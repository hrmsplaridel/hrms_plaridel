import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_repository.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('overlapping counts and list loads share their requests', () async {
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    final first = provider.loadNotifications();
    final duplicate = provider.loadNotifications();
    final count = provider.refreshUnreadCount();
    // Preferences load before the repository is hit.
    final started = DateTime.now();
    while (repo.loads < 1 &&
        DateTime.now().difference(started) < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repo.loads, 1);
    repo.listGate.complete([]);
    await Future.wait([first, duplicate, count]);
    expect(repo.loads, 1);
    provider.dispose();
  });

  testWidgets(
    'event bursts coalesce and one trailing refresh catches a late update',
    (tester) async {
      final repo = _Repo();
      final provider = NotificationProvider(repository: repo);
      provider.items = [
        AppNotification(
          id: 'old',
          category: 'leave',
          type: 'review',
          title: 'Review',
          createdAt: DateTime(2026),
        ),
      ];
      for (var i = 0; i < 10; i++) {
        provider.scheduleRefresh();
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(repo.loads, 1);
      for (var i = 0; i < 10; i++) {
        provider.scheduleRefresh();
      }
      await tester.pump(const Duration(milliseconds: 250));
      repo.listGate.complete([]);
      await tester.pump();
      expect(repo.loads, 2);
      provider.dispose();
    },
  );

  test('a failed list load keeps the previous badge', () async {
    final provider = NotificationProvider(
      repository: _Repo()..failList = true,
    )..unreadCount = 8;
    await provider.refreshUnreadCount();
    expect(provider.unreadCount, 8);
    provider.dispose();
  });

  test('disposing during a request does not publish its response', () async {
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    final load = provider.loadNotifications();
    provider.dispose();
    repo.listGate.complete([]);
    await load;
    expect(provider.items, isEmpty);
  });

  test('mark-read wins over an older in-flight count and list', () async {
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    repo.listGate.complete([_notice()]);
    await provider.loadNotifications();
    final refresh = provider.refreshUnreadCount();
    final marked = provider.markRead('old');
    await Future.wait([refresh, marked]);
    expect(provider.unreadCount, 0);
    expect(provider.items.single.readAt, isNotNull);
    expect(repo.loads, greaterThanOrEqualTo(2));
    provider.dispose();
  });

  test('disabled categories are hidden from list and badge', () async {
    SharedPreferences.setMockInitialValues({
      'settings_notif_cat_v2_leave': false,
      'settings_notif_cat_v2_locator': true,
    });
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    repo.listGate.complete([
      _notice(id: 'leave-1', category: 'leave'),
      _notice(id: 'loc-1', category: 'locator'),
    ]);
    await provider.loadNotifications();
    expect(provider.items.map((n) => n.id), ['loc-1']);
    expect(provider.unreadCount, 1);
    provider.dispose();
  });
}

class _Repo extends NotificationRepository {
  final listGate = Completer<List<AppNotification>>();
  int loads = 0;
  bool failList = false;
  bool read = false;
  List<AppNotification> _last = const [];

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    loads++;
    if (failList) throw NotificationLoadException('Offline');
    if (loads == 1) {
      _last = await listGate.future;
      return _last;
    }
    return [
      for (final n in _last)
        AppNotification(
          id: n.id,
          category: n.category,
          type: n.type,
          title: n.title,
          body: n.body,
          readAt: read ? (n.readAt ?? DateTime(2026, 10, 11)) : n.readAt,
          referenceType: n.referenceType,
          referenceId: n.referenceId,
          metadata: n.metadata,
          createdAt: n.createdAt,
        ),
    ];
  }

  @override
  Future<int> fetchUnreadCount() async => read ? 0 : 1;

  @override
  Future<void> markRead(String id) async {
    read = true;
  }
}

AppNotification _notice({
  String id = 'old',
  String category = 'leave',
  bool read = false,
}) => AppNotification(
  id: id,
  category: category,
  type: 'review',
  title: 'Review',
  createdAt: DateTime(2026),
  readAt: read ? DateTime(2026, 10, 11) : null,
);
