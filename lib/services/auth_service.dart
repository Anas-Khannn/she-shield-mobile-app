import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  /// Returns the correct base URL depending on environment:
  /// - Uses API_BASE_URL from .env if explicitly set to a non-localhost value
  /// - Falls back to 10.0.2.2:3000 for Android emulator
  /// - Falls back to localhost:3000 for iOS simulator / web
  String get baseUrl {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null &&
        envUrl.isNotEmpty &&
        envUrl != 'http://localhost:3000') {
      return envUrl;
    }
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(
            data['access_token'], data['refresh_token'], data['user']);
        return data['user'];
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Login failed');
      }
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('Connection refused') ||
          msg.contains('SocketException') ||
          msg.contains('TimeoutException')) {
        throw Exception(
            'Cannot connect to server. Make sure the backend is running.');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> signUp(
    String email,
    String password, {
    String fullName = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'full_name':
                  fullName.isNotEmpty ? fullName : email.split('@').first,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['user'];
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Signup failed');
      }
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('Connection refused') ||
          msg.contains('SocketException') ||
          msg.contains('TimeoutException')) {
        throw Exception(
            'Cannot connect to server. Make sure the backend is running.');
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        // Ignore network errors on logout — clear local session regardless
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
      return jsonDecode(userData);
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
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