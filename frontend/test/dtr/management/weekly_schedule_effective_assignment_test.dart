import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/weekly_schedules/pages/manage_weekly_schedule.dart';

void main() {
  testWidgets(
    'midweek assignment stays under its dates and saves only changed days',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.init();
      final dio = ApiClient.instance.dio;
      dio.interceptors.clear();
      addTearDown(dio.interceptors.clear);
      Map<String, dynamic>? saved;
      String? thursday;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/api/departments') {
              handler.resolve(Response(requestOptions: options, data: []));
              return;
            }
            if (options.path == '/api/weekly-schedules') {
              final monday = DateTime.parse(
                options.queryParameters['week_start'].toString(),
              );
              String date(int offset) {
                final day = monday.add(Duration(days: offset));
                return '${day.year.toString().padLeft(4, '0')}-'
                    '${day.month.toString().padLeft(2, '0')}-'
                    '${day.day.toString().padLeft(2, '0')}';
              }

              thursday = date(3);
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'employees': [
                      {
                        'employee_id': '11111111-1111-4111-8111-111111111111',
                        'employee_name': 'Earl D Bullet',
                        'days': [
                          for (var index = 3; index < 7; index++)
                            {
                              'date': date(index),
                              'shift_name': 'Overnight Shift',
                              'start_time': '22:00:00',
                              'end_time': '07:00:00',
                              'default_is_working_day': index < 5,
                            },
                        ],
                      },
                    ],
                  },
                ),
              );
              return;
            }
            if (options.method == 'PUT' &&
                options.path.startsWith('/api/weekly-schedules/')) {
              saved = Map<String, dynamic>.from(options.data as Map);
              handler.resolve(
                Response(requestOptions: options, data: {'ok': true}),
              );
              return;
            }
            handler.reject(DioException(requestOptions: options));
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
      expect(find.text('No assignment'), findsNWidgets(4));
      expect(find.text('10:00p-7:00a'), findsNWidgets(2));
      expect(find.text('REST'), findsNWidgets(2));
      await tester.tap(find.text('10:00p-7:00a').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 1 employee'));
      await tester.pumpAndSettle();
      expect(saved?['days'], [
        {'date': thursday, 'is_working_day': false},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
