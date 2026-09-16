import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/holidays/pages/manage_holiday.dart';

void main() {
  final updates = <Map<String, dynamic>>[];
  var coverage = 'am_only';
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'PUT') {
            updates.add(Map<String, dynamic>.from(options.data as Map));
            handler.resolve(
              Response<dynamic>(requestOptions: options, data: {}),
            );
            return;
          }
          handler.resolve(
            Response<List<dynamic>>(
              requestOptions: options,
              data: [
                {
                  'id': 'special-test',
                  'name': 'Special holiday fixture',
                  'date_from': '2026-09-09',
                  'date_to': '2026-09-09',
                  'holiday_type': 'special',
                  'coverage': coverage,
                },
              ],
            ),
          );
        },
      ),
    );
  });
  setUp(updates.clear);

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageHoliday())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Special holiday fixture'));
    await tester.pumpAndSettle();
  }

  for (final value in ['am_only', 'pm_only']) {
    testWidgets('description edit preserves $value special holiday coverage', (
      tester,
    ) async {
      coverage = value;
      await open(tester);
      expect(
        find.text(value == 'am_only' ? 'AM only' : 'PM only'),
        findsWidgets,
      );
      expect(find.byKey(ValueKey(value)), findsOneWidget);
      final description = find.widgetWithText(
        TextFormField,
        'Short description',
      );
      await tester.ensureVisible(description);
      await tester.enterText(description, 'Changed description only');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(updates.single['holiday_type'], 'special');
      expect(updates.single['coverage'], value);
      expect(updates.single['description'], 'Changed description only');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'switching between suspension and special preserves selected coverage',
    (tester) async {
      coverage = 'am_only';
      await open(tester);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('special')),
          )
          .onChanged!('work_suspension');
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('work_suspension')),
          )
          .onChanged!('special');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('am_only')), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(updates.single['coverage'], 'am_only');
    },
  );
}
