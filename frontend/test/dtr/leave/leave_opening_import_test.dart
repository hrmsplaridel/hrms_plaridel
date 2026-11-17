import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_opening_import_dialog.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'import at $width requires valid preview and confirmation; editing clears both',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        final posts = <Map>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              posts.add(Map.from(o.data as Map));
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'valid': true,
                    'total': 1,
                    'imported': 0,
                    'rows': [
                      {
                        'row': 2,
                        'employee_number': '3',
                        'employee_name': 'Test Employee',
                        'sick_leave_days': '12',
                        'vacation_leave_days': '10',
                        'qualifying_leave_days': '0',
                        'cutoff_date': '2026-10-31',
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: AdminLeaveOpeningImportDialog()),
          ),
        );
        final import = find.widgetWithText(FilledButton, 'Import balances');
        expect(tester.widget<FilledButton>(import).onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('opening-import-csv')),
          'CSV content',
        );
        await tester.pump();
        await tester.tap(find.text('Validate preview'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Test Employee'), findsOneWidget);
        expect(tester.widget<FilledButton>(import).onPressed, isNull);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        expect(tester.widget<FilledButton>(import).onPressed, isNotNull);
        await tester.enterText(
          find.byKey(const ValueKey('opening-import-csv')),
          'Changed CSV',
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(import).onPressed, isNull);
        expect(posts.single['mode'], 'preview');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('invalid preview shows row errors and keeps import disabled', (
    tester,
  ) async {
    ApiClient.instance.dio.interceptors.clear();
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'valid': false,
                'total': 1,
                'imported': 0,
                'rows': [
                  {
                    'row': 2,
                    'employee_number': '3',
                    'error': 'Opening balances are already recorded.',
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdminLeaveOpeningImportDialog())),
    );
    await tester.enterText(
      find.byKey(const ValueKey('opening-import-csv')),
      'CSV',
    );
    await tester.pump();
    await tester.tap(find.text('Validate preview'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Opening balances are already recorded.'),
      findsOneWidget,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import balances'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
