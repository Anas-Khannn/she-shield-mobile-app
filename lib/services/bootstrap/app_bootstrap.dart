import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../database/supabase_initializer.dart';

/// The single, awaited application startup path.
///
/// Ordering is deterministic:
/// 1. load environment variables,
/// 2. validate them,
/// 3. initialize Supabase exactly once,
/// and only then is the app UI mounted.
class AppBootstrap {
  AppBootstrap({SupabaseInitializer? supabaseInitializer})
      : _supabase = supabaseInitializer ?? SupabaseInitializer.instance;

  final SupabaseInitializer _supabase;

  Future<void> initialize() async {
    await dotenv.load(fileName: '.env');
    await _supabase.initialize();
  }
}