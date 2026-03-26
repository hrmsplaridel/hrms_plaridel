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

  /// When true, recruitment attachments upload to the API (`uploads/rsp-attachments`)
  /// instead of Supabase. Defaults to on for localhost/LAN-style API hosts so dev
  /// works without Supabase. For production using Supabase only, set
  /// `--dart-define=RSP_LOCAL_ATTACHMENTS=false`.
  static bool get useLocalRspStorage {
    const s = String.fromEnvironment('RSP_LOCAL_ATTACHMENTS', defaultValue: '');
    final v = s.toLowerCase();
    if (v == '1' || v == 'true' || v == 'yes') return true;
    if (v == '0' || v == 'false' || v == 'no') return false;
    final uri = Uri.tryParse(baseUrl);
    final host = (uri?.host ?? '').toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') return true;
    return _isPrivateLanHost(host);
  }

  static bool _isPrivateLanHost(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}
