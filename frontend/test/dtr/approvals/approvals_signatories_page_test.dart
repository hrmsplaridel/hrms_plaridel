import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/approvals_signatories_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  var backups = <Map<String, dynamic>>[];
  var periods = <Map<String, dynamic>>[];
  setUp(() {
    ApiClient.instance.init();
    requests.clear();
    backups = [];
    periods = [];
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          dynamic data;
          switch (options.path) {
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
                  {'id': 'backup', 'name': 'Backup Employee'},
                ],
              };
            case '/api/departments/department/reviewer-backups':
              backups = [
                {'reviewerId': 'backup', 'reviewerName': 'Backup Employee'},
              ];
              data = {};
            case '/api/positions/leave-final-reviewers':
              data = {
                'effective_date': '2026-09-30',
                'primary': {'id': 'hr', 'name': 'Final Primary'},
                'backups': [],
                'eligible_employees': [],
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
      await tester.tap(find.text('Locator Workflow'));
      await tester.pumpAndSettle();
      expect(find.text('Shared with Leave Workflow'), findsOneWidget);
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
      await mount(tester, savedScroll: true);
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
    await mount(tester);
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
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('settings-entry-office-wide')));
    await tester.pumpAndSettle();
    expect(find.text('Final Primary'), findsOneWidget);
    expect(find.text('Department Primary'), findsNothing);
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
      find.byKey(const ValueKey('settings-entry-office-wide')),
      findsOneWidget,
    );
    expect(find.text('Department Primary'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired correction reviewer settings are not exposed', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('DTR Corrections'), findsNothing);
    expect(
      requests.any((r) => r.path == '/api/dtr-corrections/reviewers'),
      isFalse,
    );
    expect(find.text('Leave Workflow'), findsOneWidget);
    expect(find.text('Locator Workflow'), findsOneWidget);
  });
}
