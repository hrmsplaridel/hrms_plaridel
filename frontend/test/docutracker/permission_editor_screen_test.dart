import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_permission_editor_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  var apiInitialized = false;
  Map<String, dynamic>? savedPayload;

  Map<String, dynamic> policy({String? userId}) => {
    'document_type': '*',
    'actions': ['view', 'create_draft', 'download', 'submit'],
    'role_defaults': [
      for (final role in ['admin', 'hr', 'supervisor', 'employee'])
        {
          'role_id': role,
          'permissions': {
            for (final action in ['view', 'create_draft', 'download', 'submit'])
              action: {
                'granted': role == 'admin',
                'source': role == 'admin' ? 'administrator' : 'not_configured',
              },
          },
        },
    ],
    'selected_user': userId == null
        ? null
        : {
            'id': userId,
            'full_name': userId == 'u-hr' ? 'Beatriz Reviewer' : 'Alice Admin',
            'role': userId == 'u-hr' ? 'hr' : 'admin',
            'is_active': true,
          },
    'user_overrides': userId == null
        ? null
        : {
            'view': null,
            'create_draft': null,
            'download': null,
            'submit': null,
          },
    'inherited_user_overrides': userId == null
        ? null
        : {
            'view': null,
            'create_draft': null,
            'download': null,
            'submit': null,
          },
    'effective': userId == null
        ? null
        : {
            for (final action in ['view', 'create_draft', 'download', 'submit'])
              action: {'granted': false, 'source': 'fallback_rule'},
          },
    'updated_at': '2026-09-14T13:00:00.000Z',
  };

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
                      'current_position_name': 'System Administrator',
                    },
                    {
                      'id': 'u-hr',
                      'full_name': 'Beatriz Reviewer',
                      'role': 'hr',
                      'current_department_name': 'HR',
                      'current_position_name': 'HR Officer',
                    },
                  ],
                ),
              );
              return;
            }
            if (options.path == '/api/docutracker/routing-configs') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <dynamic>[],
                ),
              );
              return;
            }
            if (options.path == '/api/docutracker/permission-policy' &&
                options.method == 'GET') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: policy(
                    userId: options.queryParameters['user_id']?.toString(),
                  ),
                ),
              );
              return;
            }
            if (options.path == '/api/docutracker/permission-policy' &&
                options.method == 'PUT') {
              savedPayload = Map<String, dynamic>.from(options.data as Map);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'updated': 1,
                    'updated_at': '2026-09-14T13:05:00.000Z',
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

  setUp(() => savedPayload = null);

  Future<void> pumpEditor(
    WidgetTester tester, {
    double width = 1440,
    bool userView = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DocuTrackerPermissionEditorScreen(
          initialTabIsUserOverride: userView,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows two clear access views without governance clutter', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('System Access'), findsOneWidget);
    expect(find.text('Role Defaults'), findsWidgets);
    expect(find.text('Employee Exceptions'), findsOneWidget);
    expect(find.text('Effective Preview'), findsNothing);
    expect(find.text('Security Insight'), findsNothing);
    expect(find.textContaining('Add custom role'), findsNothing);
    expect(find.textContaining('Saved 2026-09-14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee search includes department, position, and role', (
    tester,
  ) async {
    await pumpEditor(tester, userView: true);

    final search = find.byKey(const ValueKey('permission-employee-search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, 'officer');
    await tester.pumpAndSettle();

    expect(find.text('Beatriz Reviewer'), findsOneWidget);
    expect(find.textContaining('HR Officer'), findsOneWidget);
    await tester.tap(find.text('Beatriz Reviewer'));
    await tester.pumpAndSettle();

    expect(find.text('Open related documents'), findsOneWidget);
    expect(find.text('Create document drafts'), findsOneWidget);
    expect(find.text('Submit own drafts'), findsOneWidget);
    expect(find.text('Download attachments'), findsOneWidget);
    expect(find.text('Use role default'), findsWidgets);
    expect(find.textContaining('Workflow-controlled actions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role changes are sent through one atomic bulk save', (
    tester,
  ) async {
    await pumpEditor(tester);

    final tile = find.byKey(const ValueKey('permission-role-hr-view'));
    expect(tile, findsOneWidget);
    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pump();

    expect(find.text('1 unsaved change'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('permission-save')));
    await tester.pumpAndSettle();

    expect(savedPayload?['document_type'], '*');
    final changes = savedPayload?['changes'] as List<dynamic>?;
    expect(changes, hasLength(1));
    expect((changes!.single as Map)['role_id'], 'hr');
    expect((changes.single as Map)['action'], 'view');
    expect((changes.single as Map)['granted'], true);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('layout remains reachable at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpEditor(tester, width: width);
      expect(find.text('System Access'), findsOneWidget);
      expect(find.byKey(const ValueKey('permission-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
