import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'errors/app_exception.dart';

/// Repository for authentication flows.
///
/// Controllers talk to this service, which in turn uses the central
/// [ApiClient]. No widget performs raw HTTP calls.
class AuthService {
  AuthService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient(tokenProvider: _readToken);

  final ApiClient _apiClient;

  static Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    final response = await _apiClient.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    return _handleAuthResponse(response.data);
  }

  Future<Map<String, dynamic>?> signUp(
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
    return _handleAuthResponse(response.data);
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
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      return jsonDecode(userData) as Map<String, dynamic>?;
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }

  Future<Map<String, dynamic>?> _handleAuthResponse(dynamic data) async {
    if (data is! Map<String, dynamic>) {
      throw const InvalidDataException(
        message: 'Auth response was not a JSON object.',
      );
    }
    final accessToken = data['access_token'];
    if (accessToken is String && accessToken.isNotEmpty) {
      final refreshToken = data['refresh_token'];
      final user = data['user'];
      await _saveTokens(
        accessToken,
        refreshToken is String ? refreshToken : null,
        user is Map<String, dynamic> ? user : const {},
      );
    }
    final user = data['user'];
    return user is Map<String, dynamic> ? user : null;
  }

  Future<void> _saveTokens(
    String accessToken,
    String? refreshToken,
    Map<String, dynamic> user,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    if (refreshToken != null) {
      await prefs.setString('refresh_token', refreshToken);
    }
    await prefs.setString('user_data', jsonEncode(user));
  }
}