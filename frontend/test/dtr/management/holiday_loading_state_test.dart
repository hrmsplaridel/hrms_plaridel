import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/holidays/pages/manage_holiday.dart';

void main() {
  final requests = <RequestOptions>[];
  final handlers = <RequestInterceptorHandler>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/holidays') {
            requests.add(options);
            handlers.add(handler);
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );
  });

  setUp(() {
    requests.clear();
    handlers.clear();
  });

  tearDownAll(() {
    ApiClient.instance.dio.interceptors.clear();
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageHoliday())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(requests, hasLength(1));
  }

  void respond(int index, String name) {
    handlers[index].resolve(
      Response<List<dynamic>>(
        requestOptions: requests[index],
        data: [
          {
            'id': 'holiday-$index',
            'name': name,
            'date_from': '2026-09-09',
            'date_to': '2026-09-09',
            'holiday_type': 'regular',
            'is_active': true,
            'recurring': false,
            'coverage': 'whole_day',
          },
        ],
      ),
    );
  }

  testWidgets('an older holiday response cannot replace the latest result', (
    tester,
  ) async {
    await openPage(tester);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(requests, hasLength(2));

    respond(1, 'Newest holiday');
    await tester.pumpAndSettle();
    expect(find.text('Newest holiday'), findsOneWidget);

    respond(0, 'Stale holiday');
    await tester.pumpAndSettle();
    expect(find.text('Newest holiday'), findsOneWidget);
    expect(find.text('Stale holiday'), findsNothing);
  });

  testWidgets(
    'an initial load failure shows an error instead of an empty list',
    (tester) async {
      await openPage(tester);
      handlers.single.reject(
        DioException(requestOptions: requests.single, message: 'Unavailable'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('holiday-load-error')), findsOneWidget);
      expect(find.text('Holiday list unavailable'), findsOneWidget);
      expect(find.text('No holidays yet'), findsNothing);
      expect(find.byKey(const Key('holiday-load-retry')), findsOneWidget);
    },
  );

  testWidgets('a failed refresh preserves the last successful holiday list', (
    tester,
  ) async {
    await openPage(tester);
    respond(0, 'Existing holiday');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump(const Duration(milliseconds: 20));
    handlers[1].reject(
      DioException(requestOptions: requests[1], message: 'Unavailable'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Existing holiday'), findsOneWidget);
    expect(find.byKey(const Key('holiday-load-error')), findsOneWidget);
  });
}
