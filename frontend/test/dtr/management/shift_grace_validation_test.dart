import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/shifts/pages/manage_shift.dart';

void main() {
  final mutations = <RequestOptions>[];
  var locked = false;
  const saved = {
    'id': 'saved-shift',
    'name': 'Saved shift',
    'start_time': '08:00',
    'end_time': '12:00',
    'punch_mode': 'am_only',
    'grace_period_minutes': 15,
    'working_days': [1, 2, 3, 4, 5],
    'is_active': true,
  };

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET' && options.path == '/api/shifts') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [
                  {...saved, 'schedule_edit_locked': locked},
                ],
              ),
            );
          } else if (options.method == 'POST' || options.method == 'PUT') {
            mutations.add(options);
            handler.resolve(
              Response<Map<String, dynamic>>(requestOptions: options, data: {}),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
  });

  setUp(() {
    mutations.clear();
    locked = false;
  });

  Finder graceField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == '0',
  );

  Future<void> setTime(WidgetTester tester, int index, TimeOfDay time) async {
    final picker = find
        .byWidgetPredicate(
          (widget) =>
              widget is InputDecorator && widget.decoration.hintText == 'HH:MM',
        )
        .at(index);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(TimePickerDialog))).pop(time);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    required bool editing,
    double width = 1440,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageShift())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(editing ? 'Saved shift' : 'Add Shift'));
    await tester.pumpAndSettle();
    if (!editing) {
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Shift Name',
        ),
        'New shift',
      );
      tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .firstWhere(
            (widget) => widget.items!.any((item) => item.value == 'am_only'),
          )
          .onChanged!('am_only');
      await tester.pumpAndSettle();
      await setTime(tester, 0, const TimeOfDay(hour: 8, minute: 0));
      await setTime(tester, 1, const TimeOfDay(hour: 12, minute: 0));
    }
    await tester.ensureVisible(graceField());
  }

  Future<void> submit(WidgetTester tester, bool editing) async {
    await tester.tap(find.text(editing ? 'Update' : 'Add Shift').last);
    await tester.pumpAndSettle();
  }

  for (final editing in [false, true]) {
    final mode = editing ? 'update' : 'create';
    testWidgets(
      '$mode blocks invalid grace text with a field error and no API mutation',
      (tester) async {
        await open(tester, editing: editing);
        for (final text in [
          'abc',
          '1.5',
          '-1',
          '241',
          '1e2',
          '0x10',
          '999999999999999999999999',
        ]) {
          await tester.enterText(graceField(), text);
          await submit(tester, editing);
          expect(mutations, isEmpty, reason: 'Invalid grace input: $text');
          expect(
            find.text('Enter a whole number from 0 to 240.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    for (final text in ['', '  ', '0', '15', '240', ' 15 ']) {
      testWidgets(
        '$mode preserves valid grace minutes ${text.isEmpty ? '(blank)' : text}',
        (tester) async {
          await open(tester, editing: editing);
          await tester.enterText(graceField(), text);
          await submit(tester, editing);
          expect(mutations, hasLength(1));
          expect(mutations.single.method, editing ? 'PUT' : 'POST');
          expect(
            mutations.single.data['grace_period_minutes'],
            text.trim().isEmpty ? 0 : int.parse(text.trim()),
          );
          expect(mutations.single.data['working_days'], [1, 2, 3, 4, 5]);
          expect(mutations.single.data['punch_mode'], 'am_only');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$mode permits correcting an invalid grace value before saving',
      (tester) async {
        await open(tester, editing: editing);
        await tester.enterText(graceField(), '1.5');
        await submit(tester, editing);
        expect(mutations, isEmpty);
        await tester.enterText(graceField(), '15');
        await tester.pumpAndSettle();
        expect(find.text('Enter a whole number from 0 to 240.'), findsNothing);
        await submit(tester, editing);
        expect(mutations, hasLength(1));
        expect(mutations.single.data['grace_period_minutes'], 15);
      },
    );
  }

  testWidgets(
    'locked historical shift keeps grace disabled and preserves it on rename',
    (tester) async {
      locked = true;
      await open(tester, editing: true);
      expect(tester.widget<TextField>(graceField()).enabled, false);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Shift Name',
        ),
        'Renamed shift',
      );
      await submit(tester, true);
      expect(mutations, hasLength(1));
      expect(mutations.single.data['grace_period_minutes'], 15);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile shift editor shows grace errors without overflow', (
    tester,
  ) async {
    await open(tester, editing: true, width: 390);
    await tester.enterText(graceField(), 'abc');
    await submit(tester, true);
    expect(mutations, isEmpty);
    expect(find.text('Enter a whole number from 0 to 240.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
