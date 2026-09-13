import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/errors/app_exception.dart';

class AuthController with ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  bool isLoading = false;
  bool isLoggedIn = false;
  String? error;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  Future<void> login(String email, String password) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final user = await _authService.signIn(email, password);
      if (user != null) {
        isLoggedIn = true;
        _currentUser = user;
      }
    } on AppException catch (e) {
      error = e.userMessage;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> signup(String email, String password, {String fullName = ''}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final user = await _authService.signUp(email, password, fullName: fullName);
      if (user != null) {
        isLoggedIn = true;
        _currentUser = user;
      }
    } on AppException catch (e) {
      error = e.userMessage;
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> checkSession() async {
    final user = await _authService.getCurrentUser();
    isLoggedIn = user != null;
    _currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.signOut();
    isLoggedIn = false;
    _currentUser = null;
    error = null;
    notifyListeners();
  }
}