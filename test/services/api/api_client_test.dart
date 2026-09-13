import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:she_shield/services/api/api_client.dart';
import 'package:she_shield/services/api/api_config.dart';
import 'package:she_shield/services/errors/app_exception.dart';

// A BaseClient that delays every response to trigger timeouts in tests.
class _DelayedClient extends http.BaseClient {
  _DelayedClient(this._duration);
  final Duration _duration;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(_duration);
    final response = http.Response('{"ok":true}', 200);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
    );
  }
}

ApiClient _makeClient(http.Client handler, {void Function()? onUnauthorized}) {
  return ApiClient(
    config: const ApiConfig(
      baseUrl: 'http://localhost:3000',
      environment: AppEnvironment.development,
      timeout: Duration(milliseconds: 80),
    ),
    httpClient: handler,
    onUnauthorized: onUnauthorized,
  );
}

void main() {
  group('ApiClient', () {
    group('successful responses', () {
      test('returns ApiResponse with decoded JSON on 200', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"user":{"id":"1"}}', 200);
        }));

        final response = await client.post(
          '/auth/login',
          body: {'email': 'a@b.com', 'password': 'pass'},
        );

        expect(response.statusCode, 200);
        expect(response.isSuccess, isTrue);
        expect(response.data, {'user': {'id': '1'}});
      });

      test('returns ApiResponse on 201 (signup)', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"user":{"id":"2"}}', 201);
        }));

        final response = await client.post('/auth/signup', body: {
          'email': 'a@b.com',
          'password': 'pass',
          'full_name': 'Test',
        });

        expect(response.statusCode, 201);
        expect(response.isSuccess, isTrue);
      });

      test('returns null data when body is empty', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('', 200);
        }));

        final response = await client.get('/health');
        expect(response.isSuccess, isTrue);
        expect(response.data, isNull);
      });
    });

    group('GET / retry on network error', () {
      test('retries and succeeds on second attempt', () async {
        var callCount = 0;
        final client = _makeClient(MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            throw http.ClientException('Connection reset');
          }
          return http.Response('{"data":"ok"}', 200);
        }));

        final response = await client.get(
          '/health',
          maxRetries: 2,
          retryOnNetworkError: true,
        );

        expect(response.isSuccess, isTrue);
        expect(callCount, 2);
      });

      test('throws NetworkException after all retries fail', () async {
        final client = _makeClient(MockClient((request) async {
          throw http.ClientException('Connection reset');
        }));

        expect(
          () => client.get(
            '/health',
            maxRetries: 2,
            retryOnNetworkError: true,
          ),
          throwsA(isA<NetworkException>()),
        );
      });
    });

    group('POST does not retry on network error', () {
      test('throws after first failure without retrying', () async {
        var callCount = 0;
        final client = _makeClient(MockClient((request) async {
          callCount++;
          throw http.ClientException('Connection reset');
        }));

        await expectLater(
          client.post('/auth/login', body: {'e': 'p'}),
          throwsA(isA<NetworkException>()),
        );
        expect(callCount, 1);
      });
    });

    group('status code error mapping', () {
      test('401 throws AuthenticationException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response(
            '{"error":"Unauthorized","message":"Invalid credentials"}',
            401,
          );
        }));

        expect(
          () => client.get('/auth/me'),
          throwsA(
            isA<AuthenticationException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('Invalid credentials'),
            ),
          ),
        );
      });

      test('401 calls onUnauthorized callback', () async {
        var unauthorizedCalled = false;
        final client = _makeClient(
          MockClient((request) async {
            return http.Response('{"message":"Unauthorized"}', 401);
          }),
          onUnauthorized: () => unauthorizedCalled = true,
        );

        await expectLater(
          client.get('/auth/me'),
          throwsA(isA<AuthenticationException>()),
        );
        expect(unauthorizedCalled, isTrue);
      });

      test('403 throws AuthorizationException with server message', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response(
            '{"error":"Forbidden","message":"Account suspended"}',
            403,
          );
        }));

        expect(
          () => client.get('/auth/me'),
          throwsA(
            isA<AuthorizationException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('Account suspended'),
            ),
          ),
        );
      });

      test('404 throws NotFoundException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"error":"Not Found"}', 404);
        }));

        expect(
          () => client.get('/does-not-exist'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('422 throws ValidationException with server message', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response(
            '{"error":"Validation Error","message":"Email already exists"}',
            422,
          );
        }));

        expect(
          () => client.post('/auth/signup', body: {}),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.userMessage,
              'userMessage',
              contains('Email already exists'),
            ),
          ),
        );
      });

      test('429 throws RateLimitException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"error":"Too Many Requests"}', 429);
        }));

        expect(
          () => client.get('/health'),
          throwsA(isA<RateLimitException>()),
        );
      });

      test('500 throws ServerException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"error":"Internal Server Error"}', 500);
        }));

        expect(
          () => client.get('/health'),
          throwsA(isA<ServerException>()),
        );
      });

      test('503 throws ServerException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response('{"error":"Service Unavailable"}', 503);
        }));

        expect(
          () => client.get('/health'),
          throwsA(isA<ServerException>()),
        );
      });

      test('400 throws ValidationException', () async {
        final client = _makeClient(MockClient((request) async {
          return http.Response(
            '{"error":"Validation Error","message":"email is required"}',
            400,
          );
        }));

        expect(
          () => client.post('/auth/login', body: {}),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('timeout', () {
      test('throws ApiTimeoutException when the request exceeds timeout',
          () async {
        final client = _makeClient(_DelayedClient(
          const Duration(milliseconds: 500),
        ));

        expect(
          () => client.get('/health'),
          throwsA(isA<ApiTimeoutException>()),
        );
      });
    });

    group('network unavailable', () {
      test('throws NetworkException on ClientException (web/network)', () async {
        final client = _makeClient(MockClient((request) async {
          throw http.ClientException('Connection closed before full response');
        }));

        expect(
          () => client.post('/auth/login', body: {}),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.message,
              'message',
              contains('Connection closed'),
            ),
          ),
        );
      });
    });

    group('authorization header', () {
      test('includes Bearer token when requiresAuth is true', () async {
        String? receivedAuth;
        final client = ApiClient(
          config: const ApiConfig(
            baseUrl: 'http://localhost:3000',
            environment: AppEnvironment.development,
          ),
          httpClient: MockClient((request) async {
            receivedAuth = request.headers['Authorization'];
            return http.Response('{"ok":true}', 200);
          }),
          tokenProvider: () async => 'test-access-token-abc',
        );

        await client.get('/auth/me', requiresAuth: true);
        expect(receivedAuth, 'Bearer test-access-token-abc');
      });

      test('throws AuthenticationException when token is null', () async {
        final client = ApiClient(
          config: const ApiConfig(
            baseUrl: 'http://localhost:3000',
            environment: AppEnvironment.development,
          ),
          httpClient: MockClient((request) async {
            return http.Response('{}', 200);
          }),
          tokenProvider: () async => null,
        );

        expect(
          () => client.get('/auth/me', requiresAuth: true),
          throwsA(
            isA<AuthenticationException>().having(
              (e) => e.message,
              'message',
              contains('No access token'),
            ),
          ),
        );
      });
    });
  });
}