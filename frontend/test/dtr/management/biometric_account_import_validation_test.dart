import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

void main() {
  final imports = <Map<String, dynamic>>[];
  String? biometricId;

  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    imports.clear();
    biometricId = '1001';
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data = <dynamic>[];
          if (options.path == '/api/biometric-devices') {
            data = [
              {'id': 'clock', 'name': 'Test clock', 'vendor': 'zkteco'},
            ];
          } else if (options.path.endsWith('/users')) {
            data = [
              {
                'full_name': 'Imported Employee',
                'biometric_user_id': biometricId,
              },
            ];
          } else if (options.path.endsWith('/import-user')) {
            imports.add(Map<String, dynamic>.from(options.data as Map));
            data = {'id': 'imported-id'};
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

  Future<void> openImport(
    WidgetTester tester, {
    Size size = const Size(1400, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DtrProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManageEmployee(canCreateAccount: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Import as Inactive');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('invalid email and weak password show errors without importing', (
    tester,
  ) async {
    await openImport(tester);
    await tester.enterText(field('Admin Email for User'), 'invalid');
    await tester.enterText(field('Initial Password'), 'x');
    await tester.enterText(field('Confirm Password'), 'x');
    await submit(tester);
    expect(imports, isEmpty);
    expect(find.text('A valid email is required'), findsOneWidget);
    expect(
      find.textContaining('Password must be at least 12 characters'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank names and biometric IDs cannot be imported', (
    tester,
  ) async {
    biometricId = '  ';
    await openImport(tester);
    await tester.enterText(field('Full Name'), '  ');
    await tester.enterText(
      field('Admin Email for User'),
      'employee@example.gov.ph',
    );
    await tester.enterText(field('Initial Password'), 'StrongPass12!');
    await tester.enterText(field('Confirm Password'), 'StrongPass12!');
    await submit(tester);
    expect(imports, isEmpty);
    expect(find.text('Biometric User ID is required'), findsOneWidget);
    expect(find.text('Full name is required'), findsOneWidget);
  });

  testWidgets(
    'generated import password meets the account policy and confirmation matches',
    (tester) async {
      await openImport(tester);
      final password = tester
          .widget<TextFormField>(field('Initial Password'))
          .controller!
          .text;
      expect(password.length, greaterThanOrEqualTo(12));
      for (final pattern in [r'[a-z]', r'[A-Z]', r'\d', r'[^A-Za-z0-9]']) {
        expect(RegExp(pattern).hasMatch(password), isTrue);
      }
      expect(
        tester
            .widget<TextFormField>(field('Confirm Password'))
            .controller!
            .text,
        password,
      );
      await tester.enterText(
        field('Admin Email for User'),
        '  Employee@Example.Gov.Ph  ',
      );
      await tester.enterText(field('Full Name'), '  Imported Employee  ');
      await submit(tester);
      expect(imports, hasLength(1));
      expect(imports.single['email'], 'employee@example.gov.ph');
      expect(imports.single['full_name'], 'Imported Employee');
      expect(imports.single['biometric_user_id'], '1001');
      expect(imports.single['password'], password);
    },
  );

  testWidgets('confirmation mismatch blocks import with a valid password', (
    tester,
  ) async {
    await openImport(tester);
    await tester.enterText(
      field('Admin Email for User'),
      'employee@example.gov.ph',
    );
    await tester.enterText(field('Initial Password'), 'StrongPass12!');
    await tester.enterText(field('Confirm Password'), 'DifferentPass12!');
    await submit(tester);
    expect(imports, isEmpty);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('generated password can be revealed without changing it', (
    tester,
  ) async {
    await openImport(tester);
    final password = tester
        .widget<TextFormField>(field('Initial Password'))
        .controller!
        .text;
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.descendant(
        of: field('Initial Password'),
        matching: find.byType(TextField),
      ),
    );
    expect(input.obscureText, isFalse);
    expect(input.controller!.text, password);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: field('Initial Password'),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isTrue,
    );
    expect(imports, isEmpty);
  });
}
