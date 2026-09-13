import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/auth_controller.dart';
import 'package:she_shield/services/api/api_client.dart';
import 'package:she_shield/services/api/api_config.dart';
import 'package:she_shield/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthController', () {
    AuthController makeController(http.Client httpClient) {
      final apiClient = ApiClient(
        config: const ApiConfig(
          baseUrl: 'http://localhost:3000',
          environment: AppEnvironment.development,
          timeout: Duration(seconds: 5),
        ),
        httpClient: httpClient,
      );
      return AuthController(authService: AuthService(apiClient: apiClient));
    }

    test('login success sets isLoggedIn and currentUser', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"access_token":"tok","refresh_token":"ref","user":{"id":"1","email":"a@b.com"}}',
          200,
        );
      }));

      await controller.login('a@b.com', 'password123');

      expect(controller.isLoggedIn, isTrue);
      expect(controller.currentUser, {'id': '1', 'email': 'a@b.com'});
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
    });

    test('login failure sets user-facing error message', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"error":"Authentication Failed","message":"Invalid email or password."}',
          401,
        );
      }));

      await controller.login('a@b.com', 'wrong');

      expect(controller.isLoggedIn, isFalse);
      expect(controller.currentUser, isNull);
      expect(controller.error, contains('Invalid email or password.'));
      expect(controller.isLoading, isFalse);
    });

    test('login network error sets friendly offline message', () async {
      final controller = makeController(MockClient((request) async {
        throw http.ClientException('Connection refused');
      }));

      await controller.login('a@b.com', 'password');

      expect(controller.error, contains('No connection'));
      expect(controller.isLoading, isFalse);
    });

    test('signup success sets isLoggedIn', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"user":{"id":"3","email":"new@b.com"}}',
          201,
        );
      }));

      await controller.signup('new@b.com', 'password123', fullName: 'Test');

      expect(controller.isLoggedIn, isTrue);
      expect(controller.error, isNull);
    });

    test('signup failure sets user-facing error', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"error":"Validation Error","message":"email already exists"}',
          400,
        );
      }));

      await controller.signup('dup@b.com', 'password123');

      expect(controller.isLoggedIn, isFalse);
      expect(controller.error, contains('email already exists'));
    });

    test('logout clears user state', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response('{"message":"Logged out successfully."}', 200);
      }));

      await controller.login('a@b.com', 'password123');
      await controller.logout();

      expect(controller.isLoggedIn, isFalse);
      expect(controller.currentUser, isNull);
    });

    test('logout handles network failure gracefully', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"access_token":"tok","refresh_token":"ref","user":{"id":"1","email":"a@b.com"}}',
          200,
        );
      }));

      await controller.login('a@b.com', 'password123');

      final offlineController = makeController(MockClient((request) async {
        throw http.ClientException('Network down');
      }));
      await offlineController.logout();
      expect(offlineController.isLoggedIn, isFalse);
    });

    test('checkSession restores a cached user from prefs', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"access_token":"tok","user":{"id":"1","email":"a@b.com"}}',
          200,
        );
      }));

      await controller.login('a@b.com', 'pass');

      final controller2 = makeController(MockClient((request) async {
        return http.Response('{}', 200);
      }));
      await controller2.checkSession();

      expect(controller2.isLoggedIn, isTrue);
      expect(controller2.currentUser, {'id': '1', 'email': 'a@b.com'});
    });
  });
}