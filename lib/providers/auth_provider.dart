import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/app_user.dart';
import '../api/client.dart';
import '../api/config.dart';
import '../api/token_storage.dart';

/// Central auth state. Uses API (JWT) instead of Supabase.
/// Exposes current user, displayName, email, avatarPath. Call [refreshUser] after
/// profile/avatar updates so UI stays in sync.
class AuthProvider extends ChangeNotifier {
  AppUser? _user;

  AppUser? get user => _user;

  /// Display name from full_name or email prefix.
  String get displayName {
    if (_user == null) return '';
    final name = _user!.fullName;
    if (name != null && name.isNotEmpty) return name;
    return _user!.email.split('@').first;
  }

  String get email => _user?.email ?? '';

  /// Storage path for avatar.
  String? get avatarPath => _user?.avatarPath;

  /// Restore session from stored JWT. Call before runApp.
  Future<void> restoreSession() async {
    final token = await TokenStorage.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>('/auth/me');
      final data = res.data;
      if (data != null) {
        _user = AppUser.fromJson(data);
        notifyListeners();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await TokenStorage.instance.clearToken();
      }
    } catch (_) {
      await TokenStorage.instance.clearToken();
    }
  }

  /// Login with email and password. Stores JWT and sets user.
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

      await TokenStorage.instance.setToken(token);

      final userData = data['user'] as Map<String, dynamic>?;
      if (userData != null) {
        _user = AppUser.fromJson(userData);
      } else {
        await refreshUser();
      }
      notifyListeners();
      return null;
    } on DioException catch (e) {
      debugPrint('AuthProvider.login error: ${e.response?.data}');
      final body = e.response?.data;
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Cannot reach server. Is the backend running on ${ApiConfig.baseUrl}?';
      }
      return 'Login failed. Please try again.';
    } catch (e) {
      debugPrint('AuthProvider.login error: $e');
      return 'Login failed. Please try again.';
    }
  }

  /// Refetch current user from API (e.g. after updating profile or avatar).
  Future<void> refreshUser() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>('/auth/me');
      final data = res.data;
      if (data != null) {
        final newUser = AppUser.fromJson(data);
        if (_user?.id != newUser.id ||
            _user?.fullName != newUser.fullName ||
            _user?.avatarPath != newUser.avatarPath) {
          _user = newUser;
          notifyListeners();
        }
      }
    } catch (_) {
      // Keep existing state on error
    }
  }

  Future<void> signOut() async {
    await TokenStorage.instance.clearToken();
    _user = null;
    notifyListeners();
  }
}
