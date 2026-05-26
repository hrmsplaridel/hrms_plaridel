import 'package:dio/dio.dart';

import '../api/client.dart';
import 'app_notification.dart';

/// User-facing failure from the global notifications API.
class NotificationLoadException implements Exception {
  NotificationLoadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NotificationRepository {
  static String _friendlyMessage(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String? serverMsg;
    if (data is Map) {
      serverMsg = data['error']?.toString();
    }
    if (status == 401) {
      return 'Session expired. Sign in again to load notifications.';
    }
    if (status == 500 && serverMsg != null) {
      return serverMsg;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Check that the API is running and API_BASE_URL is correct.';
    }
    return serverMsg ?? 'Could not load notifications. Pull to refresh or try again.';
  }

  static List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['notifications'] is List) {
      return data['notifications'] as List;
    }
    return [];
  }

  Future<int> fetchUnreadCount() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/notifications/unread-count',
      );
      final data = res.data;
      if (data == null) return 0;
      return (data['unread_count'] as num?)?.toInt() ?? 0;
    } on DioException {
      return 0;
    }
  }

  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    try {
      final res = await ApiClient.instance.get<dynamic>(
        '/api/notifications',
        queryParameters: {'limit': limit},
      );
      final list = _extractList(res.data);
      return list
          .map(
            (e) => AppNotification.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw NotificationLoadException(_friendlyMessage(e));
    }
  }

  Future<void> markRead(String id) async {
    await ApiClient.instance.patch<Map<String, dynamic>>(
      '/api/notifications/$id/read',
    );
  }

  Future<void> markAllRead() async {
    await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/notifications/read-all',
    );
  }
}
