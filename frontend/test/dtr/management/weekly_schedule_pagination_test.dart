import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/weekly_schedules/pages/manage_weekly_schedule.dart';

void main() {
  testWidgets('roster pages contain 25 employees and search resets the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiClient.instance.init();
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    addTearDown(dio.interceptors.clear);
    var reads = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/departments') {
            handler.resolve(Response(requestOptions: options, data: []));
          } else if (options.path == '/api/weekly-schedules') {
            reads++;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'employees': List.generate(
                    options.queryParameters['q'] == null ? 26 : 1,
                    (i) => {
                      'employee_id': '$i',
                      'employee_name': 'Employee ${i + 1}',
                      'days': List.generate(
                        7,
                        (day) => {
                          'date': '2026-09-${21 + day}',
                          'default_is_working_day': day < 5,
                          'start_time': '08:00',
                          'end_time': '17:00',
                        },
                      ),
                    },
                  ),
                },
              ),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ManageWeeklySchedule()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Employee 25'), findsOneWidget);
    expect(find.text('Employee 26'), findsNothing);
    expect(find.text('Showing 1-25 of 26 employees'), findsOneWidget);
    final next = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Next employee page',
    );
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Employee 26'), findsOneWidget);
    expect(find.text('Employee 1'), findsNothing);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(reads, 1);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Employee 1');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Showing 1-1 of 1 employees'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
