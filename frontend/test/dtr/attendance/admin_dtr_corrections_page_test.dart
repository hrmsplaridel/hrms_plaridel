import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/pages/admin_dtr_corrections_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [390.0, 1200.0]) {
    testWidgets('correction queue filters and opens a request at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.reset);
      final requests = <RequestOptions>[];
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final detail = options.path.endsWith('/request-1');
            handler.resolve(
              Response(
                requestOptions: options,
                data: detail
                    ? {
                        'id': 'request-1',
                        'employee_name': 'Earl D Bullet',
                        'attendance_date': '2026-10-01',
                        'status': 'approved',
                        'reason': 'The biometric device was offline.',
                      }
                    : [
                        {
                          'id': 'request-1',
                          'employee_name': 'Earl D Bullet',
                          'attendance_date': '2026-10-01',
                          'status': 'approved',
                          'reason': 'The biometric device was offline.',
                        },
                      ],
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminDtrCorrectionsPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('DTR Corrections'), findsOneWidget);
      expect(find.text('Request Queue'), findsOneWidget);
      expect(find.text('Earl D Bullet'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Approved'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['status'], 'approved');
      await tester.ensureVisible(find.text('Earl D Bullet'));
      await tester.tap(find.text('Earl D Bullet'));
      await tester.pumpAndSettle();
      expect(requests.last.path, '/api/dtr-corrections/request-1');
      expect(find.text('Status: approved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
