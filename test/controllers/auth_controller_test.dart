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
AuthController makeController(http.Client httpClient,
        {void Function()? onUnauthorized}) {
      final apiClient = ApiClient(
        config: const ApiConfig(
          baseUrl: 'http://localhost:3000',
          environment: AppEnvironment.development,
          timeout: Duration(seconds: 5),
        ),
        httpClient: httpClient,
        tokenProvider: AuthService.readAccessToken,
        onUnauthorized: onUnauthorized,
      );
      return AuthController(authService: AuthService(apiClient: apiClient));
    }

    String verifiedUserJson() {
      final expiresAt = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
      return '{"access_token":"tok","refresh_token":"ref","expires_at":$expiresAt,'
          '"user":{"id":"1","email":"a@b.com","email_confirmed_at":"2024-01-01T00:00:00Z"}}';
    }

    test('login success sets isLoggedIn and currentUser', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(verifiedUserJson(), 200);
      }));

      await controller.login('a@b.com', 'password123');

      expect(controller.isLoggedIn, isTrue);
      expect(controller.state, AuthState.authenticated);
      expect(controller.currentUser?['email'], 'a@b.com');
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
    });

    test('login with unverified email sets unverified state', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"access_token":"tok","user":{"id":"1","email":"a@b.com"}}',
          200,
        );
      }));

      await controller.login('a@b.com', 'password123');

      expect(controller.isLoggedIn, isTrue);
      expect(controller.state, AuthState.unverified);
      expect(controller.isEmailVerified, isFalse);
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
      expect(controller.state, AuthState.unauthenticated);
      expect(controller.currentUser, isNull);
      expect(controller.error, contains('Invalid email or password.'));
      expect(controller.isLoading, isFalse);
    });

    test('login email verification required shows specific message', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"error":"Email Not Verified","message":"Your email has not been verified yet."}',
          403,
        );
      }));

      await controller.login('a@b.com', 'password123');

      expect(controller.isLoggedIn, isFalse);
      expect(controller.error, contains('not been verified'));
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
          '{"access_token":"tok","user":{"id":"3","email":"new@b.com","email_confirmed_at":"2024-01-01T00:00:00Z"}}',
          201,
        );
      }));

      await controller.signup('new@b.com', 'password123', fullName: 'Test');

      expect(controller.isLoggedIn, isTrue);
      expect(controller.state, AuthState.authenticated);
      expect(controller.error, isNull);
    });

    test('signup without session routes to email verification', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"message":"Account created! Please check your email.","user":{"id":"3","email":"new@b.com"}}',
          201,
        );
      }));

      await controller.signup('new@b.com', 'password123', fullName: 'Test');

      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unverified);
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
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return http.Response(verifiedUserJson(), 200);
        }
        return http.Response('{"message":"Logged out successfully."}', 200);
      }));

      await controller.login('a@b.com', 'password123');
      await controller.logout();

      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unauthenticated);
      expect(controller.currentUser, isNull);
    });

    test('logout handles network failure gracefully', () async {
      final controller = makeController(MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return http.Response(verifiedUserJson(), 200);
        }
        throw http.ClientException('Network down');
      }));

      await controller.login('a@b.com', 'password123');

      await controller.logout();
      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unauthenticated);
    });

    test('restoreSession validates against backend and restores user',
        () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'tok',
        'refresh_token': 'ref',
        'user_data': '{"id":"1","email":"a@b.com"}',
      });

      final controller = makeController(MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/refresh')) {
          return http.Response(
            '{"access_token":"tok2","refresh_token":"ref2","expires_at":${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600}}',
            200,
          );
        }
        return http.Response(
          '{"profile":{"id":"1","email":"a@b.com","email_verified":true}}',
          200,
        );
      }));

      await controller.restoreSession();

      expect(controller.isLoggedIn, isTrue);
      expect(controller.state, AuthState.authenticated);
      expect(controller.currentUser?['email'], 'a@b.com');
    });

    test('restoreSession refreshes an expired access token', () async {
      final expired = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 600;
      SharedPreferences.setMockInitialValues({
        'access_token': 'expired-tok',
        'refresh_token': 'valid-ref',
        'token_expires_at': expired,
        'user_data': '{"id":"1","email":"a@b.com"}',
      });

      var refreshCalled = false;
      final controller = makeController(MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/refresh')) {
          refreshCalled = true;
          return http.Response(
            '{"access_token":"fresh-tok","refresh_token":"valid-ref","expires_at":${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600}}',
            200,
          );
        }
        return http.Response(
          '{"profile":{"id":"1","email":"a@b.com","email_verified":true}}',
          200,
        );
      }));

      await controller.restoreSession();

      expect(refreshCalled, isTrue);
      expect(controller.isLoggedIn, isTrue);
      expect(controller.state, AuthState.authenticated);
    });

    test('restoreSession with expired token that cannot refresh logs out',
        () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'expired-tok',
        'refresh_token': 'bad-ref',
        'token_expires_at': (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 600,
        'user_data': '{"id":"1","email":"a@b.com"}',
      });

      final controller = makeController(MockClient((request) async {
        return http.Response(
          '{"error":"Token Refresh Failed","message":"Please log in again."}',
          401,
        );
      }));

      await controller.restoreSession();

      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unauthenticated);
      expect(controller.currentUser, isNull);
    });

    test('restoreSession with no stored token shows login', () async {
      final controller = makeController(MockClient((request) async {
        return http.Response('{}', 200);
      }));

      await controller.restoreSession();

      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unauthenticated);
    });

    test('restoreSession falls back to cached user on network failure',
        () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'tok',
        'user_data': '{"id":"1","email":"a@b.com"}',
        'email_verified': true,
      });

      final controller = makeController(MockClient((request) async {
        throw http.ClientException('Network down');
      }));

      await controller.restoreSession();

      expect(controller.isLoggedIn, isTrue);
      expect(controller.currentUser?['email'], 'a@b.com');
    });

    test('handleSessionExpired clears local session without network call',
        () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'tok',
        'refresh_token': 'ref',
        'user_data': '{"id":"1","email":"a@b.com"}',
      });

      final controller = makeController(MockClient((request) async {
        return http.Response('{}', 200);
      }));

      await controller.restoreSession();

      // Force a 401 by failing validation first — but here we simply invoke
      // handleSessionExpired directly to assert state is cleared.
      await controller.handleSessionExpired();

      expect(controller.isLoggedIn, isFalse);
      expect(controller.state, AuthState.unauthenticated);
      expect(controller.currentUser, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), isNull);
      expect(prefs.getString('user_data'), isNull);
    });

    test('onUnauthorized fires when a requiresAuth call returns 401', () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'tok',
        'refresh_token': 'ref',
        'user_data': '{"id":"1","email":"a@b.com"}',
      });
      var unauthorizedCalled = 0;
      final controller = makeController(
        MockClient((request) async {
          return http.Response(
            '{"error":"Unauthorized","message":"Invalid or expired token."}',
            401,
          );
        }),
        onUnauthorized: () => unauthorizedCalled++,
      );

      await controller.restoreSession();

      expect(unauthorizedCalled, greaterThan(0));
      expect(controller.isLoggedIn, isFalse);
    });
  });
}
