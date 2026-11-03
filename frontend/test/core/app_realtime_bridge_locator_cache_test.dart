import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_bridge.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_repository.dart';
import 'package:hrms_plaridel/features/notifications/models/app_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ApiClient.instance.init);

  setUp(() {
    LocatorSlipDataCache.instance.invalidateAll();
    ApiClient.instance.dio.interceptors.clear();
  });

  tearDown(() {
    LocatorSlipDataCache.instance.invalidateAll();
    ApiClient.instance.dio.interceptors.clear();
  });

  for (final eventName in ['leave_updated', 'locator_updated']) {
    testWidgets('$eventName refreshes read status and unread badge', (
      tester,
    ) async {
      final realtime = _FakeRealtimeProvider();
      final repository = _NotificationRepository();
      final notifications = NotificationProvider(repository: repository)
        ..unreadCount = 1
        ..items = [
          AppNotification(
            id: 'review',
            category: 'leave',
            type: 'leave_pending_department_head',
            title: 'Review',
            createdAt: DateTime(2026),
          ),
        ];
      addTearDown(realtime.dispose);
      addTearDown(notifications.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
            ChangeNotifierProvider<NotificationProvider>.value(
              value: notifications,
            ),
          ],
          child: const AppRealtimeBridge(child: SizedBox()),
        ),
      );
      realtime.emit(AppRealtimeEvent(name: eventName));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(repository.loads, 1);
      expect(notifications.unreadCount, 0);
      expect(notifications.items.single.readAt, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final eventName in ['leave_updated', 'locator_updated', 'connected']) {
    testWidgets('$eventName invalidates the shared approval inbox', (
      tester,
    ) async {
      final cache = WorkflowInboxCache.instance;
      cache.clearSession();
      addTearDown(cache.clearSession);
      await cache.get(
        'leave',
        () async => <dynamic>[
          {'id': 'old', 'kind': 'leave'},
        ],
      );
      final realtime = _FakeRealtimeProvider();
      addTearDown(realtime.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRealtimeProvider>.value(
          value: realtime,
          child: const AppRealtimeBridge(child: SizedBox()),
        ),
      );
      realtime.emit(AppRealtimeEvent(name: eventName));
      await tester.pump();
      await tester.runAsync(() async {
        expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('locator type event invalidates the global type cache', (
    tester,
  ) async {
    var requestCount = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.method, 'GET');
          expect(options.uri.path, '/api/locator-slips/types');
          requestCount += 1;
          handler.resolve(
            Response(
              requestOptions: options,
              data: const [
                {
                  'code': 'locator',
                  'label': 'Locator / Official Business',
                  'is_active': true,
                },
              ],
            ),
          );
        },
      ),
    );

    await tester.runAsync(() async {
      await LocatorSlipDataCache.instance.listTypes();
      await LocatorSlipDataCache.instance.listTypes();
    });
    expect(requestCount, 1);

    final realtime = _FakeRealtimeProvider();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRealtimeProvider>.value(
        value: realtime,
        child: const AppRealtimeBridge(child: SizedBox()),
      ),
    );

    realtime.emit(
      const AppRealtimeEvent(
        name: 'locator_type_updated',
        payload: {'action': 'updated', 'code': 'locator'},
      ),
    );
    await tester.pump();

    await tester.runAsync(LocatorSlipDataCache.instance.listTypes);
    expect(requestCount, 2);

    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeRealtimeProvider extends AppRealtimeProvider {
  final _events = StreamController<AppRealtimeEvent>.broadcast();

  @override
  Stream<AppRealtimeEvent> get events => _events.stream;

  void emit(AppRealtimeEvent event) => _events.add(event);

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}

class _NotificationRepository extends NotificationRepository {
  int loads = 0;
  @override
  Future<int> fetchUnreadCount() async => 0;
  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 100}) async {
    loads++;
    return [
      AppNotification(
        id: 'review',
        category: 'leave',
        type: 'leave_pending_department_head',
        title: 'Review',
        createdAt: DateTime(2026),
        readAt: DateTime(2026, 10, 11),
      ),
    ];
  }
}
