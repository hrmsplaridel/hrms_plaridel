import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';

void main() {
  late List<Map<String, dynamic>> current;
  late List<Map<String, dynamic>> upcoming;
  late List<RequestOptions> requests;
  Completer<List<Map<String, dynamic>>>? delayedUpcoming;

  Map<String, dynamic> assignment(String id, String start, String status) => {
    'id': id,
    'department_name': 'Test department',
    'position_name': 'Test position',
    'shift_name': 'Day shift',
    'effective_from': start,
    'is_active': true,
    'computed_status': status,
  };

  setUp(() {
    current = [];
    upcoming = [];
    requests = [];
    delayedUpcoming = null;
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          dynamic data = <dynamic>[];
          if (options.path == '/api/employees') {
            data = {
              'employees': [
                for (final id in ['first', 'second'])
                  {
                    'id': id,
                    'full_name': '$id employee',
                    'is_active': true,
                    'employment_status': 'active',
                  },
              ],
              'total': 2,
            };
          } else if (options.path == '/api/assignments/context') {
            data = {
              'official_date': '2026-10-17',
              'first_date': '2020-01-01',
              'last_date': '2030-12-31',
            };
          } else if (options.path == '/api/assignments') {
            if (options.queryParameters['employee_id'] == 'second') {
              data = <dynamic>[];
            } else if (options.queryParameters['status'] == 'Upcoming') {
              data = delayedUpcoming == null
                  ? upcoming
                  : await delayedUpcoming!.future;
            } else {
              data = current;
            }
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openPage(WidgetTester tester, {bool settle = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ManageAssignment())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('first employee'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Current empty state shows the earliest upcoming start date', (
    tester,
  ) async {
    upcoming = [
      assignment('later', '2026-11-03', 'Upcoming'),
      assignment('earlier', '2026-10-20', 'Upcoming'),
    ];
    await openPage(tester);
    expect(
      find.text(
        'No current assignment. Upcoming assignment starts October 20.',
      ),
      findsOneWidget,
    );
    expect(find.text('Test department'), findsNothing);
    expect(find.text('No primary assignment yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Current empty state without a scheduled assignment is accurate',
    (tester) async {
      await openPage(tester);
      expect(find.text('No current assignment.'), findsOneWidget);
      expect(find.textContaining('Upcoming assignment starts'), findsNothing);
    },
  );

  testWidgets('upcoming start in another year includes the year', (
    tester,
  ) async {
    upcoming = [assignment('next-year', '2027-01-05', 'Upcoming')];
    await openPage(tester);
    expect(
      find.text(
        'No current assignment. Upcoming assignment starts January 5, 2027.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a current assignment displays normally without an extra lookup',
    (tester) async {
      current = [assignment('current', '2026-10-01', 'Current')];
      await openPage(tester);
      expect(find.text('Test department'), findsOneWidget);
      expect(find.textContaining('No current assignment'), findsNothing);
      expect(
        requests.where(
          (r) =>
              r.path == '/api/assignments' &&
              r.queryParameters['status'] == 'Upcoming',
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'an old employee lookup cannot replace the next employee message',
    (tester) async {
      delayedUpcoming = Completer<List<Map<String, dynamic>>>();
      await openPage(tester, settle: false);
      await tester.tap(find.text('second employee'));
      await tester.pumpAndSettle();
      delayedUpcoming!.complete([assignment('old', '2026-10-20', 'Upcoming')]);
      await tester.pumpAndSettle();
      expect(find.text('No current assignment.'), findsOneWidget);
      expect(find.textContaining('Upcoming assignment starts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
