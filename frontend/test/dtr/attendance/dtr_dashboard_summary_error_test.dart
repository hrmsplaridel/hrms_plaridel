import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/shared/pages/dtr_dashboard_content.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_summary_card.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';

const _summaryPath = '/api/dtr-daily-summary/summary';

Finder inCards(String text) => find.descendant(
  of: find.byType(DtrSummaryCard),
  matching: find.text(text),
);

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  testWidgets(
    'summary failure shows a plain message with Retry instead of zero counts',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var summaryFails = true;
      final dio = ApiClient.instance.dio;
      dio.interceptors.clear();
      addTearDown(dio.interceptors.clear);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == _summaryPath && summaryFails) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 500,
                    // Same body the backend sends on failure.
                    data: {'error': 'Failed to fetch DTR summary counts'},
                  ),
                ),
              );
              return;
            }
            final data = options.path == _summaryPath
                ? {
                    'present_today': 42,
                    'late_today': 3,
                    'on_leave_today': 2,
                    'pending_approval': 1,
                  }
                : <dynamic>[];
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );

      final dtr = DtrProvider();
      addTearDown(dtr.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<DtrProvider>.value(
          value: dtr,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DtrDashboardContent()),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text("Attendance data couldn't be loaded."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // No developer or raw technical text.
      expect(find.textContaining('Query 8'), findsNothing);
      expect(find.textContaining('SUPABASE'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
      expect(
        find.text(
          'Failed to fetch DTR summary counts. If this keeps happening, '
          'contact your system administrator.',
        ),
        findsOneWidget,
      );
      // Failed counts are not shown as zeros.
      expect(inCards('—'), findsNWidgets(4));
      expect(inCards('0'), findsNothing);

      summaryFails = false;
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text("Attendance data couldn't be loaded."), findsNothing);
      expect(inCards('42'), findsOneWidget);
      expect(inCards('—'), findsNothing);
    },
  );
}
