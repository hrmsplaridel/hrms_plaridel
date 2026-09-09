import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_permission_editor_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  var apiInitialized = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'HRMS Plaridel',
      packageName: 'hrms_plaridel',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    if (!apiInitialized) {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/api/employees') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'id': 'u-admin',
                      'full_name': 'Alice Admin',
                      'role': 'admin',
                      'current_department_name': 'Admin Office',
                    },
                    {
                      'id': 'u-hr',
                      'full_name': 'Beatriz Reviewer',
                      'role': 'hr_staff',
                      'current_department_name': 'HR',
                    },
                    {
                      'id': 'u-emp',
                      'full_name': 'Carlo Employee',
                      'role': 'employee',
                      'current_department_name': 'Accounting',
                    },
                  ],
                ),
              );
              return;
            }

            if (options.path.startsWith('/api/employees/')) {
              final userId = options.path.replaceFirst('/api/employees/', '');
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': userId,
                    'full_name': userId == 'u-hr'
                        ? 'Beatriz Reviewer'
                        : 'Unknown User',
                    'current_department_name': userId == 'u-hr'
                        ? 'HR'
                        : 'Unknown',
                  },
                ),
              );
              return;
            }

            if (options.path == '/api/docutracker/permission-records') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const [],
                ),
              );
              return;
            }

            if (options.path == '/api/docutracker/permission-explain') {
              final action =
                  (options.queryParameters['action']?.toString() ?? '').trim();
              final granted =
                  action == 'view' ||
                  action == 'create_draft' ||
                  action == 'download';
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'final_decision': granted,
                    'reason': granted ? 'mock_allow' : 'mock_deny',
                    'relationship': {
                      'isCurrentHolder': false,
                      'isStepAssignee': false,
                    },
                  },
                ),
              );
              return;
            }

            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: const <String, dynamic>{},
              ),
            );
          },
        ),
      );
      apiInitialized = true;
    }
  });

  Future<void> pumpEditor(WidgetTester tester, {bool userTab = false}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 2200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DocuTrackerPermissionEditorScreen(
          initialTabIsUserOverride: userTab,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders 3 permission tabs and effective preview guidance', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('Role Governance'), findsOneWidget);
    expect(find.text('User Override'), findsOneWidget);
    expect(find.text('Effective Preview'), findsOneWidget);

    await tester.tap(find.text('Effective Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Rules reference'), findsOneWidget);
    expect(
      find.textContaining('Workflow actions are enforced'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('user search keeps selected employee visible in dropdown', (
    tester,
  ) async {
    await pumpEditor(tester, userTab: true);

    final searchField = find.widgetWithText(
      TextField,
      'Search user (name, department, id)',
    );
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'beatriz');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice Admin'), findsWidgets);
    expect(find.textContaining('Beatriz Reviewer'), findsWidgets);

    await tester.tap(find.textContaining('Beatriz Reviewer').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Effective Preview'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Beatriz Reviewer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
