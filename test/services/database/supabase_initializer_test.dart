import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/services/errors/app_exception.dart';
import 'package:she_shield/services/database/supabase_config.dart';
import 'package:she_shield/services/database/supabase_initializer.dart';

const _testConfig = SupabaseConfig(
  url: 'https://example.supabase.co',
  anonKey: 'test-anon-key-1234567890',
);

void main() {
  group('SupabaseInitializer', () {
    test('marks as initialized after a successful init call', () async {
      var callCount = 0;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        initializeCall: (url, anonKey) async {
          callCount++;
        },
      );

      expect(init.isInitialized, isFalse);
      await init.initialize();
      expect(init.isInitialized, isTrue);
      expect(callCount, 1);
    });

    test('initialize() is idempotent — only one init call is made', () async {
      var callCount = 0;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        initializeCall: (url, anonKey) async {
          callCount++;
        },
      );

      await Future.wait([
        init.initialize(),
        init.initialize(),
        init.initialize(),
      ]);

      expect(init.isInitialized, isTrue);
      expect(callCount, 1);
    });

    test('passes the validated config to the init call', () async {
      String? receivedUrl;
      String? receivedAnonKey;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        initializeCall: (url, anonKey) async {
          receivedUrl = url;
          receivedAnonKey = anonKey;
        },
      );

      await init.initialize();
      expect(receivedUrl, _testConfig.url);
      expect(receivedAnonKey, _testConfig.anonKey);
    });

    test('retries on failure and eventually succeeds', () async {
      var callCount = 0;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        maxRetries: 3,
        retryDelay: Duration.zero,
        initializeCall: (url, anonKey) async {
          callCount++;
          if (callCount < 3) throw Exception('Transient failure');
        },
      );

      await init.initialize();
      expect(init.isInitialized, isTrue);
      expect(callCount, 3);
    });

    test('throws SupabaseInitException after all retries exhausted', () async {
      var callCount = 0;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        maxRetries: 2,
        retryDelay: Duration.zero,
        initializeCall: (url, anonKey) async {
          callCount++;
          throw Exception('Permanent failure');
        },
      );

      await expectLater(
        init.initialize(),
        throwsA(
          isA<SupabaseInitException>().having(
            (e) => e.message,
            'message',
            contains('2 attempt'),
          ),
        ),
      );
      expect(callCount, 2);
    });

    test('can be retried after a previous failure', () async {
      var callCount = 0;
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        maxRetries: 1,
        retryDelay: Duration.zero,
        initializeCall: (url, anonKey) async {
          callCount++;
          if (callCount == 1) throw Exception('First attempt fails');
        },
      );

      await expectLater(
        init.initialize(),
        throwsA(isA<SupabaseInitException>()),
      );
      expect(init.isInitialized, isFalse);

      // The initializer resets itself after a failure, so a later call
      // retries from scratch.
      await init.initialize();
      expect(init.isInitialized, isTrue);
      expect(callCount, 2);
    });

    test('a failing config provider surfaces the environment error', () async {
      final init = SupabaseInitializer(
        configProvider: () => SupabaseConfig.from({'SUPABASE_ANON_KEY': 'x'}),
        initializeCall: (url, anonKey) async {},
      );

      await expectLater(
        init.initialize(),
        throwsA(isA<EnvironmentValidationException>()),
      );
    });

    test('client getter throws InitializationException before init completes',
        () {
      final init = SupabaseInitializer(
        configProvider: () => _testConfig,
        initializeCall: (url, anonKey) async {},
      );

      expect(
        () => init.client,
        throwsA(isA<InitializationException>()),
      );
    });
  });
}