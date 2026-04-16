import 'package:flutter/foundation.dart';

import 'app_notification.dart';
import 'notification_repository.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationRepository? repository})
    : _repo = repository ?? NotificationRepository();

  final NotificationRepository _repo;

  int unreadCount = 0;
  List<AppNotification> items = [];
  bool loading = false;
  String? loadError;

  /// Fetches `/api/notifications/unread-count`. Called on dashboard load, after leave actions
  /// ([LeaveProvider.onMutation]), on a 30s timer while dashboards are open, and after closing the panel.
  Future<void> refreshUnreadCount() async {
    try {
      unreadCount = await _repo.fetchUnreadCount();
      notifyListeners();
    } catch (_) {
      /* keep previous count */
    }
  }

  Future<void> loadNotifications() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      items = await _repo.fetchNotifications();
      unreadCount = await _repo.fetchUnreadCount();
    } catch (e) {
      loadError = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _repo.markRead(id);
      final i = items.indexWhere((n) => n.id == id);
      if (i >= 0) {
        final n = items[i];
        items[i] = AppNotification(
          id: n.id,
          category: n.category,
          type: n.type,
          title: n.title,
          body: n.body,
          readAt: DateTime.now(),
          referenceType: n.referenceType,
          referenceId: n.referenceId,
          metadata: n.metadata,
          createdAt: n.createdAt,
        );
      }
      unreadCount = await _repo.fetchUnreadCount();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _repo.markAllRead();
      await loadNotifications();
    } catch (_) {}
  }
}
