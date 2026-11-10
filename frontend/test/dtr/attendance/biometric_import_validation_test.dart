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
  Map<String, dynamic> reviewResponse = {};
  bool reviewFails = false;
  bool changedCoverage = false;

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
          } else if (options.path ==
              '/api/biometric-attendance-logs/import/preview') {
            if (reviewFails) {
              handler.reject(DioException(requestOptions: options));
            } else {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  data: reviewResponse,
                ),
              );
            }
          } else if (options.path == '/api/biometric-attendance-logs/import') {
            if (changedCoverage) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 409,
                    data: {...reviewResponse, 'code': 'IMPORT_REVIEW_REQUIRED'},
                  ),
                ),
              );
              return;
            }
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

  setUp(() {
    requests.clear();
    reviewFails = false;
    changedCoverage = false;
    reviewResponse = {
      'rows_total': 2,
      'rows_ready': 2,
      'rows_excluded': 0,
      'warning_count': 0,
      'row_errors': [],
      'review_warnings': [],
    };
  });

  Future<void> openAndImport(WidgetTester tester, {bool confirm = true}) async {
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.where((r) => r.path.endsWith('/import')), isEmpty);
    if (!confirm) return;
    await tester.tap(find.widgetWithText(FilledButton, 'Import 2 rows'));
    // The parent keeps its progress indicator while the result dialog is open.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requests.where((r) => r.path.endsWith('/import')).length, 1);
  }

  testWidgets('preview excludes holiday rows before HR confirms import', (
    tester,
  ) async {
    reviewResponse = {
      'rows_total': 2,
      'rows_ready': 1,
      'rows_excluded': 1,
      'warning_count': 0,
      'review_warnings': [],
      'row_errors': [
        {
          'row': 1,
          'biometric_user_id': '1001',
          'attendance_date': '2026-09-12',
          'code': 'holiday',
          'error': 'Excluded: holiday covers this session.',
        },
      ],
    };
    await openAndImport(tester, confirm: false);
    expect(
      find.textContaining('Excluded: holiday covers this session.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Import 1 row'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all excluded rows disable the final import action', (
    tester,
  ) async {
    reviewResponse = {
      'rows_total': 2,
      'rows_ready': 0,
      'rows_excluded': 2,
      'warning_count': 0,
      'review_warnings': [],
      'row_errors': [],
    };
    await openAndImport(tester, confirm: false);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'No rows to import'),
          )
          .onPressed,
      isNull,
    );
    expect(requests.where((r) => r.path.endsWith('/import')), isEmpty);
  });

  testWidgets('locator warning requires review before confirmation', (
    tester,
  ) async {
    reviewResponse['warning_count'] = 1;
    reviewResponse['review_warnings'] = [
      {
        'row': 1,
        'biometric_user_id': '1001',
        'attendance_date': '2026-09-12',
        'code': 'locator_review',
        'message': 'Verify approved locator coverage.',
      },
    ];
    importResponse = {'inserted': 2, 'summaries_inserted': 1};
    await openAndImport(tester, confirm: false);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import 2 rows'),
          )
          .onPressed,
      isNull,
    );
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import 2 rows'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final submission = requests.singleWhere((r) => r.path.endsWith('/import'));
    expect((submission.data as Map)['warnings_reviewed'], true);
    expect(find.text('Import Complete'), findsOneWidget);
  });

  testWidgets('new warnings at confirmation return HR to review', (
    tester,
  ) async {
    await openAndImport(tester, confirm: false);
    changedCoverage = true;
    reviewResponse['warning_count'] = 1;
    reviewResponse['review_warnings'] = [
      {'row': 1, 'message': 'A locator was approved after the first preview.'},
    ];
    await tester.tap(find.widgetWithText(FilledButton, 'Import 2 rows'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.textContaining('A locator was approved after the first preview.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import 2 rows'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the selected file invalidates its previous review', (
    tester,
  ) async {
    await openAndImport(tester, confirm: false);
    final bytes = Uint8List.fromList(utf8.encode('1001,10 Jan 2026 17:00'));
    tester
        .widget<DragTarget<Object>>(find.byType(DragTarget<Object>))
        .onAcceptWithDetails!(
      DragTargetDetails<Object>(
        data: PlatformFile(name: 'other.csv', size: bytes.length, bytes: bytes),
        offset: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.text('Review before importing'), findsNothing);
    expect(requests.where((r) => r.path.endsWith('/import')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed review cannot fall back to importing unchecked rows', (
    tester,
  ) async {
    reviewFails = true;
    await openAndImport(tester, confirm: false);
    expect(find.textContaining('Import failed:'), findsOneWidget);
    expect(requests.where((r) => r.path.endsWith('/import')), isEmpty);
  });

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
