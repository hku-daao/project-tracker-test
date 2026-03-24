import 'environment_config.dart';

/// Backend API (Railway) — switches with [AppEnvironment].
///
/// **Testing:** `project-tracker-test-production.up.railway.app`  
/// **Production:** `project-tracker-production-1588.up.railway.app`
///
/// Override with `--dart-define=API_BASE_URL=https://...` if needed.
///
/// See **docs/ENVIRONMENTS.md** in the repo root.
class ApiConfig {
  ApiConfig._();

  static const String _testingBaseUrl =
      'https://project-tracker-test-production.up.railway.app';
  static const String _productionBaseUrl =
      'https://project-tracker-production-1588.up.railway.app';

  /// Railway backend base URL (no trailing slash).
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;
    return AppEnvironment.isProduction ? _productionBaseUrl : _testingBaseUrl;
  }

  /// Health check path (backend returns JSON with ok: true).
  static const String healthPath = '/';
}
