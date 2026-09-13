import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../errors/app_exception.dart';

/// Runtime environment for the mobile app.
enum AppEnvironment {
  development('development'),
  staging('staging'),
  production('production');

  const AppEnvironment(this.name);

  final String name;

  /// Only development is allowed to talk to a plain-http backend.
  bool get requiresSecureConnection => this != AppEnvironment.development;
}

/// Resolved API connection settings.
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    required this.environment,
    this.timeout = const Duration(seconds: 15),
  });

  final String baseUrl;
  final AppEnvironment environment;
  final Duration timeout;

  static const String environmentName = String.fromEnvironment('APP_ENV');

  /// Loopback hosts that are only valid in a development environment.
  static const Set<String> _loopbackHosts = {
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
    '::1',
  };

  /// Determines the environment.
  ///
  /// Release builds always resolve to [AppEnvironment.production], which
  /// forces the HTTPS validation below.
  static AppEnvironment detectEnvironment({bool releaseMode = kReleaseMode}) {
    if (releaseMode) return AppEnvironment.production;
    return switch (environmentName) {
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };
  }

  /// Validates and resolves the API base URL for the current environment.
  ///
  /// Development may use `http://localhost` / `http://10.0.2.2` for local
  /// development. Staging and production require HTTPS and reject anything
  /// else, regardless of what the environment file says.
  static ApiConfig resolve({
    String? envValue,
    AppEnvironment? environment,
    bool isAndroid = false,
    bool isWeb = false,
  }) {
    final resolvedEnvironment = environment ?? detectEnvironment();
    var candidate = envValue?.trim() ?? '';

    if (candidate.isEmpty) {
      if (isAndroid && !isWeb) {
        candidate = 'http://10.0.2.2:3000';
      } else {
        candidate = 'http://localhost:3000';
      }
    } else {
      final uri = Uri.tryParse(candidate);
      final host = uri?.host;
      if (host != null &&
          _loopbackHosts.contains(host) &&
          isAndroid &&
          !isWeb) {
        // The Android emulator reaches the host machine via 10.0.2.2.
        candidate = candidate.replaceFirst(Uri.parse(candidate).host, '10.0.2.2');
      }
    }

    final parsed = Uri.tryParse(candidate);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw InsecureApiConfigException(
        message: 'API_BASE_URL "$candidate" is not a valid URL.',
      );
    }

    if (resolvedEnvironment.requiresSecureConnection &&
        parsed.scheme != 'https') {
      throw InsecureApiConfigException(
        message: 'API_BASE_URL "$candidate" is not HTTPS — ${resolvedEnvironment.name} requires an HTTPS API endpoint.',
      );
    }

    return ApiConfig(
      baseUrl: candidate,
      environment: resolvedEnvironment,
    );
  }

  static AppEnvironment? _fromName(String? name) {
    return switch (name) {
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => null,
    };
  }

  /// Resolves configuration from flutter_dotenv and the current platform.
  ///
  /// `APP_ENV` can override the environment for non-release builds (used to
  /// point staging builds at a staging API). When the environment file has not
  /// been loaded yet (e.g. in tests) it safely falls back to development
  /// defaults instead of throwing.
  static ApiConfig fromEnv() {
    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    final environment =
        _fromName(env['APP_ENV']) ?? detectEnvironment(releaseMode: kReleaseMode);
    return resolve(
      envValue: env['API_BASE_URL'],
      environment: environment,
      isAndroid: !kIsWeb && Platform.isAndroid,
      isWeb: kIsWeb,
    );
  }
}