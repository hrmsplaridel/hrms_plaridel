import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/approvals_signatories_page.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/workflow_reviewer_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  var backups = <Map<String, dynamic>>[];
  var periods = <Map<String, dynamic>>[];
  var failDepartments = false;
  Completer<void>? backupSaveGate;
  setUp(() {
    ApiClient.instance.init();
    requests.clear();
    backups = [];
    periods = [];
    failDepartments = false;
    backupSaveGate = null;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          if (failDepartments && options.path == '/api/departments') {
            handler.reject(DioException(requestOptions: options));
            return;
          }
          dynamic data;
          switch (options.path) {
            case '/api/approval-workflows':
              data = [
                {
                  'id': 'workflow',
                  'name': 'Shared workflow',
                  'current_version': 1,
                  'steps': ['department', 'hr'],
                  'is_active': true,
                },
              ];
            case '/api/departments':
              data = [
                {'id': 'department', 'name': 'Human Resources'},
              ];
            case '/api/employees':
              data = [];
            case '/api/docutracker/hr-workflow-mirrors':
              data = {
                'workflows': [
                  {
                    'key': 'leave',
                    'steps': [
                      {
                        'groups': [
                          {
                            'scope_id': 'department',
                            'primary': {'name': 'Department Primary'},
                          },
                        ],
                      },
                      {
                        'groups': [
                          {
                            'scope_id': null,
                            'primary': {'name': 'Final Primary'},
                          },
                        ],
                      },
                    ],
                  },
                ],
              };
            case '/api/docutracker/official-signatories':
              data = {'items': periods};
            case '/api/departments/department/reviewer-config':
              data = {
                'effective_date': '2026-09-30',
                'primary': {
                  'reviewerId': 'head',
                  'reviewerName': 'Department Primary',
                },
                'backups': backups,
                'eligible_employees': [
                  {
                    'id': 'head',
                    'name': 'Department Primary',
                    'position_title': 'Shared Title',
                  },
                  {
                    'id': 'backup',
                    'name': 'Backup Employee',
                    'position_title': 'Shared Title',
                  },
                ],
              };
            case '/api/departments/department/reviewer-primary':
            case '/api/positions/leave-final-reviewer-primary':
              data = {};
            case '/api/departments/department/reviewer-backups':
              if (backupSaveGate != null) await backupSaveGate!.future;
              backups = [
                {'reviewerId': 'backup', 'reviewerName': 'Backup Employee'},
              ];
              data = {};
            case '/api/positions/leave-final-reviewers':
              data = {
                'effective_date': '2026-09-30',
                'primary': {'id': 'hr', 'name': 'Final Primary'},
                'backups': [],
                'eligible_employees': [
                  {
                    'id': 'hr',
                    'name': 'Final Primary',
                    'position_title': 'HR Manager',
                  },
                  {
                    'id': 'second-hr',
                    'name': 'Second HR',
                    'position_title': 'HR Manager',
                  },
                ],
              };
            case '/api/dtr-corrections/reviewers':
              data = {
                'config': {
                  'effective_from': '2026-10-03',
                  'reviewer_ids': ['dtr-primary', 'dtr-backup'],
                },
                'eligible': [
                  {'id': 'dtr-primary', 'name': 'DTR Primary'},
                  {'id': 'dtr-backup', 'name': 'DTR Backup'},
                ],
              };
            default:
              handler.reject(DioException(requestOptions: options));
              return;
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(
    WidgetTester tester, {
    bool savedScroll = false,
    double width = 1100,
    String? reviewerStep = 'Department Review',
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bucket = PageStorageBucket();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: Container(
              key: const PageStorageKey('dashboard-feature'),
              child: Builder(
                builder: (context) {
                  if (savedScroll) bucket.writeState(context, 320.0);
                  return const ApprovalsSignatoriesPage();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (reviewerStep != null) {
      await tester.tap(find.byTooltip('Edit Shared workflow'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configure $reviewerStep reviewers'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('workflows is the single approval configuration entry', (
    tester,
  ) async {
    await mount(tester, reviewerStep: null);
    expect(find.text('Reviewer Assignments'), findsNothing);
    expect(find.text('Workflows'), findsOneWidget);
    expect(find.text('Shared workflow'), findsOneWidget);
    expect(requests.any((r) => r.path == '/api/departments'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing fixed department cannot open Final HR configuration', (
    tester,
  ) async {
    await mount(tester, reviewerStep: null);
    unawaited(
      showWorkflowReviewerConfiguration(
        tester.element(find.text('Workflows')),
        source: 'department_reviewers',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      requests.any((r) => r.path == '/api/positions/leave-final-reviewers'),
      isFalse,
    );
    expect(
      find.text('Select a department before configuring reviewers.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'department setup retries a failed load from the workflow editor',
    (tester) async {
      failDepartments = true;
      await mount(tester);
      expect(find.text('Retry'), findsOneWidget);
      failDepartments = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Department Primary'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsaved backups cannot be closed with Done and can be discarded',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Add backup reviewer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup Employee').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Close without saving'));
      await tester.pumpAndSettle();
      expect(requests.any((r) => r.method == 'PUT'), isFalse);
      await tester.tap(find.byTooltip('Configure Department Review reviewers'));
      await tester.pumpAndSettle();
      expect(find.text('Backup Employee'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reviewer setup cannot close while backup changes are saving', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Add backup reviewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup Employee').last);
    await tester.pumpAndSettle();
    backupSaveGate = Completer<void>();
    await tester.tap(find.text('Save backups'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Close without saving'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
          .onPressed,
      isNull,
    );
    backupSaveGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reviewer group can be configured while editing the approval step',
    (tester) async {
      await mount(tester, reviewerStep: null);
      await tester.tap(find.byTooltip('Edit Shared workflow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Department Review').last);
      await tester.pumpAndSettle();
      final configure = find.widgetWithText(TextButton, 'Configure reviewers');
      await tester.ensureVisible(configure);
      await tester.tap(configure);
      await tester.pumpAndSettle();
      expect(find.text('Department Primary'), findsOneWidget);
      expect(find.textContaining('shared by every workflow'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final finalReview in [false, true]) {
    testWidgets('primary designation chooses an employee: final=$finalReview', (
      tester,
    ) async {
      await mount(
        tester,
        reviewerStep: finalReview ? 'HR Review' : 'Department Review',
      );
      await tester.tap(find.text('Primary designation'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          finalReview ? 'Final HR Reviewer' : 'Department Head Reviewer',
        ),
        findsOneWidget,
      );
      final employeeField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Employee',
      );
      await tester.tap(employeeField);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(finalReview ? 'Second HR' : 'Backup Employee').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save designation'));
      await tester.pumpAndSettle();
      final save = requests.singleWhere((r) => r.method == 'PUT');
      expect(
        save.path,
        finalReview
            ? '/api/positions/leave-final-reviewer-primary'
            : '/api/departments/department/reviewer-primary',
      );
      expect(save.data, {
        'employee_id': finalReview ? 'second-hr' : 'backup',
        'effective_from': '2026-09-30',
        'effective_to': null,
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'saved department backups remain visible in both shared workflows',
    (tester) async {
      await mount(tester);
      expect(find.text('Department Primary'), findsOneWidget);
      await tester.tap(find.text('Add backup reviewer').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup Employee').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save backups').first);
      await tester.pumpAndSettle();
      final save = requests.singleWhere((r) => r.method == 'PUT');
      expect(save.path, '/api/departments/department/reviewer-backups');
      expect(save.data, {
        'effective_from': '2026-09-30',
        'employee_ids': ['backup'],
      });
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configure Department Review reviewers'));
      await tester.pumpAndSettle();
      expect(
        find.text('Shared reviewer assignments for Leave and Locator'),
        findsOneWidget,
      );
      expect(find.text('Backup Employee'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'designation history does not read the dashboard scroll offset as a boolean',
    (tester) async {
      periods = [
        for (final role in [
          'dtr_office_hours_verifier',
          'dtr_hr_officer',
          'leave_credit_certifier',
        ])
          {
            'id': role,
            'role_key': role,
            'employee_id': 'official',
            'name': 'Official $role',
            'effective_from': '2026-01-01',
            'position_title': 'Officer',
            'is_effective': true,
          },
      ];
      await mount(tester, savedScroll: true, reviewerStep: null);
      expect(tester.takeException(), isNull);
      final tabScroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tabScroll.position.pixels, 0.0);
      await tester.tap(find.text('Report Signatories').first);
      await tester.pumpAndSettle();
      final verifierHistory = find.byKey(
        const PageStorageKey(
          'official-signatory-history-dtr_office_hours_verifier',
        ),
      );
      await tester.ensureVisible(verifierHistory);
      await tester.tap(
        find.descendant(
          of: verifierHistory,
          matching: find.text('Designation history (1)'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find
            .descendant(
              of: verifierHistory,
              matching: find.text('Official dtr_office_hours_verifier'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(verifierHistory);
      expect(
        find
            .descendant(
              of: verifierHistory,
              matching: find.text('Official dtr_office_hours_verifier'),
            )
            .hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('report tab no longer offers a separate leave certifier', (
    tester,
  ) async {
    await mount(tester, reviewerStep: null);
    await tester.tap(find.text('Report Signatories').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-entry-dtr_office_hours_verifier')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-entry-dtr_hr_officer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-entry-leave_credit_certifier')),
      findsNothing,
    );
    expect(requests.any((r) => r.path.endsWith('/automatic-mayor')), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('office-wide review opens separately from department review', (
    tester,
  ) async {
    await mount(tester, reviewerStep: 'HR Review');
    expect(find.text('Final Primary'), findsOneWidget);
    expect(find.text('Department Primary'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configure Department Review reviewers'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Human');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-entry-office-wide')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-entry-department')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile opens selected details and returns to the list', (
    tester,
  ) async {
    await mount(tester, width: 420);
    expect(find.text('Department Primary'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-entry-department')));
    await tester.pumpAndSettle();
    expect(find.text('Department Primary'), findsOneWidget);
    await tester.tap(find.text('Back to list'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-entry-department')),
      findsOneWidget,
    );
    expect(find.text('Department Primary'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired correction reviewer settings are not exposed', (
    tester,
  ) async {
    await mount(tester, reviewerStep: null);
    expect(find.text('DTR Corrections'), findsNothing);
    expect(
      requests.any((r) => r.path == '/api/dtr-corrections/reviewers'),
      isFalse,
    );
    expect(find.text('Reviewer Assignments'), findsNothing);
    expect(find.text('Workflows'), findsOneWidget);
  });
}
