import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'errors/app_exception.dart';

/// The authenticated session returned by the backend.
class AuthSession {
  const AuthSession({
    required this.user,
    this.emailConfirmed = false,
    this.sessionActive = false,
  });

  final Map<String, dynamic> user;
  final bool emailConfirmed;

  /// Whether a usable access token was persisted for this session.
  ///
  /// Signup responses that only carry a "check your email" message have no
  /// access token, so the user is not logged in until they verify their email.
  final bool sessionActive;
}

/// Repository for authentication flows.
///
/// Controllers talk to this service, which in turn uses the central
/// [ApiClient]. No widget performs raw HTTP calls.
class AuthService {
  AuthService({ApiClient? apiClient, void Function()? onUnauthorized}) {
    _apiClient = apiClient ??
        ApiClient(
          tokenProvider: readAccessToken,
          onRefreshToken: refreshAccessToken,
          onUnauthorized: onUnauthorized,
        );
  }

  late final ApiClient _apiClient;

  /// Remembers the in-flight refresh so concurrent callers (e.g. several
  /// requests that hit 401 at once) share a single token refresh instead of
  /// stampeding the auth endpoint.
  Future<bool>? _refreshInFlight;

  /// Reads the persisted access token from local storage.
  static Future<String?> readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<AuthSession> signIn(String email, String password) async {
    final response = await _apiClient.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    final session = _asSession(response.data);
    if (session != null) return session;
    throw const InvalidDataException(
      message: 'Login response did not contain a session.',
    );
  }

  Future<AuthSession?> signUp(
    String email,
    String password, {
    String fullName = '',
  }) async {
    final response = await _apiClient.post(
      '/auth/signup',
      body: {
        'email': email,
        'password': password,
        'full_name': fullName.isNotEmpty ? fullName : email.split('@').first,
      },
    );
    return _asSession(response.data);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token != null) {
      try {
        await _apiClient.post('/auth/logout', requiresAuth: true, maxRetries: 1);
      } on AppException {
        // Best-effort: always clear the local session regardless of outcome.
      }
    }
    await clearLocalSession();
  }

  /// Clears only the persisted session without contacting the backend.
  ///
  /// Used when a session is already known to be invalid (e.g. after a 401) so
  /// no further network request can cause a refresh/401 loop.
  Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('token_expires_at');
    await prefs.remove('user_data');
    await prefs.remove('email_verified');
  }

  /// Restores and validates the persisted session against the backend.
  ///
  /// Returns the validated [AuthSession], or null when the session is missing,
  /// expired, or revoked. Expired access tokens are transparently refreshed
  /// using the stored refresh token before deciding.
  Future<AuthSession?> validateSession() async {
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final response = await _apiClient.get('/auth/me', requiresAuth: true);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final profile = data['profile'];
        if (profile is Map<String, dynamic>) {
          final emailConfirmed =
              profile['email_verified'] == true ||
              profile['email_confirmed_at'] != null;
          await _updateCachedUser(profile, emailConfirmed);
          return AuthSession(
            user: profile,
            emailConfirmed: emailConfirmed,
            sessionActive: true,
          );
        }
      }
      return null;
    } on AuthenticationException {
      // The access token is invalid and could not be refreshed.
      await clearLocalSession();
      return null;
    } on AppException {
      // Network/server failures should not wipe the session; fall back to the
      // cached user so the app stays usable offline.
      return _cachedSession();
    }
  }

  Future<AuthSession?> _cachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData == null) return null;
    try {
      final user = jsonDecode(userData) as Map<String, dynamic>;
      final emailConfirmed = prefs.getBool('email_verified') ?? false;
      return AuthSession(
        user: user,
        emailConfirmed: emailConfirmed,
        sessionActive: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateCachedUser(
    Map<String, dynamic> profile,
    bool emailConfirmed,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(profile));
    await prefs.setBool('email_verified', emailConfirmed);
  }

  /// Returns a valid access token, refreshing when needed, or null.
  Future<String?> getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return null;

    final expiresAt = prefs.getInt('token_expires_at');
    if (expiresAt == null) return token;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now < expiresAt - 60) return token;

    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearLocalSession();
      return null;
    }

    final refreshed = await refreshAccessToken();
    final newToken = refreshed
        ? prefs.getString('access_token')
        : null;
    if (newToken == null) await clearLocalSession();
    return newToken;
  }

  Future<void> _persistTokens(
    String accessToken,
    String? refreshToken,
    int? expiresAt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString('refresh_token', refreshToken);
    }
    if (expiresAt != null) {
      await prefs.setInt('token_expires_at', expiresAt);
    }
  }

  /// Refreshes the persisted session using the stored refresh token.
  ///
  /// Single-flight: concurrent callers share one network refresh. Returns true
  /// when a new access token was persisted. Never throws — failures return
  /// false so callers can decide how to degrade.
  Future<bool> refreshAccessToken() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _apiClient.post(
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      final accessToken = data['access_token'];
      if (accessToken is! String || accessToken.isEmpty) return false;
      await _persistTokens(
        accessToken,
        data['refresh_token'] as String?,
        data['expires_at'] as int?,
      );
      return true;
    } on AppException {
      return false;
    }
  }

  /// Sends a password reset email for [email].
  Future<void> sendPasswordResetEmail(String email) async {
    await _apiClient.post(
      '/auth/forgot-password',
      body: {'email': email},
    );
  }

  AuthSession? _asSession(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final rawUser = data['user'];
    if (rawUser is! Map<String, dynamic>) return null;

    final accessToken = data['access_token'];
    if (accessToken is String && accessToken.isNotEmpty) {
      _persistTokens(
        accessToken,
        data['refresh_token'] as String?,
        data['expires_at'] as int?,
      );
      _persistUser(rawUser, data['email_confirmed_at'] != null);
    }

    final emailConfirmed = rawUser['email_confirmed_at'] != null ||
        data['email_confirmed_at'] != null;
    final accessTokenPersisted = accessToken is String && accessToken.isNotEmpty;
    return AuthSession(
      user: rawUser,
      emailConfirmed: emailConfirmed,
      sessionActive: accessTokenPersisted,
    );
  }

  Future<void> _persistUser(Map<String, dynamic> user, bool emailConfirmed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(user));
    await prefs.setBool('email_verified', emailConfirmed);
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      return jsonDecode(userData) as Map<String, dynamic>?;
    }
    return null;
  }
}