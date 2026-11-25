import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/weekly_schedules/pages/manage_weekly_schedule.dart';

const _employeeId = '11111111-1111-4111-8111-111111111111';
const _nightId = '22222222-2222-4222-8222-222222222222';
const _morningId = '33333333-3333-4333-8333-333333333333';

String _date(DateTime monday, int offset) {
  final day = monday.add(Duration(days: offset));
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime _currentMonday() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - DateTime.monday));
}

Map<String, dynamic> _week(
  DateTime monday, {
  Map<int, String> roster = const {},
}) {
  return {
    'employees': [
      {
        'employee_id': _employeeId,
        'employee_name': 'Nurse Ana',
        'department_name': 'Hospital',
        'days': [
          for (var index = 0; index < 7; index++)
            {
              'date': _date(monday, index),
              'shift_id': _morningId,
              'shift_name': 'Morning',
              'start_time': '06:00:00',
              'end_time': '14:00:00',
              'default_is_working_day': index < 5,
              if (roster.containsKey(index)) ...{
                'override_is_working_day': true,
                'roster_shift_id': roster[index],
                'roster_shift_name': 'Night duty',
                'roster_start_time': '22:00:00',
                'roster_end_time': '06:00:00',
              },
            },
        ],
      },
    ],
  };
}

void main() {
  late List<Map<String, dynamic>> puts;
  late Map<int, String> previousWeekRoster;
  late Map<int, String> currentWeekRoster;

  setUp(() {
    puts = [];
    previousWeekRoster = {};
    currentWeekRoster = {};
    ApiClient.instance.init();
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/departments') {
            handler.resolve(Response(requestOptions: options, data: []));
          } else if (options.path == '/api/shifts') {
            handler.resolve(
              Response(
                requestOptions: options,
                data: [
                  {
                    'id': _morningId,
                    'name': 'Morning',
                    'start_time': '06:00:00',
                    'end_time': '14:00:00',
                  },
                  {
                    'id': _nightId,
                    'name': 'Night duty',
                    'start_time': '22:00:00',
                    'end_time': '06:00:00',
                  },
                ],
              ),
            );
          } else if (options.method == 'GET' &&
              options.path == '/api/weekly-schedules') {
            final monday = DateTime.parse(
              options.queryParameters['week_start'].toString(),
            );
            final isCurrent = monday == _currentMonday();
            handler.resolve(
              Response(
                requestOptions: options,
                data: _week(
                  monday,
                  roster: isCurrent ? currentWeekRoster : previousWeekRoster,
                ),
              ),
            );
          } else if (options.method == 'PUT') {
            puts.add(Map<String, dynamic>.from(options.data as Map));
            handler.resolve(
              Response(requestOptions: options, data: {'ok': true}),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ManageWeeklySchedule()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a rostered day shows its duty shift', (tester) async {
    currentWeekRoster = {2: _nightId};
    await open(tester);
    expect(find.text('10:00p-6:00a'), findsOneWidget);
    expect(find.text('Night duty'), findsOneWidget);
    expect(find.text('6:00a-2:00p'), findsNWidgets(4));
  });

  testWidgets('choosing a duty shift saves it for that day', (tester) async {
    await open(tester);
    final monday = _currentMonday();
    await tester.tap(find.byTooltip('Choose duty shift').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night duty (10:00p-6:00a)').last);
    await tester.pumpAndSettle();
    expect(find.text('10:00p-6:00a'), findsOneWidget);
    await tester.tap(find.text('Save 1 employee'));
    await tester.pumpAndSettle();
    expect(puts.single['days'], [
      {'date': _date(monday, 1), 'is_working_day': null, 'shift_id': _nightId},
    ]);
  });

  testWidgets('copy previous week brings over its duty shifts', (tester) async {
    previousWeekRoster = {0: _nightId, 4: _nightId};
    await open(tester);
    final monday = _currentMonday();
    await tester.tap(find.text('Copy previous week'));
    await tester.pumpAndSettle();
    expect(find.text('10:00p-6:00a'), findsNWidgets(2));
    await tester.tap(find.text('Save 1 employee'));
    await tester.pumpAndSettle();
    expect(puts.single['days'], [
      {'date': _date(monday, 0), 'is_working_day': true, 'shift_id': _nightId},
      {'date': _date(monday, 4), 'is_working_day': true, 'shift_id': _nightId},
    ]);
  });
}
