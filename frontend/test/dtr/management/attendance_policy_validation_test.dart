import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/attendance_policies/pages/manage_attendance_policy.dart';

void main() {
  final mutations = <RequestOptions>[];
  var used = false;
  const hoursKey = Key('attendance-policy-work-hours');
  const multiplierKey = Key('attendance-policy-deduction-multiplier');
  const hoursError = 'Enter a number greater than 0 and at most 24.';
  const multiplierError = 'Enter a number greater than 0 and at most 999.999.';

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET' &&
              options.path == '/api/attendance-policies') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [
                  {
                    'id': 'saved-policy',
                    'policy_name': 'Saved policy',
                    'work_hours_per_day': 8,
                    'deduction_multiplier': 1,
                    'is_used': used,
                    'is_active': true,
                    'deduct_late': false,
                  },
                ],
              ),
            );
          } else if (options.path == '/api/shifts') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [
                  {
                    'id': 'am-shift',
                    'name': 'AM shift',
                    'punch_mode': 'am_only',
                    'start_time': '08:00',
                    'end_time': '12:00',
                  },
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
    used = false;
  });

  Finder field(Key key) => find.byKey(key);

  Future<void> enter(WidgetTester tester, Key key, String text) async {
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), text);
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
      const MaterialApp(home: Scaffold(body: ManageAttendancePolicy())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(editing ? 'Saved policy' : 'Add Policy'));
    await tester.pumpAndSettle();
    if (!editing) {
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == 'Name',
        ),
        'New policy',
      );
    }
  }

  Future<void> submit(WidgetTester tester, bool editing) async {
    await tester.tap(find.text(editing ? 'Update' : 'Add Policy').last);
    await tester.pumpAndSettle();
  }

  for (final editing in [false, true]) {
    final mode = editing ? 'update' : 'create';
    for (final key in [hoursKey, multiplierKey]) {
      testWidgets(
        '$mode blocks invalid $key at the field before any API mutation',
        (tester) async {
          await open(tester, editing: editing);
          final error = key == hoursKey ? hoursError : multiplierError;
          final upper = key == hoursKey ? '25' : '1000';
          for (final input in [
            upper,
            '',
            'abc',
            '0',
            '-1',
            'NaN',
            'Infinity',
            '-Infinity',
            '1e309',
          ]) {
            await enter(tester, key, input);
            await submit(tester, editing);
            expect(mutations, isEmpty, reason: 'Invalid value: $input');
            expect(
              tester.state<FormFieldState<String>>(field(key)).errorText,
              error,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }

    for (final values in [
      ['8', '1'],
      ['24', '999.999'],
      ['0.25', '0.125'],
      [' 7.5 ', ' 1.25 '],
      ['1e1', '2e0'],
    ]) {
      testWidgets('$mode preserves valid policy numbers $values', (
        tester,
      ) async {
        await open(tester, editing: editing);
        await enter(tester, hoursKey, values[0]);
        await enter(tester, multiplierKey, values[1]);
        await submit(tester, editing);
        expect(mutations, hasLength(1));
        expect(mutations.single.method, editing ? 'PUT' : 'POST');
        expect(
          mutations.single.data['work_hours_per_day'],
          double.parse(values[0]),
        );
        expect(
          mutations.single.data['deduction_multiplier'],
          double.parse(values[1]),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      '$mode clears errors after correction and submits the corrected numbers',
      (tester) async {
        await open(tester, editing: editing);
        await enter(tester, hoursKey, '25');
        await enter(tester, multiplierKey, '1000');
        await submit(tester, editing);
        expect(mutations, isEmpty);
        expect(
          tester.state<FormFieldState<String>>(field(hoursKey)).errorText,
          hoursError,
        );
        expect(
          tester.state<FormFieldState<String>>(field(multiplierKey)).errorText,
          multiplierError,
        );
        await enter(tester, hoursKey, '8');
        await enter(tester, multiplierKey, '1.25');
        expect(
          tester.state<FormFieldState<String>>(field(hoursKey)).errorText,
          isNull,
        );
        expect(
          tester.state<FormFieldState<String>>(field(multiplierKey)).errorText,
          isNull,
        );
        await submit(tester, editing);
        expect(mutations, hasLength(1));
        expect(mutations.single.data['deduction_multiplier'], 1.25);
      },
    );
  }

  testWidgets(
    'used-policy computation locks and valid metadata editing remain supported',
    (tester) async {
      used = true;
      await open(tester, editing: true);
      expect(tester.widget<TextFormField>(field(hoursKey)).enabled, false);
      expect(tester.widget<TextFormField>(field(multiplierKey)).enabled, false);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == 'Name',
        ),
        'Renamed policy',
      );
      await submit(tester, true);
      expect(mutations, hasLength(1));
      expect(mutations.single.data['work_hours_per_day'], 8);
      expect(mutations.single.data['deduction_multiplier'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile policy editor displays numeric errors without overflow', (
    tester,
  ) async {
    await open(tester, editing: true, width: 390);
    await enter(tester, multiplierKey, '1000');
    await submit(tester, true);
    expect(mutations, isEmpty);
    expect(find.text(multiplierError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
