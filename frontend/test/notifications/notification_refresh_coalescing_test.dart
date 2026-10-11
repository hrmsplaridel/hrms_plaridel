import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_repository.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';

void main() {
  test('overlapping counts and list loads share their requests', () async {
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    final first = provider.loadNotifications();
    final duplicate = provider.loadNotifications();
    final count = provider.refreshUnreadCount();
    expect(repo.loads, 1);
    repo.listGate.complete([]);
    await Future.wait([first, duplicate, count]);
    expect(repo.loads, 1);
    expect(repo.counts, 1);
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
      expect(repo.counts, 2);
      provider.dispose();
    },
  );
  test('a failed count keeps the previous badge', () async {
    final provider = NotificationProvider(repository: _Repo()..failCount = true)
      ..unreadCount = 8;
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
    expect(repo.counts, 0);
  });
  test('mark-read wins over an older in-flight count and list', () async {
    final repo = _Repo();
    final provider = NotificationProvider(repository: repo);
    repo.listGate.complete([_notice()]);
    await provider.loadNotifications();
    repo.countGate = Completer<int>();
    final refresh = provider.refreshUnreadCount();
    final marked = provider.markRead('old');
    await Future<void>.delayed(Duration.zero);
    repo.countGate!.complete(1);
    await Future.wait([refresh, marked]);
    expect(provider.unreadCount, 0);
    expect(provider.items.single.readAt, isNotNull);
    expect(repo.loads, 2);
    expect(repo.counts, 3);
    provider.dispose();
  });
}

class _Repo extends NotificationRepository {
  final listGate = Completer<List<AppNotification>>();
  int loads = 0, counts = 0;
  bool failCount = false;
  bool read = false;
  Completer<int>? countGate;
  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 50}) {
    loads++;
    return loads == 1
        ? listGate.future
        : Future.value(read ? [_notice(read: true)] : []);
  }

  @override
  Future<int> fetchUnreadCount() async {
    counts++;
    if (failCount) throw Exception('Offline');
    if (counts == 2 && countGate != null) return countGate!.future;
    return read ? 0 : 1;
  }

  @override
  Future<void> markRead(String id) async {
    read = true;
  }
}

AppNotification _notice({bool read = false}) => AppNotification(
  id: 'old',
  category: 'leave',
  type: 'review',
  title: 'Review',
  createdAt: DateTime(2026),
  readAt: read ? DateTime(2026, 10, 11) : null,
);
