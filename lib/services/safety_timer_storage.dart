import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/safety_timer_state.dart';

/// Persists the active safety timer across navigation, app lifecycle
/// transitions, and app restarts.
///
/// Reuses the same [SharedPreferences] mechanism the contacts feature already
/// uses. Only timer fields are stored — never secrets or contact data.
class SafetyTimerStorage {
  static const String storageKey = 'safety_timer_state';

  /// Loads the persisted timer, or `null` when nothing is saved.
  Future<SafetyTimerRecord?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SafetyTimerRecord.fromStorage(prefs.getString(storageKey));
    } catch (_) {
      return null;
    }
  }

  /// Persists [record] atomically as a single JSON string.
  Future<void> save(SafetyTimerRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(record.toJson()));
  }

  /// Removes any persisted timer.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}