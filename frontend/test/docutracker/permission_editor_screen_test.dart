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
  var failSave = false;

  Map<String, dynamic> policy({String? userId, String documentType = '*'}) => {
    'document_type': documentType,
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
                    documentType:
                        options.queryParameters['document_type']?.toString() ??
                        '*',
                  ),
                ),
              );
              return;
            }
            if (options.path == '/api/docutracker/permission-policy' &&
                options.method == 'PUT') {
              savedPayload = Map<String, dynamic>.from(options.data as Map);
              if (failSave) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                    message: 'Connection failed',
                  ),
                );
                return;
              }
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

  setUp(() {
    savedPayload = null;
    failSave = false;
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    double width = 1440,
    bool userView = false,
    String? documentType,
    String? userId,
    double height = 1400,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DocuTrackerPermissionEditorScreen(
          initialTabIsUserOverride: userView,
          initialDocumentType: documentType,
          initialUserId: userId,
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
    expect(find.text('Role access'), findsOneWidget);
    expect(find.text('Employee exceptions'), findsOneWidget);
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
    // Switching roles must retain edits until the shared Save is pressed.
    await tester.tap(find.byKey(const ValueKey('permission-role-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employee').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission-role-hr-view')), findsNothing);
    expect(
      find.byKey(const ValueKey('permission-role-employee-view')),
      findsOneWidget,
    );
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

  testWidgets('review and undo removes only the selected change from saving', (
    tester,
  ) async {
    await pumpEditor(tester);
    for (final action in ['view', 'download']) {
      await tester.tap(find.byKey(ValueKey('permission-role-hr-$action')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('permission-review')));
    await tester.pumpAndSettle();
    expect(find.text('HR · All document types'), findsNWidgets(2));
    expect(find.text('Blocked → Allowed'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('permission-undo-hr-view')));
    await tester.pumpAndSettle();
    expect(find.text('Blocked → Allowed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('permission-role-hr-view')),
          )
          .value,
      false,
    );
    await tester.tap(find.byKey(const ValueKey('permission-save')));
    await tester.pumpAndSettle();
    expect(savedPayload?['changes'], [
      {'role_id': 'hr', 'action': 'download', 'granted': true},
    ]);
  });

  testWidgets(
    'employee review names the employee and undo restores inheritance',
    (tester) async {
      await pumpEditor(tester, userView: true, userId: 'u-hr');
      await tester.tap(
        find.byKey(
          const ValueKey(
            'permission-user-decision-view-_EmployeeDecision.inherit',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('permission-review')));
      await tester.pumpAndSettle();
      expect(
        find.text('Beatriz Reviewer · All document types'),
        findsOneWidget,
      );
      expect(find.text('Use role default → Allowed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('permission-undo-u-hr-view')));
      await tester.pumpAndSettle();
      expect(find.text('No pending changes.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('permission-save')))
            .onPressed,
        isNull,
      );
      expect(savedPayload, isNull);
    },
  );

  testWidgets(
    'removal names all affected roles and cancels without a request',
    (tester) async {
      await pumpEditor(tester, width: 360, height: 800);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove custom role settings'));
      await tester.pumpAndSettle();
      expect(find.text('Roles: HR, Supervisor, Employee'), findsOneWidget);
      expect(find.text('Document type: All document types'), findsOneWidget);
      expect(
        find.textContaining(
          'Document-specific settings and employee exceptions stay in place.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(savedPayload, isNull);
    },
  );

  testWidgets('removal uses the displayed document scope in one request', (
    tester,
  ) async {
    await pumpEditor(tester, documentType: 'memo');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove custom role settings'));
    await tester.pumpAndSettle();
    expect(find.text('Document type: Memo'), findsOneWidget);
    expect(
      find.textContaining(
        'These roles will use their All document types settings.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove settings'));
    await tester.pumpAndSettle();
    expect(savedPayload?['document_type'], 'memo');
    final changes = (savedPayload!['changes'] as List).cast<Map>();
    expect(changes, hasLength(12));
    expect(changes.map((change) => change['role_id']).toSet(), {
      'hr',
      'supervisor',
      'employee',
    });
    expect(changes.every((change) => change['granted'] == null), isTrue);
  });

  testWidgets(
    'failed save preserves changes and prevents removal over unsaved edits',
    (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('permission-role-hr-view')));
      await tester.pump();
      failSave = true;
      await tester.tap(find.byKey(const ValueKey('permission-save')));
      await tester.pumpAndSettle();
      expect(find.text('1 unsaved change'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('permission-role-hr-view')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Save or undo pending changes first.'), findsOneWidget);
      final item = find.ancestor(
        of: find.text('Remove custom role settings'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(tester.widget<PopupMenuItem<String>>(item).enabled, isFalse);
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('layout remains reachable at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpEditor(tester, width: width, height: 800);
      expect(find.text('System Access'), findsOneWidget);
      expect(find.byKey(const ValueKey('permission-save')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('permission-role-hr-view')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('permission-review')));
      await tester.pumpAndSettle();
      expect(find.text('Blocked → Allowed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('permission-undo-hr-view')));
      await tester.pumpAndSettle();
      expect(find.text('No pending changes.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
