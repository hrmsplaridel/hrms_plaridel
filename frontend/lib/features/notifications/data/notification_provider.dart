import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'notification_preference_store.dart';
import 'notification_repository.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationRepository? repository})
    : _repo = repository ?? NotificationRepository() {
    unawaited(_ensurePrefsLoaded());
  }

  final NotificationRepository _repo;
  Future<void>? _refreshInFlight;
  Timer? _eventDebounce;
  bool _wantList = false;
  bool _includingList = false;
  bool _trailingRefresh = false;
  bool _disposed = false;
  Map<String, bool> _categoryPrefs = {
    for (final c in NotificationPreferenceStore.managedCategories) c: true,
  };
  bool _prefsLoaded = false;
  Future<void>? _prefsLoadInFlight;
  List<AppNotification> _allItems = [];

  int unreadCount = 0;
  List<AppNotification> items = [];
  bool loading = false;
  String? loadError;

  /// Fetches notifications and applies category preferences for the badge count.
  Future<void> refreshUnreadCount() => _refresh(includeList: true);

  Future<void> loadNotifications() => _refresh(includeList: true);

  /// Reloads toggles from settings and re-filters the current list / badge.
  Future<void> reloadPreferences() async {
    _prefsLoaded = false;
    await _ensurePrefsLoaded(force: true);
    _applyPreferenceFilter();
    _publish();
  }

  Future<void> _ensurePrefsLoaded({bool force = false}) {
    if (_prefsLoaded && !force) return Future.value();
    if (_prefsLoadInFlight != null && !force) return _prefsLoadInFlight!;
    final done = Completer<void>();
    _prefsLoadInFlight = done.future;
    () async {
      try {
        final prefs = await NotificationPreferenceStore.load();
        if (_disposed) return;
        _categoryPrefs = prefs;
        _prefsLoaded = true;
      } catch (_) {
        if (!_disposed) _prefsLoaded = true;
      } finally {
        _prefsLoadInFlight = null;
        done.complete();
      }
    }();
    return done.future;
  }

  bool _isEnabled(AppNotification n) {
    return NotificationPreferenceStore.isCategoryEnabled(
      _categoryPrefs,
      n.category,
    );
  }

  void _applyPreferenceFilter() {
    items = _allItems.where(_isEnabled).toList(growable: false);
    unreadCount = items.where((n) => n.readAt == null).length;
  }

  /// Combine realtime event bursts; late events request one fresh pass after the current load.
  void scheduleRefresh() {
    if (_disposed) return;
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(
        _refresh(
          includeList: true,
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
    // Always load the list so the badge matches enabled categories.
    _wantList = true;
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
          await _ensurePrefsLoaded();
          if (_disposed) return;
          if (_includingList) {
            final nextItems = await _repo.fetchNotifications();
            if (_disposed) return;
            _allItems = nextItems;
            _applyPreferenceFilter();
          }
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
      final allI = _allItems.indexWhere((n) => n.id == id);
      if (allI >= 0) {
        final n = _allItems[allI];
        _allItems[allI] = AppNotification(
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
      _applyPreferenceFilter();
      _publish();
      await _refresh(includeList: true, trailing: true);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _repo.markAllRead();
      await _refresh(includeList: true, trailing: true);
    } catch (_) {}
  }
}
