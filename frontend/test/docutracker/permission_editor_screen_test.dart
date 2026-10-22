import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_permission_editor_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

void main() {
  var apiInitialized = false;
  Map<String, dynamic>? savedPayload;
  var failSave = false;
  List<dynamic> routingConfigs = const [];
  var extraEmployees = 0;
  final savedPayloads = <Map<String, dynamic>>[];
  Map<String, dynamic>? auditQuery;

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
              action: userId == 'u-hr' && action == 'view'
                  ? {
                      'granted': true,
                      'source': 'explicit_permission',
                      'matched_scope': 'user',
                      'matched_document_type': '*',
                    }
                  : {'granted': false, 'source': 'fallback_rule'},
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
                    for (var i = 1; i <= extraEmployees; i++)
                      {
                        'id': 'u-staff-$i',
                        'full_name':
                            'Staff ${i.toString().padLeft(2, '0')} Member',
                        'role': 'employee',
                        'current_department_name': i.isEven
                            ? 'Engineering'
                            : 'Treasury',
                        'current_position_name': 'Clerk',
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
                  data: routingConfigs,
                ),
              );
              return;
            }
            if (options.path == '/api/docutracker/permission-records') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    for (final action in ['view', 'submit'])
                      {
                        'id': 'p-$action',
                        'role_id': null,
                        'user_id': 'u-hr',
                        'document_type': '*',
                        'action': action,
                        'granted': true,
                      },
                  ],
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
              savedPayloads.add(savedPayload!);
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
            if (options.path == '/api/docutracker/governance-audit') {
              auditQuery = Map<String, dynamic>.from(options.queryParameters);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <dynamic>[],
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
    savedPayloads.clear();
    auditQuery = null;
    failSave = false;
    extraEmployees = 0;
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
      ChangeNotifierProvider(
        create: (_) => DocuTrackerProvider(),
        child: MaterialApp(
          home: DocuTrackerPermissionEditorScreen(
            initialTabIsUserOverride: userView,
            initialDocumentType: documentType,
            initialUserId: userId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool roleSwitchValue(WidgetTester tester, String role, String action) =>
      tester
          .widget<Switch>(
            find.descendant(
              of: find.byKey(ValueKey('permission-role-$role-$action')),
              matching: find.byType(Switch),
            ),
          )
          .value;

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

  testWidgets('tabs show real role and employee exception counts', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('System Access & Permissions'), findsOneWidget);
    final tabs = find.byKey(const ValueKey('system-access-view-selector'));
    expect(find.descendant(of: tabs, matching: find.text('4')), findsOneWidget);
    // Two user rows for the same employee count as one exception.
    expect(find.descendant(of: tabs, matching: find.text('1')), findsOneWidget);
    expect(find.text('Hierarchy notice'), findsOneWidget);
    // Includes Release, which administrators do not inherit.
    expect(find.text('Restricted'), findsNWidgets(5));
  });

  testWidgets('renders in dark mode without layout errors', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DocuTrackerProvider(),
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const DocuTrackerPermissionEditorScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('System Access & Permissions'), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-role-hr')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role dropdown groups and filters the real roles', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('permission-role-selector')));
    await tester.pumpAndSettle();

    expect(find.text('STANDARD ROLES'), findsOneWidget);
    expect(find.text('ADMINISTRATIVE ROLES'), findsOneWidget);
    for (final role in ['hr', 'supervisor', 'employee', 'admin']) {
      expect(
        find.byKey(ValueKey('permission-role-option-$role')),
        findsOneWidget,
      );
    }

    await tester.enterText(
      find.byKey(const ValueKey('permission-role-search')),
      'department',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('permission-role-option-supervisor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('permission-role-option-hr')),
      findsNothing,
    );
    expect(find.text('ADMINISTRATIVE ROLES'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('document scope hides source-module types like DTR', (
    tester,
  ) async {
    routingConfigs = [
      for (final type in ['dtr', 'ld', 'rsp', 'travel_order'])
        {
          'document_type': type,
          'workflow_version': 1,
          'is_published': true,
          'steps': const <dynamic>[],
        },
    ];
    addTearDown(() => routingConfigs = const []);
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('permission-document-type-*')));
    await tester.pumpAndSettle();
    expect(find.text('Travel Order'), findsWidgets);
    expect(find.text('Dtr'), findsNothing);
    expect(find.text('Ld'), findsNothing);
    expect(find.text('Rsp'), findsNothing);
    expect(find.text('DTR'), findsNothing);
    expect(find.text('Memo').hitTestable(), findsWidgets);
  });

  testWidgets('discard restores the saved values without a request', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('permission-role-hr-view')));
    await tester.pump();
    expect(roleSwitchValue(tester, 'hr', 'view'), isTrue);

    await tester.tap(find.byKey(const ValueKey('permission-discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(roleSwitchValue(tester, 'hr', 'view'), isFalse);
    expect(find.byKey(const ValueKey('permission-discard')), findsNothing);
    expect(savedPayload, isNull);
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

  testWidgets('employee list paginates and filters by department and role', (
    tester,
  ) async {
    extraEmployees = 23;
    await pumpEditor(tester, userView: true, height: 2400);

    final label = find.byKey(const ValueKey('permission-employee-page-label'));
    expect(tester.widget<Text>(label).data, 'Showing 1–10 of 25');
    await tester.tap(find.byKey(const ValueKey('permission-employee-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, 'Showing 11–20 of 25');
    await tester.tap(find.byKey(const ValueKey('permission-employee-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, 'Showing 21–25 of 25');
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('permission-employee-next')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('permission-filter-role-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, 'Showing 1–1 of 1');
    expect(find.text('Beatriz Reviewer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('permission-filter-role-hr')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All roles').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('permission-filter-department-null')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Engineering').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, 'Showing 1–10 of 11');

    await tester.tap(
      find.byKey(const ValueKey('permission-filter-exceptions')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(label).data, 'No results');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk assignment saves exceptions for every selected employee', (
    tester,
  ) async {
    extraEmployees = 3;
    await pumpEditor(tester, userView: true, documentType: 'purchaseRequest');

    for (final id in ['u-staff-1', 'u-staff-2']) {
      await tester.tap(find.byKey(ValueKey('permission-employee-check-$id')));
      await tester.pump();
    }
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('permission-bulk-assign')));
    await tester.pumpAndSettle();

    Future<void> choose(String action, String option) async {
      await tester.tap(find.byKey(ValueKey('permission-bulk-$action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await choose('submit', 'Allow');
    await choose('create_draft', 'Block');
    expect(
      find.byKey(const ValueKey('permission-warning-submit-without-create')),
      findsOneWidget,
    );
    await choose('create_draft', 'Allow');
    expect(
      find.byKey(const ValueKey('permission-warning-submit-without-create')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('permission-bulk-apply')));
    await tester.pumpAndSettle();

    expect(savedPayloads, hasLength(1));
    expect(savedPayloads.single['document_type'], 'purchaseRequest');
    final changes = (savedPayloads.single['changes'] as List).cast<Map>();
    expect(changes, hasLength(4));
    expect(changes.map((change) => change['user_id']).toSet(), {
      'u-staff-1',
      'u-staff-2',
    });
    expect(changes.every((change) => change['granted'] == true), isTrue);
    expect(changes.map((change) => change['action']).toSet(), {
      'submit',
      'create_draft',
    });
    expect(find.text('Access updated for 2 employees.'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('employee view shows server effective access and its source', (
    tester,
  ) async {
    await pumpEditor(tester, userView: true, userId: 'u-hr');

    expect(
      find.text('Effective: Allowed · Employee exception · All document types'),
      findsOneWidget,
    );
    expect(
      find.text('Effective: Blocked · No rule · blocked by default'),
      findsNWidgets(3),
    );
  });

  testWidgets('history opens the audit log scoped to the employee', (
    tester,
  ) async {
    await pumpEditor(tester, userView: true, userId: 'u-hr');
    await tester.tap(find.byKey(const ValueKey('permission-user-history')));
    await tester.pumpAndSettle();

    expect(find.text('History for Beatriz Reviewer'), findsOneWidget);
    expect(auditQuery?['target_user_id'], 'u-hr');
    expect(auditQuery?['event_type'], contains('permission_saved'));
  });

  testWidgets('role view warns about conflicting create and submit access', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(
      find.byKey(const ValueKey('permission-warning-create-without-submit')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('permission-role-hr-create_draft')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('permission-warning-create-without-submit')),
      findsOneWidget,
    );
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
    await tester.tap(
      find.byKey(const ValueKey('permission-role-option-employee')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission-role-menu')), findsNothing);
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
    expect(roleSwitchValue(tester, 'hr', 'view'), isFalse);
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
          'These roles return to the system default policy for all document '
          'types. Document-specific settings and employee exceptions stay in '
          'place.',
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
        'These roles return to the system default policy for this document type',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove settings'));
    await tester.pumpAndSettle();
    expect(savedPayload?['document_type'], 'memo');
    final changes = (savedPayload!['changes'] as List).cast<Map>();
    expect(changes, hasLength(15));
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
      expect(roleSwitchValue(tester, 'hr', 'view'), isTrue);
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('permission-role-hr-view')),
      );
      await tester.pumpAndSettle();
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
