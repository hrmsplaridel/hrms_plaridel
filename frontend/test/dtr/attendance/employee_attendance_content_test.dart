import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/desktop/pages/employee_dashboard_desktop_page.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dashboard_skeletons.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });

  testWidgets(
    'loading error retry empty and populated results are mutually exclusive',
    (tester) async {
      final firstLoad = Completer<ResponseBody>();
      final adapter = _AttendancePageAdapter(
        officialDate: '2026-09-14',
        attendanceResponses: [
          firstLoad.future,
          Future.value(_emptyAttendanceResponse()),
          Future.value(_attendanceResponse(['2026-09-14'])),
        ],
      );
      final provider = await _pumpAttendance(
        tester,
        adapter: adapter,
        size: const Size(1000, 800),
      );
      await _pumpUntil(tester, () => adapter.attendanceRequests.length == 1);

      expect(find.byType(EmployeeTimeRecordsLoadingSkeleton), findsOneWidget);
      expect(find.text('Could not load attendance'), findsNothing);
      expect(
        find.text('No time records for the selected period.'),
        findsNothing,
      );

      firstLoad.complete(
        _errorResponse('Attendance is temporarily unavailable'),
      );
      await _pumpUntil(
        tester,
        () => find.text('Could not load attendance').evaluate().isNotEmpty,
      );

      expect(find.byType(EmployeeTimeRecordsLoadingSkeleton), findsNothing);
      expect(find.text('Could not load attendance'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('No time records for the selected period.'),
        findsNothing,
      );

      await tester.tap(find.text('Retry'));
      await _pumpUntil(
        tester,
        () => find
            .text('No time records for the selected period.')
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Could not load attendance'), findsNothing);
      expect(
        find.text('No time records for the selected period.'),
        findsOneWidget,
      );

      provider.debugPublishDtrUpdate(
        DtrUpdateEvent.fromJson({
          'action': 'manual_correction',
          'user_id': 'employee-a',
          'date': '2026-09-14',
        }),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _pumpUntil(tester, () => find.text('14 Mon').evaluate().isNotEmpty);

      expect(
        find.text('No time records for the selected period.'),
        findsNothing,
      );
      expect(find.text('14 Mon'), findsOneWidget);
      expect(adapter.attendanceRequests, hasLength(3));

      provider.debugPublishDtrUpdate(
        DtrUpdateEvent.fromJson({
          'action': 'manual_correction',
          'user_id': 'employee-b',
          'date': '2026-09-14',
        }),
      );
      provider.debugPublishDtrUpdate(
        DtrUpdateEvent.fromJson({
          'action': 'manual_correction',
          'user_id': 'employee-a',
          'date': '2026-08-31',
        }),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(adapter.attendanceRequests, hasLength(3));
      provider.dispose();

      await tester.pumpWidget(const SizedBox.shrink());
      provider.debugPublishDtrUpdate(
        DtrUpdateEvent.fromJson({
          'action': 'manual_correction',
          'user_id': 'employee-a',
          'date': '2026-09-14',
        }),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(adapter.attendanceRequests, hasLength(3));
    },
  );

  testWidgets(
    'mobile uses an ahead official date once and rejects stale modes',
    (tester) async {
      final delayedMonthly = Completer<ResponseBody>();
      final adapter = _AttendancePageAdapter(
        officialDate: '2026-09-15',
        attendanceResponses: [
          Future.value(_attendanceResponse(['2026-09-15'])),
          delayedMonthly.future,
          Future.value(_attendanceResponse(['2026-09-15'])),
        ],
      );
      final provider = await _pumpAttendance(
        tester,
        adapter: adapter,
        size: const Size(420, 900),
      );
      await _pumpUntil(tester, () => adapter.attendanceRequests.length == 1);
      await _pumpUntil(tester, () => find.text('15 Tue').evaluate().isNotEmpty);

      expect(adapter.attendanceRequests, hasLength(1));
      expect(
        adapter.attendanceRequests.single.queryParameters['start_date'],
        '2026-09-15',
      );
      expect(
        adapter.attendanceRequests.single.queryParameters['end_date'],
        '2026-09-15',
      );
      expect(find.text('15 Tue'), findsOneWidget);

      await tester.tap(find.text('Monthly'));
      await _pumpUntil(tester, () => adapter.attendanceRequests.length == 2);
      expect(adapter.attendanceRequests, hasLength(2));

      await tester.tap(find.text('Day'));
      await _pumpUntil(
        tester,
        () => provider.filterStart == DateTime(2026, 9, 15),
      );
      expect(provider.filterStart, DateTime(2026, 9, 15));
      expect(provider.filterEnd, DateTime(2026, 9, 15));

      await tester.tap(find.text('Today'));
      await _pumpUntil(tester, () => adapter.attendanceRequests.length == 3);
      expect(adapter.attendanceRequests, hasLength(3));

      delayedMonthly.complete(_attendanceResponse(['2026-09-01']));
      await _pumpUntil(tester, () => adapter.completedAttendanceResponses == 3);

      expect(provider.filterStart, DateTime(2026, 9, 15));
      expect(provider.filterEnd, DateTime(2026, 9, 15));
      expect(find.text('15 Tue'), findsOneWidget);
      expect(find.text('1 Tue'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );

  testWidgets('official date controls range filtering reset and app resume', (
    tester,
  ) async {
    final adapter = _AttendancePageAdapter(
      officialDate: '2026-08-31',
      attendanceResponses: List.generate(
        3,
        (_) => Future.value(_attendanceResponse(['2026-08-31', '2026-09-01'])),
      ),
    );
    final provider = await _pumpAttendance(
      tester,
      adapter: adapter,
      size: const Size(1000, 800),
    );
    await _pumpUntil(tester, () => adapter.attendanceRequests.length == 1);
    await _pumpUntil(tester, () => find.text('31 Mon').evaluate().isNotEmpty);

    expect(adapter.attendanceRequests, hasLength(1));
    expect(
      adapter.attendanceRequests.first.queryParameters['start_date'],
      '2026-08-01',
    );
    expect(
      adapter.attendanceRequests.first.queryParameters['end_date'],
      '2026-08-31',
    );
    expect(find.text('31 Mon'), findsOneWidget);
    expect(find.text('1 Tue'), findsNothing);

    await tester.tap(find.byTooltip('Reset filters'));
    await _pumpUntil(tester, () => adapter.attendanceRequests.length == 2);
    expect(adapter.attendanceRequests, hasLength(2));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntil(tester, () => adapter.attendanceRequests.length == 3);
    expect(adapter.attendanceRequests, hasLength(3));
    expect(adapter.reportPeriodRequests, hasLength(3));

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}

Future<DtrProvider> _pumpAttendance(
  WidgetTester tester, {
  required _AttendancePageAdapter adapter,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  ApiClient.instance.dio.httpClientAdapter = adapter;
  final provider = DtrProvider()..onAuthUserChanged('employee-a');

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const Scaffold(
            body: SingleChildScrollView(child: EmployeeAttendanceContent()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return provider;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
}) async {
  for (var i = 0; i < attempts; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  final text = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .join(' | ');
  fail('Timed out waiting for the expected attendance state. Text: $text');
}

class _AttendancePageAdapter implements HttpClientAdapter {
  _AttendancePageAdapter({
    required this.officialDate,
    required this.attendanceResponses,
  });

  final String officialDate;
  final List<Future<ResponseBody>> attendanceResponses;
  final List<RequestOptions> reportPeriodRequests = [];
  final List<RequestOptions> attendanceRequests = [];
  int completedAttendanceResponses = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/api/dtr-daily-summary/report-years') {
      reportPeriodRequests.add(options);
      final year = int.parse(officialDate.substring(0, 4));
      return ResponseBody.fromString(
        jsonEncode({
          'official_date': officialDate,
          'years': [2019, 2020, 2021, 2022, 2023, 2024, 2025, year],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == '/api/dtr-daily-summary') {
      attendanceRequests.add(options);
      if (attendanceResponses.isEmpty) {
        throw StateError('No attendance response was queued.');
      }
      final response = await attendanceResponses.removeAt(0);
      completedAttendanceResponses += 1;
      return response;
    }
    throw StateError('Unexpected request: ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _attendanceResponse(List<String> dates) => ResponseBody.fromString(
  jsonEncode([
    for (final date in dates)
      {
        'id': 'record-$date',
        'user_id': 'employee-a',
        'record_date': date,
        'time_in': '${date}T00:00:00.000Z',
        'time_out': '${date}T09:00:00.000Z',
        'status': 'present',
      },
  ]),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    'x-total-count': ['${dates.length}'],
    'x-limit': ['500'],
    'x-offset': ['0'],
  },
);

ResponseBody _emptyAttendanceResponse() => _attendanceResponse([]);

ResponseBody _errorResponse(String message) => ResponseBody.fromString(
  jsonEncode({'error': message}),
  503,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
