import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/errors/app_exception.dart';

/// The app-wide authentication state.
enum AuthState {
  /// No session restored yet (startup).
  initial,

  /// A session exists locally and is being validated against the backend.
  checking,

  /// Fully authenticated.
  authenticated,

  /// Authenticated but the email address is not verified yet.
  unverified,

  /// Signed out / session missing or invalid.
  unauthenticated,
}

class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService, void Function()? onUnauthorized})
      : _authService = authService ??
            AuthService(onUnauthorized: onUnauthorized);

  final AuthService _authService;

  bool isLoading = false;
  bool isLoggedIn = false;
  String? error;

  AuthState _state = AuthState.initial;
  AuthState get state => _state;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  bool get isEmailVerified => _state == AuthState.authenticated;

  Future<void> login(String email, String password) async {
    if (isLoading) return; // Duplicate-submission protection.
    isLoading = true;
    error = null;
    _state = AuthState.checking;
    notifyListeners();
    try {
      final session = await _authService.signIn(email, password);
      isLoggedIn = true;
      _currentUser = session.user;
      _state = session.emailConfirmed
          ? AuthState.authenticated
          : AuthState.unverified;
    } on AppException catch (e) {
      error = e.userMessage;
      _state = AuthState.unauthenticated;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
      _state = AuthState.unauthenticated;
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> signup(String email, String password,
      {String fullName = ''}) async {
    if (isLoading) return; // Duplicate-submission protection.
    isLoading = true;
    error = null;
    _state = AuthState.checking;
    notifyListeners();
    try {
      final session = await _authService.signUp(email, password,
          fullName: fullName);
      if (session != null && session.sessionActive) {
        isLoggedIn = true;
        _currentUser = session.user;
        _state = session.emailConfirmed
            ? AuthState.authenticated
            : AuthState.unverified;
      } else {
        // Signup returned no usable session — backend answered with a "check
        // your email" response. Treat as pending verification.
        isLoggedIn = false;
        _currentUser = null;
        _state = AuthState.unverified;
      }
    } on AppException catch (e) {
      error = e.userMessage;
      _state = AuthState.unauthenticated;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
      _state = AuthState.unauthenticated;
    }
    isLoading = false;
    notifyListeners();
  }

  /// Restores a persisted session and verifies it against the backend.
  Future<void> restoreSession() async {
    if (isLoading) return; // Prevent overlapping startup restores.
    _state = AuthState.checking;
    isLoading = true;
    notifyListeners();
    try {
      final session = await _authService.validateSession();
      if (session != null) {
        isLoggedIn = true;
        _currentUser = session.user;
        _state = session.emailConfirmed
            ? AuthState.authenticated
            : AuthState.unverified;
      } else {
        isLoggedIn = false;
        _currentUser = null;
        _state = AuthState.unauthenticated;
      }
    } on AppException catch (e) {
      isLoggedIn = false;
      _currentUser = null;
      error = e.userMessage;
      _state = AuthState.unauthenticated;
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    if (isLoading) return; // Prevent repeated concurrent logout.
    isLoading = true;
    notifyListeners();
    await _authService.signOut();
    _currentUser = null;
    isLoggedIn = false;
    error = null;
    _state = AuthState.unauthenticated;
    isLoading = false;
    notifyListeners();
  }

  Future<void> handleSessionExpired() async {
    await _authService.clearLocalSession();
    _currentUser = null;
    isLoggedIn = false;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (isLoading) return; // Duplicate-submission protection.
    isLoading = true;
    error = null;
    try {
      await _authService.sendPasswordResetEmail(email);
    } on AppException catch (e) {
      error = e.userMessage;
    } catch (_) {
      error = 'Failed to send reset link. Please try again.';
    } finally {
      isLoading = false;
    }
  }
}
