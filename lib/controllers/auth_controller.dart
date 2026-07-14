import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class AuthController with ChangeNotifier {
  final AuthService _authService = AuthService();

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
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> signup(String email, String password) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final user = await _authService.signUp(email, password);
      if (user != null) {
        isLoggedIn = true;
        _currentUser = user;
      }
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
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
    notifyListeners();
  }
}