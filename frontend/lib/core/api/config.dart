/// API configuration for the HRMS backend.
///
/// To switch between localhost and LAN deployment, use ONE of:
/// - Edit config/api_base_url.txt, then run via scripts/run_flutter.bat (or .sh)
/// - flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3000
/// Private deployment instructions are kept outside version control.
class ApiConfig {
  ApiConfig._();

  /// Base URL for the backend API.
  /// Default: http://127.0.0.1:3000 (dev).
  /// Prefer 127.0.0.1 over localhost on Windows/Chrome: localhost can resolve
  /// to ::1 while the API often listens on IPv4 only (0.0.0.0:3000).
  static String get baseUrl {
    const url = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return url.isNotEmpty ? url : 'http://127.0.0.1:3000';
  }

  /// Recruitment attachments are always stored on the API under `uploads/rsp-attachments`.
  /// Kept for compatibility; always true (external object storage is not used).
  static bool get useLocalRspStorage => true;
}
