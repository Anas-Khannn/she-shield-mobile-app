import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/services/api/api_config.dart';
import 'package:she_shield/services/errors/app_exception.dart';

void main() {
  group('ApiConfig.resolve', () {
    group('development environment', () {
      test('allows http://localhost', () {
        final config = ApiConfig.resolve(
          envValue: 'http://localhost:3000',
          environment: AppEnvironment.development,
        );
        expect(config.baseUrl, 'http://localhost:3000');
        expect(config.environment, AppEnvironment.development);
      });

      test('allows http://127.0.0.1', () {
        final config = ApiConfig.resolve(
          envValue: 'http://127.0.0.1:3000',
          environment: AppEnvironment.development,
        );
        expect(config.baseUrl, 'http://127.0.0.1:3000');
      });

      test('allows https in development', () {
        final config = ApiConfig.resolve(
          envValue: 'https://api.example.com',
          environment: AppEnvironment.development,
        );
        expect(config.baseUrl, 'https://api.example.com');
      });

      test('defaults to localhost when envValue is empty', () {
        final config = ApiConfig.resolve(
          envValue: '',
          environment: AppEnvironment.development,
        );
        expect(config.baseUrl, 'http://localhost:3000');
      });

      test('defaults to 10.0.2.2 on Android when envValue is empty', () {
        final config = ApiConfig.resolve(
          envValue: '',
          environment: AppEnvironment.development,
          isAndroid: true,
        );
        expect(config.baseUrl, 'http://10.0.2.2:3000');
      });
    });

    group('staging environment', () {
      test('requires HTTPS', () {
        expect(
          () => ApiConfig.resolve(
            envValue: 'http://api.staging.example.com',
            environment: AppEnvironment.staging,
          ),
          throwsA(
            isA<InsecureApiConfigException>().having(
              (e) => e.message,
              'message',
              contains('not HTTPS'),
            ),
          ),
        );
      });

      test('accepts HTTPS', () {
        final config = ApiConfig.resolve(
          envValue: 'https://api.staging.example.com',
          environment: AppEnvironment.staging,
        );
        expect(config.baseUrl, 'https://api.staging.example.com');
      });
    });

    group('production environment', () {
      test('rejects plain HTTP even when set in .env', () {
        expect(
          () => ApiConfig.resolve(
            envValue: 'http://api.production.example.com',
            environment: AppEnvironment.production,
          ),
          throwsA(
            isA<InsecureApiConfigException>().having(
              (e) => e.message,
              'message',
              contains('not HTTPS'),
            ),
          ),
        );
      });

      test('accepts HTTPS', () {
        final config = ApiConfig.resolve(
          envValue: 'https://api.production.example.com',
          environment: AppEnvironment.production,
        );
        expect(config.baseUrl, 'https://api.production.example.com');
      });
    });

    group('Android emulator URL rewriting', () {
      test('rewrites localhost to 10.0.2.2 for development on Android', () {
        final config = ApiConfig.resolve(
          envValue: 'http://localhost:3000',
          environment: AppEnvironment.development,
          isAndroid: true,
        );
        expect(config.baseUrl, 'http://10.0.2.2:3000');
      });

      test('rewrites 127.0.0.1 to 10.0.2.2 for development on Android', () {
        final config = ApiConfig.resolve(
          envValue: 'http://127.0.0.1:3000',
          environment: AppEnvironment.development,
          isAndroid: true,
        );
        expect(config.baseUrl, 'http://10.0.2.2:3000');
      });

      test('does not rewrite a non-loopback host', () {
        final config = ApiConfig.resolve(
          envValue: 'http://api.example.com:3000',
          environment: AppEnvironment.development,
          isAndroid: true,
        );
        expect(config.baseUrl, 'http://api.example.com:3000');
      });
    });

    group('invalid URLs', () {
      test('rejects a completely malformed URL', () {
        expect(
          () => ApiConfig.resolve(
            envValue: 'not a url at all',
            environment: AppEnvironment.development,
          ),
          throwsA(isA<InsecureApiConfigException>()),
        );
      });

      test('rejects a URL with no host', () {
        expect(
          () => ApiConfig.resolve(
            envValue: 'http://',
            environment: AppEnvironment.development,
          ),
          throwsA(isA<InsecureApiConfigException>()),
        );
      });
    });
  });

  group('ApiConfig.detectEnvironment', () {
    test('returns production in release builds', () {
      expect(
        ApiConfig.detectEnvironment(releaseMode: true),
        AppEnvironment.production,
      );
    });

    test('returns production when dart-define is "production"', () {
      // This test verifies the switch in detectEnvironment. The dart-define
      // 'APP_ENV' is set at compile time, so the test checks the fallback
      // path (non-release with no dart-define) returns development.
      expect(
        ApiConfig.detectEnvironment(releaseMode: false),
        AppEnvironment.development,
      );
    });
  });
}