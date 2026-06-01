import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/config.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';

/// Central auth state. Uses API (JWT) instead of Supabase.
/// Exposes current user, displayName, email, avatarPath. Call [refreshUser] after
/// profile/avatar updates so UI stays in sync.
class AuthProvider extends ChangeNotifier {
  AppUser? _user;
  bool _isSigningOut = false;

  AppUser? get user => _user;

  /// True while [signOut] is in progress (shows loading overlay in UI).
  bool get isSigningOut => _isSigningOut;

  /// Display name from full_name or email prefix.
  String get displayName {
    if (_user == null) return '';
    final first = (_user!.firstName ?? '').trim();
    final last = (_user!.lastName ?? '').trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return [first, last].where((s) => s.isNotEmpty).join(' ');
    }
    final name = (_user!.fullName ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts.first} ${parts.last}';
      }
      return name;
    }
    return _user!.email.split('@').first;
  }

  String get email => _user?.email ?? '';

  /// Storage path for avatar.
  String? get avatarPath => _user?.avatarPath;

  void replaceUser(AppUser user) {
    _user = user;
    notifyListeners();
  }

  /// Restore session from stored JWT. Call before runApp.
  Future<void> restoreSession() async {
    String? token;
    try {
      final future = TokenStorage.instance.getToken();
      token = kIsWeb
          ? await future.timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                debugPrint(
                  'TokenStorage.getToken timed out on web; continuing without session.',
                );
                return null;
              },
            )
          : await future;
    } catch (e) {
      debugPrint('TokenStorage.getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) return;
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/auth/me',
      );
      final data = res.data;
      if (data != null) {
        _user = AppUser.fromJson(data);
        notifyListeners();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await TokenStorage.instance.clearAllTokens();
      }
    } catch (_) {
      await TokenStorage.instance.clearAllTokens();
    }
  }

  /// Login with email and password. Stores access + refresh tokens and sets user.
  /// Returns `null` on success, or an error message String on failure.
  Future<String?> login(String email, String password) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      final data = res.data;
      if (data == null) return 'Invalid email or password';

      final token = data['token'] as String?;
      if (token == null || token.isEmpty) return 'Invalid email or password';

      final refresh = data['refreshToken'] as String?;
      await TokenStorage.instance.setTokens(access: token, refresh: refresh);

      final userData = data['user'] as Map<String, dynamic>?;
      if (userData != null) {
        _user = AppUser.fromJson(userData);
      }
      await refreshUser();
      notifyListeners();
      return null;
    } on DioException catch (e) {
      debugPrint(
        'AuthProvider.login error: '
        'type=${e.type}, '
        'status=${e.response?.statusCode}, '
        'message=${e.message}, '
        'data=${e.response?.data}, '
        'error=${e.error}',
      );
      final body = e.response?.data;
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Cannot reach server at ${ApiConfig.baseUrl}. '
            'On PC: start backend (npm start in backend/). '
            'Phone on Wi‑Fi: same network as PC, allow port 3000 in Windows Firewall '
            '(run scripts/allow-backend-firewall-windows.ps1 as Admin), '
            'or use USB: scripts/run_flutter_mobile_usb.ps1.';
      }
      return 'Login failed. Please try again.';
    } catch (e) {
      debugPrint('AuthProvider.login error: $e');
      return 'Login failed. Please try again.';
    }
  }

  /// Apply a new avatar storage path immediately (e.g. right after upload).
  void applyAvatarPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || _user == null) return;
    _user = _user!.copyWith(avatarPath: trimmed);
    notifyListeners();
  }

  /// Refetch current user from API (e.g. after updating profile or avatar).
  Future<void> refreshUser() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/auth/me',
      );
      final data = res.data;
      if (data != null) {
        _user = AppUser.fromJson(data);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AuthProvider.refreshUser failed: $e');
    }
  }

  Future<void> signOut() async {
    if (_isSigningOut) return;
    _isSigningOut = true;
    notifyListeners();
    try {
      final refresh = await TokenStorage.instance.getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        try {
          await ApiClient.instance.post<void>(
            '/auth/logout',
            data: {'refreshToken': refresh},
            options: Options(extra: {'skipAuthRefresh': true}),
          );
        } catch (_) {}
      }
      await TokenStorage.instance.clearAllTokens();
      _user = null;
    } finally {
      _isSigningOut = false;
      notifyListeners();
    }
  }
}
