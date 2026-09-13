import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/services/errors/app_exception.dart';
import 'package:she_shield/services/database/supabase_config.dart';

void main() {
  group('SupabaseConfig', () {
    test('accepts valid SUPABASE_URL and SUPABASE_ANON_KEY', () {
      final config = SupabaseConfig.from({
        'SUPABASE_URL': 'https://zplrwuxcahqqyamvwycp.supabase.co',
        'SUPABASE_ANON_KEY': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.validkey',
      });
      expect(config.url, 'https://zplrwuxcahqqyamvwycp.supabase.co');
      expect(config.anonKey, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.validkey');
    });

    test('trims whitespace from values', () {
      final config = SupabaseConfig.from({
        'SUPABASE_URL': '  https://a.supabase.co  ',
        'SUPABASE_ANON_KEY': '  abc123456789012345678901234567890  ',
      });
      expect(config.url, 'https://a.supabase.co');
      expect(config.anonKey, 'abc123456789012345678901234567890');
    });

    test('throws EnvironmentValidationException when SUPABASE_URL is missing',
        () {
      expect(
        () => SupabaseConfig.from({'SUPABASE_ANON_KEY': 'validkey1234567890123'}),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('SUPABASE_URL'),
          ),
        ),
      );
    });

    test('throws when SUPABASE_ANON_KEY is missing', () {
      expect(
        () => SupabaseConfig.from({'SUPABASE_URL': 'https://x.supabase.co'}),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('SUPABASE_ANON_KEY'),
          ),
        ),
      );
    });

    test('throws when both are missing and message lists both', () {
      expect(
        () => SupabaseConfig.from(null),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('SUPABASE_URL'), contains('SUPABASE_ANON_KEY')),
          ),
        ),
      );
    });

    test('throws for placeholder "your_*" values', () {
      expect(
        () => SupabaseConfig.from({
          'SUPABASE_URL': 'your_supabase_url_here',
          'SUPABASE_ANON_KEY': 'your_supabase_anon_key_here',
        }),
        throwsA(isA<EnvironmentValidationException>()),
      );
    });

    test('rejects SUPABASE_SERVICE_ROLE_KEY when present in Flutter config',
        () {
      expect(
        () => SupabaseConfig.from({
          'SUPABASE_URL': 'https://x.supabase.co',
          'SUPABASE_ANON_KEY': 'validkey12345678901234567890',
          'SUPABASE_SERVICE_ROLE_KEY': 'shh',
        }),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('SUPABASE_SERVICE_ROLE_KEY'),
          ),
        ),
      );
    });

    test('throws for invalid SUPABASE_URL', () {
      expect(
        () => SupabaseConfig.from({
          'SUPABASE_URL': 'not a url',
          'SUPABASE_ANON_KEY': 'validkey12345678901234567890',
        }),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('not a valid URL'),
          ),
        ),
      );
    });

    test('throws for a short SUPABASE_ANON_KEY', () {
      expect(
        () => SupabaseConfig.from({
          'SUPABASE_URL': 'https://x.supabase.co',
          'SUPABASE_ANON_KEY': 'short',
        }),
        throwsA(
          isA<EnvironmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('too short'),
          ),
        ),
      );
    });
  });
}