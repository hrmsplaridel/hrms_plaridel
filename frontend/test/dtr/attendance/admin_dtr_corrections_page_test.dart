import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/pages/admin_dtr_corrections_page.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_corrections_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final admin in [true, false]) {
    testWidgets(
      'cursor navigation survives failure and returns to first page ($admin)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 1000);
        addTearDown(tester.view.reset);
        final cursors = <dynamic>[];
        var fail = true;
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              expect(options.queryParameters['pagination'], 'cursor');
              expect(options.queryParameters.containsKey('offset'), false);
              final cursor = options.queryParameters['cursor'];
              cursors.add(cursor);
              if (cursor == 'next' && fail) {
                fail = false;
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
                return;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'entries': <dynamic>[],
                    'first_cursor': 'first',
                    'next_cursor': cursor == 'next' ? null : 'next',
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: admin
                  ? const AdminDtrCorrectionsPage()
                  : const DtrCorrectionsDialog(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        expect(find.text('Page 1'), findsOneWidget);
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        expect(find.text('Page 2'), findsOneWidget);
        expect(cursors, [null, 'next', 'next']);
        await tester.tap(find.byTooltip('Previous page'));
        await tester.pumpAndSettle();
        expect(cursors.last, 'first');
        expect(find.text('Page 1'), findsOneWidget);
      },
    );
  }

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
                        'original_record': {'time_in': null},
                        'requested_time_in': '2026-10-01T00:00:00Z',
                        'applied_record': {'time_in': '2026-10-01T00:00:00Z'},
                        'reviewer_name': 'Admin User',
                        'reviewed_at': '2026-10-02T07:16:00Z',
                        'review_notes': 'Verified against device report.',
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
      expect(find.text('Punch comparison'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Review decision'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Review decision'), findsOneWidget);
      expect(find.text('Verified against device report.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
