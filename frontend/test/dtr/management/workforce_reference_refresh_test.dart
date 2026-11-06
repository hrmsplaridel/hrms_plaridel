import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';
import 'package:hrms_plaridel/features/dtr/management/attendance_policies/pages/manage_attendance_policy.dart';
import 'package:hrms_plaridel/features/dtr/management/weekly_schedules/pages/manage_weekly_schedule.dart';

void main() {
  late List<RequestOptions> requests;
  late Map<String, dynamic> data;
  late ValueNotifier<bool> active;
  Completer<void>? delayedShifts;

  setUp(() {
    requests = [];
    active = ValueNotifier(true);
    delayedShifts = null;
    data = {
      '/api/employees': {
        'employees': [
          {
            'id': 'employee',
            'full_name': 'Test Employee',
            'is_active': true,
            'employment_status': 'active',
            'employee_number': 1,
          },
        ],
        'total': 1,
      },
      '/api/assignments/context': {
        'official_date': '2026-11-06',
        'first_date': '2020-01-01',
        'last_date': '2030-12-31',
      },
      '/api/assignments': <dynamic>[],
      '/api/employee-other-positions': <dynamic>[],
      '/api/departments': [
        {'id': 'dept', 'name': 'Human Resources'},
      ],
      '/api/positions': [
        {'id': 'position', 'name': 'HR Officer', 'department_id': 'dept'},
      ],
      '/api/shifts': [
        {
          'id': 'shift',
          'name': 'Office Shift',
          'start_time': '08:00:00',
          'end_time': '17:00:00',
          'break_end': '13:00:00',
        },
      ],
      '/api/attendance-policies': <dynamic>[],
    };
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          if (options.path == '/api/weekly-schedules') {
            final monday = DateTime.parse(
              options.queryParameters['week_start'] as String,
            );
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'employees': [
                    {
                      'employee_id': 'employee',
                      'employee_name': data['employee_name'] ?? 'Test Employee',
                      'days': [
                        for (var i = 0; i < 7; i++)
                          {
                            'date': monday
                                .add(Duration(days: i))
                                .toIso8601String()
                                .split('T')
                                .first,
                            'shift_name': 'Office Shift',
                            'start_time': '08:00:00',
                            'end_time': '17:00:00',
                            'default_is_working_day': i < 5,
                          },
                      ],
                    },
                  ],
                },
              ),
            );
            return;
          }
          final responseData = data[options.path];
          if (options.path == '/api/shifts' && delayedShifts != null) {
            await delayedShifts!.future;
          }
          if (responseData != null) {
            handler.resolve(
              Response<dynamic>(requestOptions: options, data: responseData),
            );
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'Unexpected request',
              ),
            );
          }
        },
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.dio.interceptors.clear();
    active.dispose();
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<bool>(
              valueListenable: active,
              child: screen,
              builder: (context, enabled, child) => Offstage(
                offstage: !enabled,
                child: TickerMode(enabled: enabled, child: child!),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> returnToTab(WidgetTester tester) async {
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label, String value) async {
    // Fields use external labels; find the nearest field container instead of
    // depending on its current options or selection key.
    final field = find
        .ancestor(of: find.text(label).last, matching: find.byType(Column))
        .evaluate()
        .map((e) => e.widget)
        .whereType<Column>()
        .first;
    final finder = find
        .descendant(
          of: find.byWidget(field),
          matching: find.byType(DropdownButtonFormField<String>),
        )
        .first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets('cached assignments refresh every reference category on return', (
    tester,
  ) async {
    await open(tester, const ManageAssignment());
    for (final path in [
      '/api/departments',
      '/api/positions',
      '/api/shifts',
      '/api/attendance-policies',
    ]) {
      data[path] = [
        ...data[path] as List,
        {
          'id': 'new',
          'name': 'New option',
          'policy_name': 'New option',
          'department_id': 'new',
        },
      ];
    }
    await returnToTab(tester);
    for (final path in [
      '/api/departments',
      '/api/positions',
      '/api/shifts',
      '/api/attendance-policies',
    ]) {
      expect(requests.where((r) => r.path == path), hasLength(2), reason: path);
    }
    await tester.tap(find.text('Test Employee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Primary'));
    await tester.pumpAndSettle();
    await choose(tester, 'Department', 'New option');
    await choose(tester, 'Position', 'New option');
    await choose(tester, 'Shift', 'New option');
    await choose(tester, 'Attendance Policy', 'New option');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening Other Position refreshes departments without changing tabs',
    (tester) async {
      await open(tester, const ManageAssignment());
      data['/api/departments'] = [
        {'id': 'new', 'name': 'New Department'},
      ];
      await tester.tap(find.text('Test Employee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Other'));
      await tester.pumpAndSettle();
      // Existing SwitchListTile ink warning is unrelated to reference refresh.
      final warning = tester.takeException();
      if (warning != null) {
        expect(
          warning.toString(),
          contains(
            'ListTile background color or ink splashes may be invisible',
          ),
        );
      }
      await choose(tester, 'Department', 'New Department');
      final refreshWarning = tester.takeException();
      if (refreshWarning != null) {
        expect(
          refreshWarning.toString(),
          contains(
            'ListTile background color or ink splashes may be invisible',
          ),
        );
      }
    },
  );

  testWidgets(
    'primary assignment refresh preserves draft selections and remarks',
    (tester) async {
      await open(tester, const ManageAssignment());
      await tester.tap(find.text('Test Employee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Primary'));
      await tester.pumpAndSettle();
      await choose(tester, 'Department', 'Human Resources');
      await choose(tester, 'Position', 'HR Officer');
      await choose(tester, 'Shift', 'Office Shift');
      final remarks = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Notes about this assignment',
      );
      await tester.ensureVisible(remarks);
      await tester.enterText(remarks, 'Keep these unsaved notes');
      await returnToTab(tester);
      expect(
        tester.widget<TextField>(remarks).controller!.text,
        'Keep these unsaved notes',
      );
      final fields = tester.widgetList<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(
        fields.map((field) => field.initialValue),
        containsAll(['dept', 'position', 'shift']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cached policies refresh shift templates on return', (
    tester,
  ) async {
    await open(tester, const ManageAttendancePolicy());
    data['/api/shifts'] = [
      {
        'id': 'new',
        'name': 'New Shift',
        'start_time': '08:00:00',
        'end_time': '12:00:00',
        'punch_mode': 'am_only',
      },
    ];
    await returnToTab(tester);
    expect(requests.where((r) => r.path == '/api/shifts'), hasLength(2));
    await tester.tap(find.text('Add Policy').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Shift - 4 hrs').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('attendance-policy-work-hours')),
          )
          .controller!
          .text,
      '4',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening policy refreshes templates and preserves typed work hours',
    (tester) async {
      await open(tester, const ManageAttendancePolicy());
      delayedShifts = Completer<void>();
      data['/api/shifts'] = [
        {
          'id': 'new',
          'name': 'New Shift',
          'start_time': '08:00:00',
          'end_time': '12:00:00',
          'punch_mode': 'am_only',
        },
      ];
      await tester.tap(find.text('Add Policy').first);
      await tester.pumpAndSettle();
      final hours = find.byKey(const Key('attendance-policy-work-hours'));
      await tester.enterText(hours, '7.5');
      delayedShifts!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(hours).controller!.text, '7.5');
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('New Shift - 4 hrs'), findsOneWidget);
    },
  );

  testWidgets(
    'late initial policy templates cannot replace newer drawer choices',
    (tester) async {
      delayedShifts = Completer<void>();
      final oldRequest = delayedShifts!;
      await open(tester, const ManageAttendancePolicy());
      delayedShifts = null;
      data['/api/shifts'] = [
        {
          'id': 'new',
          'name': 'New Shift',
          'start_time': '08:00:00',
          'end_time': '12:00:00',
          'punch_mode': 'am_only',
        },
      ];
      await tester.tap(find.text('Add Policy').first);
      await tester.pumpAndSettle();
      oldRequest.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('New Shift - 4 hrs'), findsOneWidget);
      expect(find.text('Office Shift - 8 hrs'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly schedule refreshes employees and department choices on return',
    (tester) async {
      await open(tester, const ManageWeeklySchedule());
      data['employee_name'] = 'Updated Employee';
      data['/api/departments'] = [
        {'id': 'new', 'name': 'New Department'},
      ];
      await returnToTab(tester);
      expect(find.text('Updated Employee'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('New Department'), findsOneWidget);
      expect(
        requests.where((r) => r.path == '/api/weekly-schedules'),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly schedule keeps unsaved overrides until explicitly discarded',
    (tester) async {
      await open(tester, const ManageWeeklySchedule());
      await tester.tap(find.text('8:00a-5:00p').first);
      await tester.pumpAndSettle();
      data['employee_name'] = 'Updated Employee';
      data['/api/departments'] = [
        {'id': 'new', 'name': 'New Department'},
      ];
      await returnToTab(tester);
      expect(find.text('Save 1 employee'), findsOneWidget);
      expect(find.text('Test Employee'), findsOneWidget);
      expect(
        requests.where((r) => r.path == '/api/weekly-schedules'),
        hasLength(1),
      );
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Updated Employee'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('New Department'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removed weekly department filter safely resets on return', (
    tester,
  ) async {
    await open(tester, const ManageWeeklySchedule());
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Human Resources').last);
    await tester.pumpAndSettle();
    data['/api/departments'] = <dynamic>[];
    await returnToTab(tester);
    expect(find.text('All departments'), findsOneWidget);
    expect(
      requests
          .lastWhere((r) => r.path == '/api/weekly-schedules')
          .queryParameters,
      isNot(contains('department_id')),
    );
    expect(tester.takeException(), isNull);
  });
}
