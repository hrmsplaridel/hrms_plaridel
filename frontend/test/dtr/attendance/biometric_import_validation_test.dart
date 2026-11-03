import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/import_biometric_attendance_logs_dialog.dart';

void main() {
  final requests = <RequestOptions>[];
  Map<String, dynamic> importResponse = {};

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path == '/api/employees') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [
                  {
                    'id': '11111111-1111-4111-8111-111111111111',
                    'biometric_user_id': '1001',
                    'full_name': 'Sample Employee',
                  },
                ],
              ),
            );
          } else if (options.path == '/api/biometric-attendance-logs/import') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: importResponse,
              ),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
  });

  setUp(requests.clear);

  Future<void> openAndImport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportBiometricAttendanceLogsDialog(onCancel: () {}),
        ),
      ),
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        '1001\t2026-09-12 08:00:00\t1\t0\t0\n'
        '1001\t2026-09-12 17:00:00\t1\t1\t0',
      ),
    );
    tester
        .widget<DragTarget<Object>>(find.byType(DragTarget<Object>))
        .onAcceptWithDetails!(
      DragTargetDetails<Object>(
        data: PlatformFile(
          name: 'attlog.dat',
          size: bytes.length,
          bytes: bytes,
        ),
        offset: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    // The parent keeps its progress indicator while the result dialog is open.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.where((r) => r.method == 'POST').length, 1);
  }

  testWidgets(
    'partial import shows server rejections and reasons with summary results',
    (tester) async {
      importResponse = {
        'inserted': 1,
        'skipped_invalid_row': 1,
        'row_errors': [
          {
            'row': 2,
            'field': 'punch_code',
            'error': 'punch_code must be text or null',
          },
        ],
        'summaries_inserted': 1,
        'summaries_updated': 0,
      };
      await openAndImport(tester);
      expect(find.text('Import completed with rejected rows'), findsOneWidget);
      expect(find.text('Rejected: invalid row data'), findsOneWidget);
      expect(
        find.text('Submitted row 2: punch_code must be text or null'),
        findsOneWidget,
      );
      expect(find.text('Summaries inserted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'older success responses still show a complete import without rejection details',
    (tester) async {
      importResponse = {'inserted': 2, 'summaries_inserted': 1};
      await openAndImport(tester);
      expect(find.text('Import Complete'), findsOneWidget);
      expect(find.text('Import completed with rejected rows'), findsNothing);
      expect(find.textContaining('Submitted row'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
