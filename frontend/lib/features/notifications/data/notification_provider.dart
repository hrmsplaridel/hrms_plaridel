import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'notification_repository.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationRepository? repository})
    : _repo = repository ?? NotificationRepository();

  final NotificationRepository _repo;
  Future<void>? _refreshInFlight;
  Timer? _eventDebounce;
  bool _wantList = false;
  bool _includingList = false;
  bool _trailingRefresh = false;
  bool _listLoaded = false;
  bool _disposed = false;

  int unreadCount = 0;
  List<AppNotification> items = [];
  bool loading = false;
  String? loadError;

  /// Fetches `/api/notifications/unread-count`. Called on dashboard load, after leave actions
  /// ([LeaveProvider.onMutation]), on a 30s timer while dashboards are open, and after closing the panel.
  Future<void> refreshUnreadCount() => _refresh();

  Future<void> loadNotifications() => _refresh(includeList: true);

  /// Combine realtime event bursts; late events request one fresh pass after the current load.
  void scheduleRefresh() {
    if (_disposed) return;
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(
        _refresh(
          includeList: _listLoaded || items.isNotEmpty || _includingList,
          trailing: true,
        ),
      );
    });
  }

  Future<void> _refresh({bool includeList = false, bool trailing = false}) {
    if (_disposed) return Future.value();
    if (_refreshInFlight != null) {
      if (includeList && (!_includingList || trailing)) _wantList = true;
      if (trailing) _trailingRefresh = true;
      return _refreshInFlight!;
    }
    final done = Completer<void>();
    _refreshInFlight = done.future;
    _wantList = includeList;
    unawaited(_runRefresh(done));
    return done.future;
  }

  Future<void> _runRefresh(Completer<void> done) async {
    try {
      do {
        _includingList = _wantList;
        _wantList = false;
        _trailingRefresh = false;
        if (_includingList) {
          loading = true;
          loadError = null;
          _publish();
        }
        try {
          if (_includingList) {
            final nextItems = await _repo.fetchNotifications();
            if (_disposed) return;
            items = nextItems;
            _listLoaded = true;
          }
          final nextCount = await _repo.fetchUnreadCount();
          if (_disposed) return;
          unreadCount = nextCount;
        } catch (e) {
          if (_includingList) {
            loadError = e is NotificationLoadException
                ? e.message
                : 'Could not load notifications. Try again.';
          }
        } finally {
          loading = false;
          _includingList = false;
          _publish();
        }
      } while (!_disposed && (_wantList || _trailingRefresh));
    } finally {
      _refreshInFlight = null;
      done.complete();
    }
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventDebounce?.cancel();
    super.dispose();
  }

  Future<void> markRead(String id) async {
    try {
      await _repo.markRead(id);
      if (_disposed) return;
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
      _publish();
      await _refresh(includeList: _listLoaded, trailing: true);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _repo.markAllRead();
      await _refresh(includeList: true, trailing: true);
    } catch (_) {}
  }
}
