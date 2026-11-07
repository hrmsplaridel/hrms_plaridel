import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/dtr_reports.dart';

void main() {
  late DateTime month;
  late DateTime monthEnd;
  late List<Map<String, dynamic>> overrides;
  late Set<int> omittedDays;

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
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
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
                  'is_active': true,
                  'employment_status': 'active',
                },
              ];
            case '/api/assignments':
              data = [
                {
                  'id': 'assignment',
                  'effective_from': dateKey(month),
                  'effective_to': dateKey(monthEnd),
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

  Future<void> openReport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DtrProvider(),
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: DtrReports())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Employee'), findsWidgets);
    expect(tester.takeException(), isNull);
  }

  void expectOfficialActions(WidgetTester tester, {required bool enabled}) {
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
}
