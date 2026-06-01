import 'package:hrms_plaridel/features/docutracker/data/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';

/// Notification helper for DocuTracker.
///
/// Backend already scopes `/notifications` to the authenticated user, so this
/// service mainly provides caching + reusable grouping/unread helpers.
class DocuTrackerNotificationService {
  DocuTrackerNotificationService(this._repo);

  final DocuTrackerRepository _repo;

  List<DocumentNotification>? _cachedNotifications;

  /// Clears cached notifications so the next fetch hits the backend.
  void clearCache() => _cachedNotifications = null;

  Future<List<DocumentNotification>> fetchMyNotifications({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedNotifications != null) {
      return _cachedNotifications!;
    }
    final list = await _repo.listMyNotifications();
    _cachedNotifications = list;
    return list;
  }

  List<DocumentNotification> unreadOnly(
    List<DocumentNotification> notifications,
  ) {
    return notifications.where((n) => !n.read).toList();
  }

  Map<String, List<DocumentNotification>> groupByType(
    List<DocumentNotification> notifications,
  ) {
    final map = <String, List<DocumentNotification>>{};
    for (final n in notifications) {
      map.putIfAbsent(n.type, () => <DocumentNotification>[]).add(n);
    }
    return map;
  }

  int unreadCount(List<DocumentNotification> notifications) =>
      notifications.where((n) => !n.read).length;
}
