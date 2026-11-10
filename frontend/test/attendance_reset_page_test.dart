import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/super_admin/attendance_reset_page.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'attendance reset requires preview, reason and confirmation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        final applied = <Map<String, dynamic>>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final data = options.path.endsWith('/employees')
                  ? {
                      'official_date': '2026-11-08',
                      'time_zone': 'Asia/Manila',
                      'items': [
                        {
                          'id': 'employee',
                          'full_name': 'Test Employee',
                          'employee_number': 17,
                        },
                      ],
                    }
                  : options.path.endsWith('/preview')
                  ? {
                      'employee': {
                        'id': 'employee',
                        'full_name': 'Test Employee',
                      },
                      'attendance_date': options.data['attendance_date'],
                      'time_zone': 'Asia/Manila',
                      'preview_token': 'preview-1',
                      'can_reset': true,
                      'deletion_blocks': 1,
                      'summary': {'id': 'summary'},
                      'processed_months': [
                        {'service_month': '2026-10-01'},
                      ],
                      'punches': [
                        {
                          'id': 'punch',
                          'logged_at_local': '2026-11-08 18:56:53',
                        },
                      ],
                    }
                  : {
                      'punches_deleted': 1,
                      'reconciliation_months': ['2026-10-01'],
                    };
              if (options.path.endsWith('/apply')) {
                applied.add(Map<String, dynamic>.from(options.data));
              }
              handler.resolve(Response(requestOptions: options, data: data));
            },
          ),
        );
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AttendanceResetPage())),
        );
        await tester.pumpAndSettle();
        expect(find.text('Attendance reset'), findsOneWidget);
        await tester.tap(find.text('Test Employee'));
        await tester.pumpAndSettle();
        final preview = find.byKey(const ValueKey('attendance-reset-preview'));
        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        expect(find.textContaining('18:56:53'), findsOneWidget);
        expect(find.textContaining('reconciliation'), findsWidgets);
        final apply = find.byKey(const ValueKey('attendance-reset-apply'));
        expect(tester.widget<FilledButton>(apply).onPressed, isNull);
        final reason = find.byKey(const ValueKey('attendance-reset-reason'));
        await tester.ensureVisible(reason);
        await tester.enterText(reason, 'Remove demonstration punches');
        final confirmation = find.byKey(
          const ValueKey('attendance-reset-confirmation'),
        );
        await tester.ensureVisible(confirmation);
        await tester.enterText(confirmation, 'RESET');
        await tester.pumpAndSettle();
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(applied, hasLength(1));
        expect(applied.single['employee_id'], 'employee');
        expect(applied.single['attendance_date'], '2026-11-08');
        expect(applied.single['preview_token'], 'preview-1');
        expect(applied.single['confirmation'], 'RESET');
        expect(find.textContaining('Attendance reset completed'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'changing date invalidates preview and a failed reset needs a new preview',
    (tester) async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      var previews = 0, applies = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/apply')) {
              applies++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 409,
                    data: {
                      'error':
                          'Attendance changed since the preview. Preview again before resetting.',
                    },
                  ),
                ),
              );
              return;
            }
            if (options.path.endsWith('/preview')) previews++;
            handler.resolve(
              Response(
                requestOptions: options,
                data: options.path.endsWith('/employees')
                    ? {
                        'official_date': '2026-11-08',
                        'items': [
                          {'id': 'employee', 'full_name': 'Test Employee'},
                        ],
                      }
                    : {
                        'employee': {
                          'id': 'employee',
                          'full_name': 'Test Employee',
                        },
                        'attendance_date': '2026-11-08',
                        'can_reset': true,
                        'preview_token': 'token',
                        'punches': [],
                        'summary': {'id': 'entry'},
                        'processed_months': [],
                        'deletion_blocks': 0,
                      },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AttendanceResetPage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Employee'));
      await tester.pumpAndSettle();
      Future<void> pressPreview() async {
        final button = find.byKey(const ValueKey('attendance-reset-preview'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await pressPreview();
      final date = find.byKey(const ValueKey('attendance-reset-date'));
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-11-07');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attendance-reset-apply')),
        findsNothing,
      );
      await pressPreview();
      final reason = find.byKey(const ValueKey('attendance-reset-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Correct test logs');
      final confirmation = find.byKey(
        const ValueKey('attendance-reset-confirmation'),
      );
      await tester.ensureVisible(confirmation);
      await tester.enterText(confirmation, 'RESET');
      await tester.pumpAndSettle();
      final apply = find.byKey(const ValueKey('attendance-reset-apply'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(applies, 1);
      expect(previews, 2);
      expect(
        find.byKey(const ValueKey('attendance-reset-apply')),
        findsNothing,
      );
      expect(
        find.textContaining('Attendance changed since the preview'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
