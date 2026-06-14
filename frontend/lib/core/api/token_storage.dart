import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists access and refresh JWTs for API auth.
/// Uses [FlutterSecureStorage]; on web it falls back to in-memory–like behavior
/// per package docs.
///
/// ⚠️ Android note: encryptedSharedPreferences can deadlock on first Keystore
/// access (especially inside Dio interceptors). We disable it here and use the
/// standard Android Keystore path instead, which is still encrypted at rest.
/// All calls are also wrapped in a 5-second timeout as a safety net.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  /// Access token (same key as legacy single-JWT installs).
  static const String _keyAccess = 'hrms_jwt';
  static const String _keyRefresh = 'hrms_refresh_jwt';

  static const _kTimeout = Duration(seconds: 5);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    // encryptedSharedPreferences: true has a known Android bug where it can
    // block indefinitely the first time the Keystore is accessed (e.g. from
    // inside a Dio interceptor). The default (false) still encrypts via the
    // Android Keystore but uses a non-blocking AES key derivation.
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,
      // If old tokens were encrypted with a different scheme (e.g. after
      // switching encryptedSharedPreferences), BAD_DECRYPT will occur.
      // resetOnError clears all stale data automatically so the user can
      // simply log in again instead of the app crashing or hanging.
      resetOnError: true,
    ),
  );

  Future<T?> _safe<T>(Future<T?> Function() fn) async {
    try {
      return await fn().timeout(_kTimeout);
    } catch (e) {
      debugPrint('[TokenStorage] storage op failed/timed out: $e');
      return null;
    }
  }

  Future<void> _safeVoid(Future<void> Function() fn) async {
    try {
      await fn().timeout(_kTimeout);
    } catch (e) {
      debugPrint('[TokenStorage] storage op failed/timed out: $e');
    }
  }

  /// Returns the stored access JWT, or null if none.
  Future<String?> getToken() => _safe(() => _storage.read(key: _keyAccess));

  /// Saves only the access token. Prefer [setTokens] after login.
  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await clearAllTokens();
    } else {
      await _safeVoid(() => _storage.write(key: _keyAccess, value: token));
    }
  }

  Future<String?> getRefreshToken() =>
      _safe(() => _storage.read(key: _keyRefresh));

  /// Saves access token and optional refresh token (clears refresh if null/empty).
  Future<void> setTokens({required String access, String? refresh}) async {
    await _safeVoid(() => _storage.write(key: _keyAccess, value: access));
    if (refresh != null && refresh.isNotEmpty) {
      await _safeVoid(() => _storage.write(key: _keyRefresh, value: refresh));
    } else {
      await _safeVoid(() => _storage.delete(key: _keyRefresh));
    }
  }

  /// Removes both tokens (e.g. on sign out or auth failure).
  Future<void> clearAllTokens() async {
    await _safeVoid(() => _storage.delete(key: _keyAccess));
    await _safeVoid(() => _storage.delete(key: _keyRefresh));
  }

  /// Same as [clearAllTokens] (legacy name).
  Future<void> clearToken() => clearAllTokens();
}
