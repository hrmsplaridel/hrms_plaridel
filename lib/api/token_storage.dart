import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists and retrieves the JWT for API auth.
/// Uses [FlutterSecureStorage]; on web it falls back to in-memory–like behavior
/// per package docs.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  static const String _key = 'hrms_jwt';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Returns the stored JWT, or null if none.
  Future<String?> getToken() async {
    return _storage.read(key: _key);
  }

  /// Saves the JWT (e.g. after login). Pass null to clear.
  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: token);
    }
  }

  /// Removes the stored JWT (e.g. on sign out).
  Future<void> clearToken() async {
    await _storage.delete(key: _key);
  }
}
