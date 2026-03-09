/// API configuration for the HRMS backend.
///
/// To switch between localhost and LAN deployment, use ONE of:
/// - Edit config/api_base_url.txt, then run via scripts/run_flutter.bat (or .sh)
/// - flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3000
/// See docs/LAN_DEPLOYMENT.md for full setup.
class ApiConfig {
  ApiConfig._();

  /// Base URL for the backend API.
  /// Default: http://localhost:3000 (dev).
  static String get baseUrl {
    const url = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return url.isNotEmpty ? url : 'http://localhost:3000';
  }
}
