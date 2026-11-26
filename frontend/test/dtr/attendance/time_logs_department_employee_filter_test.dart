import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/shared/pages/dtr_time_logs_content.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/widgets/searchable_dropdown_field.dart';

/// The Time Logs Employee filter must list only the selected department's
/// employees, whatever other screens load into the shared provider list.
void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  late DtrProvider dtr;
  var accountingDelay = Duration.zero;

  Map<String, dynamic> emp(String id, String name) => {
    'id': id,
    'full_name': name,
  };

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    addTearDown(dio.interceptors.clear);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          dynamic data = <dynamic>[];
          if (options.path == '/api/departments') {
            data = [
              {'id': 'acc', 'name': 'Accounting'},
              {'id': 'hr', 'name': 'HR Office'},
              {'id': 'rec', 'name': 'Records'},
            ];
          } else if (options.path == '/api/employees') {
            final dept = options.queryParameters['department_id'];
            if (dept == 'acc') {
              await Future<void>.delayed(accountingDelay);
              data = [emp('ana', 'Ana Reyes')];
            } else if (dept == 'hr') {
              data = [emp('ben', 'Ben Santos')];
            } else if (dept == 'rec') {
              data = <dynamic>[];
            } else {
              data = [
                emp('ana', 'Ana Reyes'),
                emp('ben', 'Ben Santos'),
                emp('carl', 'Carl Lim'),
              ];
            }
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(id: 'admin', email: 'admin@test.local', role: 'admin'),
      );
    dtr = DtrProvider();
    addTearDown(auth.dispose);
    addTearDown(dtr.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider<DtrProvider>.value(value: dtr),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DtrTimeLogsContent()),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pickDepartment(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButton<String?>).first);
    // The page has a live clock, so pumpAndSettle would never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text(name).last);
  }

  List<String> employeeOptions(WidgetTester tester) => tester
      .widget<SearchableDropdownField>(find.byType(SearchableDropdownField))
      .options;

  setUp(() => accountingDelay = Duration.zero);

  testWidgets('other screens reloading all employees do not leak in', (
    tester,
  ) async {
    await open(tester);
    await pickDepartment(tester, 'Accounting');
    await settle(tester);
    expect(employeeOptions(tester), ['Ana Reyes']);

    // e.g. the Employees page or Add entry dialog reloads everyone.
    unawaited(dtr.loadEmployees(forceRefresh: true));
    await settle(tester);
    expect(dtr.employees, hasLength(3));
    expect(employeeOptions(tester), ['Ana Reyes']);
  });

  testWidgets('a slow response for an older department is ignored', (
    tester,
  ) async {
    await open(tester);
    accountingDelay = const Duration(seconds: 3);
    await pickDepartment(tester, 'Accounting');
    await tester.pump();
    await pickDepartment(tester, 'HR Office');
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(employeeOptions(tester), ['Ben Santos']);
  });

  testWidgets('an empty department explains why the list is empty', (
    tester,
  ) async {
    await open(tester);
    await pickDepartment(tester, 'Records');
    await settle(tester);
    expect(employeeOptions(tester), isEmpty);
    expect(
      find.text('No employees in this department on the selected date.'),
      findsOneWidget,
    );
  });
}
