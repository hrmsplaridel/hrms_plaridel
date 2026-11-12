import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';

class _Auth extends AuthProvider {
  @override
  AppUser get user =>
      AppUser(id: 'actor', email: 'actor@example.test', role: 'admin');
}

void main() {
  final creations = <Map<String, dynamic>>[];
  var completed = 0;
  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    creations.clear();
    completed = 0;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data = <dynamic>[];
          if (options.path == '/api/employees' && options.method == 'POST') {
            creations.add(Map<String, dynamic>.from(options.data as Map));
            data = {
              'id': 'created-id',
              'account_email_sent': true,
              'account_email_configured': true,
            };
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Finder field(String label) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    ),
    matching: find.byType(TextFormField),
  );

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
          ChangeNotifierProvider(create: (_) => RecruitmentHirePrefill()),
          ChangeNotifierProvider(create: (_) => DtrProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AddEmployeeForm(onAccountCreated: () => completed++),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('Email'), 'employee@example.gov.ph');
    await tester.enterText(field('First name'), 'Test');
    await tester.enterText(field('Last name'), 'Employee');
    Future<void> select(String label, String option) async {
      final dropdown = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == label,
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await select('Role', 'Employee');
    await select('Sex', 'Male');
    final hireDate = find.byWidgetPredicate(
      (widget) =>
          widget is InputDecorator &&
          widget.decoration.labelText == 'Date hired',
    );
    await tester.ensureVisible(hireDate);
    await tester.tap(hireDate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'malformed emails are rejected in the form before account creation',
    (tester) async {
      await openForm(tester);
      for (final email in [
        'invalid',
        'a b@example.test',
        'a@@example.test',
        '${'a' * 245}@example.test',
        '  ',
      ]) {
        await tester.enterText(field('Email'), email);
        await submit(tester);
        expect(find.text('A valid email is required'), findsOneWidget);
        expect(creations, isEmpty);
        expect(completed, 0);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid optional contacts are rejected before account creation',
    (tester) async {
      await openForm(tester);
      for (final phone in [
        'abc',
        '12345',
        '+19171234567',
        'call 09171234567',
        '0917/123/4567',
        '++639171234567',
      ]) {
        await tester.enterText(field('Contact number'), phone);
        await submit(tester);
        expect(
          find.text('Contact number must be a valid Philippine mobile number'),
          findsOneWidget,
        );
        expect(creations, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supported SMS formats validate and a formatted contact can be submitted',
    (tester) async {
      await openForm(tester);
      for (final phone in [
        '09171234567',
        '9171234567',
        '639171234567',
        '+639171234567',
        '00639171234567',
        '0917 123 4567',
        '+63 (917) 123-4567',
        '0917.123.4567',
      ]) {
        await tester.enterText(field('Contact number'), phone);
        expect(
          tester
              .state<FormFieldState<String>>(field('Contact number'))
              .validate(),
          isTrue,
        );
      }
      await tester.enterText(field('Contact number'), ' +63 (917) 123-4567 ');
      await tester.enterText(field('Email'), ' employee+hr@example.gov.ph ');
      await submit(tester);
      expect(creations, hasLength(1));
      expect(creations.single['contact_number'], '+63 (917) 123-4567');
      expect(creations.single['email'], 'employee+hr@example.gov.ph');
      expect(completed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contact number can be omitted when creating an account', (
    tester,
  ) async {
    await openForm(tester);
    await submit(tester);
    expect(creations, hasLength(1));
    expect(creations.single.containsKey('contact_number'), isFalse);
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });
}
