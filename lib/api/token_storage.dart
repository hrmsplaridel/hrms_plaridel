import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists access and refresh JWTs for API auth.
/// Uses [FlutterSecureStorage]; on web it falls back to in-memory–like behavior
/// per package docs.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  /// Access token (same key as legacy single-JWT installs).
  static const String _keyAccess = 'hrms_jwt';
  static const String _keyRefresh = 'hrms_refresh_jwt';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Returns the stored access JWT, or null if none.
  Future<String?> getToken() async {
    return _storage.read(key: _keyAccess);
  }

  /// Saves only the access token. Prefer [setTokens] after login.
  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await clearAllTokens();
    } else {
      await _storage.write(key: _keyAccess, value: token);
    }
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _keyRefresh);
  }

  /// Saves access token and optional refresh token (clears refresh if null/empty).
  Future<void> setTokens({required String access, String? refresh}) async {
    await _storage.write(key: _keyAccess, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.write(key: _keyRefresh, value: refresh);
    } else {
      await _storage.delete(key: _keyRefresh);
    }
  }

  /// Removes both tokens (e.g. on sign out or auth failure).
  Future<void> clearAllTokens() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }

  /// Same as [clearAllTokens] (legacy name).
  Future<void> clearToken() async {
    await clearAllTokens();
  }
}
