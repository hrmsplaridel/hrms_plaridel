import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/shifts/pages/manage_shift.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

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
          requests.add(options);
          handlers.add(handler);
        },
      ),
    );
  });

  setUp(() {
    requests.clear();
    handlers.clear();
  });

  void succeed(int index, {String? name}) {
    handlers[index].resolve(
      Response<List<dynamic>>(
        requestOptions: requests[index],
        data: [
          if (name != null)
            {
              'id': name,
              'name': name,
              'start_time': '08:00',
              'end_time': '17:00',
            },
        ],
      ),
    );
  }

  void fail(int index) {
    handlers[index].reject(
      DioException(
        requestOptions: requests[index],
        response: Response<dynamic>(
          requestOptions: requests[index],
          statusCode: 403,
          data: {'error': 'Access denied.'},
        ),
      ),
    );
  }

  Future<void> flushRequests(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(WidgetTester tester, {double width = 1440}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageShift())),
      ),
    );
    await flushRequests(tester);
  }

  Future<void> select(WidgetTester tester, String status) async {
    final dropdown = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .firstWhere(
          (widget) => widget.items!.any((item) => item.value == 'All'),
        );
    dropdown.onChanged!(status);
    await flushRequests(tester);
  }

  void expectAttendanceOnlyForm(WidgetTester tester) {
    expect(find.text('Attendance Mode'), findsOneWidget);
    for (final label in [
      'Break handling',
      'Existing rules',
      'Paid break',
      'Fixed unpaid deduction',
      'Recorded unpaid break',
      'Unpaid break (minutes)',
      'Punch window before/after shift (minutes)',
    ]) {
      expect(find.text(label), findsNothing);
    }
    final dropdownValues = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .expand((widget) => widget.items ?? <DropdownMenuItem<String>>[])
        .map((item) => item.value);
    expect(dropdownValues, contains('single_session'));
    expect(dropdownValues, contains('full_day'));
    for (final value in ['legacy', 'paid', 'fixed', 'recorded']) {
      expect(dropdownValues, isNot(contains(value)));
    }
  }

  for (final width in [390.0, 1440.0]) {
    testWidgets('new shift form at $width only exposes attendance settings', (
      tester,
    ) async {
      await mount(tester, width: width);
      succeed(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Shift'));
      await tester.pumpAndSettle();
      expectAttendanceOnlyForm(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shift edits do not submit hidden break or matching settings', (
    tester,
  ) async {
    await mount(tester);
    handlers[0].resolve(
      Response<List<dynamic>>(
        requestOptions: requests[0],
        data: [
          {
            'id': 'saved-shift',
            'name': 'Saved shift',
            'start_time': '08:00',
            'end_time': '17:00',
            'break_start': '12:00',
            'break_end': '13:00',
            'punch_mode': 'full_day',
            'capture_window_minutes': 90,
          },
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved shift'));
    await tester.pumpAndSettle();
    expectAttendanceOnlyForm(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Saved shift',
      ),
      'Renamed shift',
    );
    await tester.tap(find.text('Update'));
    await flushRequests(tester);
    expect(requests[1].method, 'PUT');
    final body = requests[1].data as Map<String, dynamic>;
    expect(body['name'], 'Renamed shift');
    expect(body['break_start'], '12:00:00');
    expect(body['break_end'], '13:00:00');
    for (final field in [
      'break_mode',
      'unpaid_break_minutes',
      'capture_window_minutes',
    ]) {
      expect(body, isNot(contains(field)));
    }
    handlers[1].resolve(
      Response<dynamic>(requestOptions: requests[1], data: {}),
    );
    await flushRequests(tester);
    succeed(2, name: 'Renamed shift');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('older successes cannot replace the latest filter results', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'Inactive');
    await select(tester, 'All');
    expect(requests.map((r) => r.queryParameters['status']), [
      'Active',
      'Inactive',
      'All',
    ]);
    succeed(2, name: 'Latest shift');
    await tester.pumpAndSettle();
    succeed(1, name: 'Old inactive shift');
    succeed(0, name: 'Old active shift');
    await tester.pumpAndSettle();
    expect(find.text('Latest shift'), findsOneWidget);
    expect(find.text('Old inactive shift'), findsNothing);
    expect(find.text('Old active shift'), findsNothing);
  });

  testWidgets('stale failure cannot stop current loading or show an error', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'All');
    fail(0);
    await tester.pump();
    expect(find.byType(WorkforceRowsSkeleton), findsOneWidget);
    expect(find.text('Access denied.'), findsNothing);
    succeed(1, name: 'Current shift');
    await tester.pumpAndSettle();
    expect(find.text('Current shift'), findsOneWidget);
    expect(find.byType(WorkforceRowsSkeleton), findsNothing);
  });

  testWidgets('failure hides old rows and Retry reloads the selected status', (
    tester,
  ) async {
    await mount(tester);
    succeed(0, name: 'Previously loaded');
    await tester.pumpAndSettle();
    await select(tester, 'Inactive');
    fail(1);
    await tester.pumpAndSettle();
    expect(find.text('Access denied.'), findsOneWidget);
    expect(find.text('No shifts'), findsNothing);
    expect(find.text('Previously loaded'), findsNothing);
    await tester.tap(find.text('Retry'));
    await flushRequests(tester);
    expect(requests.last.queryParameters['status'], 'Inactive');
    succeed(2);
    await tester.pumpAndSettle();
    expect(find.text('No shifts'), findsOneWidget);
    expect(find.text('Access denied.'), findsNothing);
  });

  testWidgets('completion after disposal does not update widget state', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    succeed(0, name: 'Late response');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
