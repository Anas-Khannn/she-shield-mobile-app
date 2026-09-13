import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import 'supabase_config.dart';

/// Initializes Supabase exactly once for the whole application.
///
/// [initialize] is idempotent and awaitable: concurrent callers share the same
/// in-flight initialization future, so startup is deterministic. Database
/// access is gated — calling any accessor before [initialize] completes throws
/// an [InitializationException].
class SupabaseInitializer {
  /// Pluggable for tests. Defaults to the real Supabase initialization.
  SupabaseInitializer({
    Future<void> Function(String url, String anonKey)? initializeCall,
    SupabaseConfig Function()? configProvider,
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 400),
  })  : _initializeCall = initializeCall ?? _defaultInitialize,
        _configProvider = configProvider ?? SupabaseConfig.load;

  static final SupabaseInitializer instance = SupabaseInitializer();

  static Future<void> _defaultInitialize(String url, String anonKey) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  final Future<void> Function(String url, String anonKey) _initializeCall;
  final SupabaseConfig Function() _configProvider;
  final int maxRetries;
  final Duration retryDelay;

  Future<void>? _initFuture;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Ensures Supabase is initialized.
  ///
  /// Returns immediately when already initialized and reuses the in-flight
  /// future when another caller is already initializing.
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInitialize();
  }

  /// The initialized Supabase client.
  ///
  /// Throws before [initialize] has successfully completed to prevent database
  /// access before initialization.
  SupabaseClient get client {
    if (!_initialized || _initFuture == null) {
      throw const InitializationException(
        message: 'Supabase accessed before initialization completed.',
        userMessage: 'The app is still starting up. Please wait.',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> _doInitialize() async {
    final config = _configProvider();

    Object? lastError;
    var attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        await _initializeCall(config.url, config.anonKey);
        _initialized = true;
        return;
      } catch (error) {
        lastError = error;
      }
      if (attempt < maxRetries) {
        await Future<void>.delayed(retryDelay * attempt);
      }
    }

    // Allow a later explicit retry to start from scratch.
    _initFuture = null;
    throw SupabaseInitException(
      message: 'Supabase initialization failed after $attempt attempt(s): $lastError',
    );
  }
}