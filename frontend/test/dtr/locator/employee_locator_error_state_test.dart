import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });

  setUp(() {
    LocatorSlipDataCache.instance.invalidateAll();
  });

  testWidgets(
    'request and approval failures stay isolated and retry to empty states',
    (tester) async {
      final adapter = _LocatorErrorStateAdapter();
      ApiClient.instance.dio.httpClientAdapter = adapter;
      final realtime = AppRealtimeProvider();
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'department-head-1',
            email: 'head@example.com',
            role: 'employee',
            fullName: 'Department Head',
          ),
        );
      addTearDown(realtime.dispose);
      addTearDown(auth.dispose);

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: EmployeeLocatorSlipContent()),
            ),
          ),
        ),
      );

      await _pumpUntil(
        tester,
        () =>
            adapter.myRequestCount == 1 &&
            adapter.approvalRequestCount == 1 &&
            find.text('Approvals / History').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Approvals / History'));
      await _pumpUntil(
        tester,
        () => find.text('Approval queue unavailable').evaluate().isNotEmpty,
      );

      expect(find.text('Approval queue unavailable'), findsOneWidget);
      expect(find.text('My requests unavailable'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No locator requests or history yet.'), findsNothing);
      expect(
        find.text('No locator requests match the current filter.'),
        findsNothing,
      );

      await tester.tap(find.text('My Requests'));
      await tester.pump();

      expect(find.text('My requests unavailable'), findsOneWidget);
      expect(find.text('Approval queue unavailable'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text(
          'No locator requests yet. Click "File Request" to create one.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Retry'));
      await _pumpUntil(
        tester,
        () => find
            .text(
              'No locator requests yet. Click "File Request" to create one.',
            )
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('My requests unavailable'), findsNothing);
      expect(adapter.myRequestCount, 2);

      await tester.tap(find.text('Approvals / History'));
      await tester.pump();

      expect(find.text('Approval queue unavailable'), findsOneWidget);
      expect(find.text('No locator requests or history yet.'), findsNothing);

      await tester.tap(find.text('Retry'));
      await _pumpUntil(
        tester,
        () => find
            .text('No locator requests or history yet.')
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Approval queue unavailable'), findsNothing);
      expect(adapter.approvalRequestCount, 2);
    },
  );

  testWidgets(
    'manual refresh, app resume, and realtime reconnect reconcile requests',
    (tester) async {
      final adapter = _LocatorRefreshAdapter();
      ApiClient.instance.dio.httpClientAdapter = adapter;
      final realtime = _FakeRealtimeProvider();
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'employee-1',
            email: 'employee@example.com',
            role: 'employee',
            fullName: 'Employee One',
          ),
        );
      addTearDown(realtime.dispose);
      addTearDown(auth.dispose);

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: EmployeeLocatorSlipContent()),
            ),
          ),
        ),
      );

      await _pumpUntil(tester, () => adapter.myRequestCount >= 1);

      var previousCount = adapter.myRequestCount;
      await tester.tap(find.byTooltip('Refresh locator requests'));
      await _pumpUntil(tester, () => adapter.myRequestCount > previousCount);
      expect(find.text('Locator requests refreshed.'), findsOneWidget);

      previousCount = adapter.myRequestCount;
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await _pumpUntil(tester, () => adapter.myRequestCount > previousCount);

      previousCount = adapter.myRequestCount;
      realtime.setConnected(true);
      await _pumpUntil(tester, () => adapter.myRequestCount > previousCount);
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  final visibleText = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .join(' | ');
  fail(
    'Timed out waiting for the expected locator state. '
    'Visible text: $visibleText',
  );
}

class _LocatorErrorStateAdapter implements HttpClientAdapter {
  int myRequestCount = 0;
  int approvalRequestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    switch (options.uri.path) {
      case '/api/locator-slips/types':
        return _jsonResponse([
          {
            'code': 'locator',
            'label': 'Locator / Official Business',
            'is_active': true,
          },
        ]);
      case '/api/locator-slips/context':
        return _jsonResponse({'official_date': '2026-09-17'});
      case '/api/locator-slips/department-head/check':
        return _jsonResponse({'isDeptHead': true});
      case '/api/locator-slips/my':
        myRequestCount += 1;
        if (myRequestCount == 1) {
          return _jsonResponse({
            'message': 'My requests unavailable',
          }, statusCode: 503);
        }
        return _emptyPage();
      case '/api/locator-slips/department-head':
        approvalRequestCount += 1;
        if (approvalRequestCount == 1) {
          return _jsonResponse({
            'message': 'Approval queue unavailable',
          }, statusCode: 503);
        }
        return _emptyPage();
      default:
        throw StateError('Unexpected request: ${options.uri}');
    }
  }

  @override
  void close({bool force = false}) {}
}

class _LocatorRefreshAdapter implements HttpClientAdapter {
  int myRequestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    switch (options.uri.path) {
      case '/api/locator-slips/types':
        return _jsonResponse([
          {
            'code': 'locator',
            'label': 'Locator / Official Business',
            'is_active': true,
          },
        ]);
      case '/api/locator-slips/context':
        return _jsonResponse({'official_date': '2026-09-19'});
      case '/api/locator-slips/department-head/check':
        return _jsonResponse({
          'isDeptHead': false,
          'canReviewPending': false,
          'hasReviewHistory': false,
        });
      case '/api/locator-slips/my':
        myRequestCount += 1;
        return _emptyPage();
      default:
        throw StateError('Unexpected request: ${options.uri}');
    }
  }

  @override
  void close({bool force = false}) {}
}

class _FakeRealtimeProvider extends AppRealtimeProvider {
  bool _connected = false;

  @override
  bool get connected => _connected;

  void setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    notifyListeners();
  }
}

ResponseBody _emptyPage() => _jsonResponse({
  'items': <Object>[],
  'pagination': {'page': 1, 'page_size': 50, 'total': 0, 'page_count': 1},
});

ResponseBody _jsonResponse(Object body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
