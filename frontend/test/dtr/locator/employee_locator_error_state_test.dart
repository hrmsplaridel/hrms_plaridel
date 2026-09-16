import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
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
      addTearDown(realtime.dispose);

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _DepartmentHeadAuthProvider(),
            ),
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
  fail('Timed out waiting for the expected locator state.');
}

class _DepartmentHeadAuthProvider extends AuthProvider {
  @override
  AppUser? get user => const AppUser(
    id: 'department-head-1',
    email: 'head@example.com',
    role: 'employee',
    fullName: 'Department Head',
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
