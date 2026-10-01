import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_governance_audit_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final auditRequests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? rowsOverride;

  final defaultRows = <Map<String, dynamic>>[
    {
      'id': 'a-1',
      'actor_id': 'admin-1',
      'actor_name': 'System Admin',
      'event_type': 'permission_saved',
      'entity_type': 'permission',
      'document_type': '*',
      'target_role_id': 'employee',
      'before_state': {'action': 'submit', 'granted': true},
      'after_state': {'action': 'submit', 'granted': false},
      'created_at': DateTime.now().toUtc().toIso8601String(),
    },
    {
      'id': 'a-2',
      'actor_id': 'admin-1',
      'actor_name': 'Maria Santos',
      'event_type': 'workflow_published',
      'entity_type': 'workflow_version',
      'document_type': 'memo',
      'workflow_version': 13,
      'after_state': {'version': 13},
      'created_at': '2026-09-01T02:00:00.000Z',
    },
  ];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'HRMS Plaridel',
      packageName: 'hrms_plaridel',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/docutracker/governance-audit') {
            auditRequests.add(Map.of(options.queryParameters));
            final eventTypes = options.queryParameters['event_type']
                ?.toString()
                .split(',');
            final limit = options.queryParameters['limit'] as int? ?? 50;
            final offset = options.queryParameters['offset'] as int? ?? 0;
            final matching = [
              for (final row in rowsOverride ?? defaultRows)
                if (eventTypes == null ||
                    eventTypes.contains(row['event_type']))
                  row,
            ];
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: matching.skip(offset).take(limit).toList(),
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: const <dynamic>[],
            ),
          );
        },
      ),
    );
  });

  setUp(() {
    auditRequests.clear();
    rowsOverride = null;
  });

  Future<void> pumpScreen(WidgetTester tester, {ThemeData? theme}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const DocuTrackerGovernanceAuditScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists changes in plain language grouped by day', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Today'.toUpperCase()), findsOneWidget);
    expect(find.text('Access rule changed'), findsOneWidget);
    expect(
      find.text(
        'Employee · Submit own drafts · All document types: '
        'Allowed → Blocked',
      ),
      findsOneWidget,
    );
    expect(find.text('Memo workflow v13 is now live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category chips filter on the server', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('audit-category-workflow')));
    await tester.pumpAndSettle();

    expect(
      auditRequests.last['event_type'],
      'workflow_published,step_assignees_updated',
    );
    expect(find.text('Access rule changed'), findsNothing);
    expect(find.text('Workflow published'), findsOneWidget);
  });

  testWidgets('search narrows the loaded changes by person', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const ValueKey('audit-search')), 'maria');
    await tester.pumpAndSettle();

    expect(find.text('Workflow published'), findsOneWidget);
    expect(find.text('Access rule changed'), findsNothing);
  });

  testWidgets('details show a readable before and after', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('audit-entry-a-1')));
    await tester.pumpAndSettle();

    expect(find.text('What changed'), findsOneWidget);
    expect(find.text('Changed by'), findsOneWidget);
    expect(find.text('System Admin'), findsOneWidget);
    expect(find.text('Applies to'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('audit-technical-details')),
      findsOneWidget,
    );
  });

  testWidgets('pages through changes instead of loading them all', (
    tester,
  ) async {
    rowsOverride = [
      for (var i = 1; i <= 15; i++)
        {
          'id': 'p-$i',
          'actor_id': 'admin-1',
          'actor_name': 'Actor $i',
          'event_type': 'workflow_published',
          'entity_type': 'workflow_version',
          'document_type': 'memo',
          'workflow_version': i,
          'after_state': {'version': i},
          'created_at': '2026-09-01T02:00:00.000Z',
        },
    ];
    await pumpScreen(tester);

    expect(auditRequests.last['limit'], 11);
    expect(auditRequests.last['offset'], 0);
    expect(find.byKey(const ValueKey('audit-entry-p-1')), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    final previous = tester.widget<IconButton>(
      find.byKey(const ValueKey('audit-previous-page')),
    );
    expect(previous.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('audit-next-page')));
    await tester.pumpAndSettle();

    expect(auditRequests.last['offset'], 10);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('audit-entry-p-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('audit-entry-p-1')), findsNothing);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('audit-next-page')),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('audit-first-page')));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('audit-entry-p-1')), findsOneWidget);
  });

  testWidgets('hides the pager when everything fits on one page', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('audit-pager')), findsNothing);
  });

  testWidgets('renders in dark mode without errors', (tester) async {
    await pumpScreen(tester, theme: ThemeData(brightness: Brightness.dark));
    expect(find.text('Configuration audit log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
