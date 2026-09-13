import '../errors/app_exception.dart';
import 'api_client.dart';

/// Probes the backend `/health` endpoint to determine API reachability.
///
/// A failing health check never throws — it returns `false` so the rest of the
/// app can degrade gracefully instead of becoming unusable.
class HealthService {
  const HealthService(this._apiClient);

  final ApiClient _apiClient;

  Future<bool> isApiReachable() async {
    try {
      final response = await _apiClient.get(
        '/health',
        retryOnNetworkError: false,
      );
      return response.statusCode == 200;
    } on ApiException {
      return false;
    }
  }
}