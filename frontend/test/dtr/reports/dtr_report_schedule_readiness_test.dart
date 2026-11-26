import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/dtr_reports.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_summary_card.dart';

void main() {
  late DateTime month;
  late DateTime monthEnd;
  late List<Map<String, dynamic>> overrides;
  late Set<int> omittedDays;
  late String employmentStatus;
  final requests = <RequestOptions>[];

  String dateKey(DateTime date) => date.toIso8601String().split('T').first;
  DateTime firstWeekday(int weekday) => List.generate(
    7,
    (offset) => month.add(Duration(days: offset)),
  ).firstWhere((date) => date.weekday == weekday);

  setUp(() {
    final today = DateTime.now();
    month = DateTime(today.year, today.month, 1);
    monthEnd = DateTime(today.year, today.month + 1, 0);
    overrides = [];
    omittedDays = {};
    employmentStatus = 'active';
    requests.clear();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          dynamic data;
          switch (options.path) {
            case '/api/dtr-daily-summary/report-years':
              data = {
                'years': [month.year],
              };
            case '/api/departments':
              data = <dynamic>[];
            case '/api/employees':
              data = [
                {
                  'id': 'employee',
                  'full_name': 'Test Employee',
                  'employee_number': 1,
                  'is_active': employmentStatus == 'active',
                  'employment_status': employmentStatus,
                },
              ];
            case '/api/assignments':
              data = [
                {
                  'id': 'assignment',
                  'effective_from': dateKey(month),
                  'effective_to': employmentStatus == 'inactive'
                      ? null
                      : dateKey(monthEnd),
                  'working_days': [1, 2, 3, 4, 5],
                  'start_time': '08:00:00',
                  'end_time': '17:00:00',
                  'break_end': '13:00:00',
                  'schedule_overrides': overrides,
                },
              ];
            case '/api/dtr-report-signatories':
              data = {
                'roles': {
                  for (final role in [
                    'dtr_office_hours_verifier',
                    'dtr_hr_officer',
                  ])
                    role: {
                      'configured': true,
                      'current': {
                        'name': 'Report Officer',
                        'position_title': 'Officer',
                      },
                    },
                },
              };
            case '/api/dtr-daily-summary':
              data = <Map<String, dynamic>>[];
              for (var day = 1; day <= monthEnd.day; day++) {
                final date = DateTime(month.year, month.month, day);
                final override = overrides.where(
                  (item) => item['date'] == dateKey(date),
                );
                final isWorking = override.isEmpty
                    ? date.weekday <= DateTime.friday
                    : override.first['is_working_day'] == true;
                if (!isWorking || omittedDays.contains(day)) continue;
                data.add({
                  'id': 'record-$day',
                  'user_id': 'employee',
                  'record_date': dateKey(date),
                  'status': 'present',
                  'attendance_policy': {
                    'id': 'policy',
                    'work_hours_per_day': 8,
                  },
                  'report_deduction': {
                    'late_minutes': 0,
                    'undertime_minutes': 0,
                    'absence_minutes': 0,
                    'total_minutes': 0,
                    'equivalent_day': 0,
                  },
                });
              }
            default:
              handler.reject(
                DioException(
                  requestOptions: options,
                  message: 'Unexpected request: ${options.path}',
                ),
              );
              return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: data,
              statusCode: 200,
              headers: Headers.fromMap({
                'x-reportable-through': [dateKey(monthEnd)],
              }),
            ),
          );
        },
      ),
    );
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openReport(
    WidgetTester tester, {
    double width = 1800,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DtrProvider(),
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: SingleChildScrollView(child: DtrReports()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Employee'), findsWidgets);
    expect(tester.takeException(), isNull);
  }

  void expectOfficialActions(WidgetTester tester, {required bool enabled}) {
    expect(find.text('Last day of service is missing'), findsNothing);
    expect(
      tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'PREVIEW'),
              )
              .onPressed !=
          null,
      enabled,
    );
    expect(
      tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'PRINT CURRENT'),
              )
              .onPressed !=
          null,
      enabled,
    );
    expect(
      find.text('Official report unavailable'),
      enabled ? findsNothing : findsOneWidget,
    );
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('inactive employment warning explains the next step at '
          '$width in $brightness', (tester) async {
        employmentStatus = 'inactive';
        await openReport(tester, width: width, brightness: brightness);

        expect(find.text('Last day of service is missing'), findsOneWidget);
        expect(
          find.text(
            "Update this employee's service dates in Employees to finalize their DTR.",
          ),
          findsOneWidget,
        );
        expect(
          find.text('Missing days are not counted as absences.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
        expect(find.textContaining('assignment is still open'), findsNothing);

        await tester.ensureVisible(find.text('Details'));
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.textContaining('assignment is still open'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final summary = tester.widget<DtrReportSummaryCard>(
          find.byType(DtrReportSummaryCard),
        );
        expect(summary.hideCounts, isTrue);
        expect(summary.actionsEnabled, isFalse);
      });
    }
  }

  testWidgets(
    'weekday overridden as rest needs no policy record for official reports',
    (tester) async {
      overrides = [
        {
          'date': dateKey(firstWeekday(DateTime.wednesday)),
          'is_working_day': false,
        },
      ];
      await openReport(tester);
      expectOfficialActions(tester, enabled: true);
    },
  );

  testWidgets(
    'weekend overridden as working blocks reports without verified attendance',
    (tester) async {
      final saturday = firstWeekday(DateTime.saturday);
      overrides = [
        {'date': dateKey(saturday), 'is_working_day': true},
      ];
      omittedDays.add(saturday.day);
      await openReport(tester);
      expectOfficialActions(tester, enabled: false);
    },
  );

  testWidgets(
    'verified attendance on a working weekend allows official reports',
    (tester) async {
      overrides = [
        {
          'date': dateKey(firstWeekday(DateTime.saturday)),
          'is_working_day': true,
        },
      ];
      await openReport(tester);
      expectOfficialActions(tester, enabled: true);
    },
  );

  testWidgets('ordinary working days still require verified attendance', (
    tester,
  ) async {
    omittedDays.add(firstWeekday(DateTime.wednesday).day);
    await openReport(tester);
    expectOfficialActions(tester, enabled: false);
  });
  testWidgets(
    'day filters update locally and reset reloads the current period',
    (tester) async {
      await openReport(tester);
      final initialRequests = requests.length;
      Finder dayFilter(String prefix) => find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButton<int> &&
            widget.items!.any(
              (item) =>
                  item.child is Text &&
                  ((item.child as Text).data ?? '').startsWith(prefix),
            ),
      );
      tester.widget<DropdownButton<int>>(dayFilter('From day ')).onChanged!(5);
      await tester.pumpAndSettle();
      tester.widget<DropdownButton<int>>(dayFilter('To day ')).onChanged!(7);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<int>>(dayFilter('From day ')).value,
        5,
      );
      expect(tester.widget<DropdownButton<int>>(dayFilter('To day ')).value, 7);
      expect(requests.length, initialRequests);
      await tester.tap(find.widgetWithText(OutlinedButton, 'RESET'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<int>>(dayFilter('From day ')).value,
        1,
      );
      expect(
        tester.widget<DropdownButton<int>>(dayFilter('To day ')).value,
        monthEnd.day,
      );
      final employeeRequest = requests.lastWhere(
        (r) => r.path == '/api/employees',
      );
      expect(employeeRequest.queryParameters['status'], 'Active');
      expect(employeeRequest.queryParameters['start_date'], dateKey(month));
      expect(employeeRequest.queryParameters['end_date'], dateKey(monthEnd));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 420.0, 768.0]) {
    testWidgets('report lays out without overflow at width $width', (
      tester,
    ) async {
      await openReport(tester, width: width);
      expect(find.text('Test Employee'), findsWidgets);
    });
  }
}
