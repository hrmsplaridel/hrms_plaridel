import 'package:dio/dio.dart';

import '../api/client.dart';
import 'app_notification.dart';

class NotificationRepository {
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
    final res = await ApiClient.instance.get<List<dynamic>>(
      '/api/notifications',
      queryParameters: {'limit': limit},
    );
    final data = res.data;
    if (data == null) return [];
    return data
        .map(
          (e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
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
