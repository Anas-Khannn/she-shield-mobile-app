import 'package:flutter/material.dart';

import '../services/api/api_client.dart';
import '../services/api/health_service.dart';

/// Tracks whether the backend API is reachable.
///
/// A backend outage must not block the whole app — this controller exposes a
/// [isReachable] flag that the UI uses to show an offline/degraded banner.
class HealthController extends ChangeNotifier {
  HealthController({ApiClient? apiClient})
      : _health = HealthService(apiClient ?? ApiClient());

  final HealthService _health;

  bool _isReachable = true;
  bool _isChecking = false;

  bool get isReachable => _isReachable;
  bool get isChecking => _isChecking;

  Future<void> checkHealth() async {
    _isChecking = true;
    notifyListeners();
    final reachable = await _health.isApiReachable();
    _isReachable = reachable;
    _isChecking = false;
    notifyListeners();
  }
}