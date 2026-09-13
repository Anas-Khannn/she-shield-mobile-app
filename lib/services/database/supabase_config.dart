import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../errors/app_exception.dart';

/// The Supabase settings the Flutter app is allowed to use.
///
/// Only the public (anon) configuration is read here. The service-role key is
/// backend-only and must never be loaded by the mobile app; this class
/// actively rejects it if it appears in the Flutter environment.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  static const _serviceRoleKeyName = 'SUPABASE_SERVICE_ROLE_KEY';

  /// Validates and builds a [SupabaseConfig] from an environment map.
  ///
  /// Throws an [EnvironmentValidationException] when required variables are
  /// missing, use placeholder values, or are structurally invalid.
  static SupabaseConfig from(Map<String, String>? env) {
    final url = env?.containsKey('SUPABASE_URL') == true
        ? (env!['SUPABASE_URL']!.trim())
        : '';
    final anonKey = env?.containsKey('SUPABASE_ANON_KEY') == true
        ? (env!['SUPABASE_ANON_KEY']!.trim())
        : '';

    final missing = <String>[
      if (url.isEmpty || url.startsWith('your_')) 'SUPABASE_URL',
      if (anonKey.isEmpty || anonKey.startsWith('your_')) 'SUPABASE_ANON_KEY',
    ];

    if (missing.isNotEmpty) {
      throw EnvironmentValidationException(
        message: 'Missing required Supabase environment variables: ${missing.join(', ')}.',
      );
    }

    if (env?.containsKey(_serviceRoleKeyName) == true) {
      throw EnvironmentValidationException(
        message: 'SUPABASE_SERVICE_ROLE_KEY found in the Flutter environment. '
            'The service-role key is backend-only and must not be shipped in the app.',
      );
    }

    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null ||
        !parsedUrl.hasScheme ||
        !(parsedUrl.isScheme('https') || parsedUrl.isScheme('http')) ||
        parsedUrl.host.isEmpty) {
      throw EnvironmentValidationException(
        message: 'SUPABASE_URL "$url" is not a valid URL.',
      );
    }

    if (anonKey.length < 20) {
      throw EnvironmentValidationException(
        message: 'SUPABASE_ANON_KEY looks invalid (too short).',
      );
    }

    return SupabaseConfig(url: url, anonKey: anonKey);
  }

  /// Loads and validates the Supabase configuration from flutter_dotenv.
  static SupabaseConfig load() => from(dotenv.env);
}