import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/routes/docutracker_routes.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_main.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requestedPaths = <String>[];
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          if (call.method == 'containsKey') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, (call) async {
          if (call.method != 'getAll') return null;
          return <String, dynamic>{
            'appName': 'HRMS Test',
            'packageName': 'hrms_plaridel',
            'version': '1.0.0',
            'buildNumber': '1',
            'buildSignature': '',
            'installerStore': null,
          };
        });
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.uri.path;
          requestedPaths.add(path);
          final data = switch (path) {
            '/api/docutracker/permission-explain' => <String, dynamic>{
              'final_decision': true,
            },
            '/api/docutracker/documents' => <dynamic>[
              <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000001',
                'document_type': 'memo',
                'title': 'Responsive memo',
                'status': 'in_review',
                'current_step': 1,
                'current_holder_id': '00000000-0000-4000-8000-000000000002',
                'assignee_name': 'Department Head',
              },
              <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000003',
                'document_type': 'memo',
                'title': 'Editable draft',
                'status': 'pending',
              },
              <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000004',
                'document_type': 'memo',
                'title': 'Finished memo',
                'status': 'approved',
                'current_step': 2,
              },
              <String, dynamic>{
                'id': 'source:dtr:leave-1',
                'document_type': 'dtr',
                'title': 'Linked leave',
                'status': 'pending',
                'source_module': 'dtr',
                'source_table': 'leave_requests',
                'source_record_id': 'leave-1',
                'source_status': 'draft',
                'source_action': 'complete_in_dtr',
                'source_action_label': 'Complete and submit in DTR',
                'source_only': true,
              },
              <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000005',
                'document_type': 'memo',
                'title': 'Missing assignment',
                'status': 'in_review',
                'current_step': 2,
              },
            ],
            _ => <dynamic>[],
          };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, null);
  });

  test(
    'DocuTracker navigation opens Documents and has no dashboard section',
    () {
      expect(DocuTrackerRoutes.sections, [
        DocuTrackerSection.documents,
        DocuTrackerSection.admin,
      ]);
      expect(
        DocuTrackerRoutes.sectionFromIndex(0),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sectionFromIndex(-1),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sectionFromIndex(99),
        DocuTrackerSection.documents,
      );
      expect(
        DocuTrackerRoutes.sections.map((section) => section.title),
        isNot(contains('Dashboard')),
      );
    },
  );

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('Documents is the employee landing page at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await _pumpMain(tester);

      expect(find.text('DocuTracker'), findsWidgets);
      expect(find.text('Dashboard'), findsNothing);
      expect(
        find.byKey(const ValueKey('docutracker-document-search')),
        findsOneWidget,
      );
      expect(find.text('Required actions'), findsOneWidget);
      expect(find.text('Complete and submit in DTR'), findsOneWidget);
      if (width == 360) {
        expect(find.text('Filters'), findsOneWidget);
        expect(find.text('Create Draft'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admins see Documents and Admin without a dashboard tab', (
    tester,
  ) async {
    await _pumpMain(tester, isAdmin: true);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(
      find.byKey(const ValueKey('docutracker-document-search')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop table shows the current assignee', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await _pumpMain(tester, isAdmin: true);
    for (
      var i = 0;
      i < 100 && find.text('Responsive memo').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.text('Responsive memo'),
      findsWidgets,
      reason: 'Requests: $requestedPaths',
    );
    expect(find.text('Department Head'), findsOneWidget);
    expect(find.text('Current assignee'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('Workflow complete'), findsOneWidget);
    expect(find.text('Managed in DTR'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    final tableSize = tester.getSize(find.byType(DataTable));
    expect(tableSize.width, greaterThan(1300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin More exposes tools and opens Audit log directly', (
    tester,
  ) async {
    await _pumpMain(tester, isAdmin: true);
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More admin tools'));
    await tester.pumpAndSettle();
    expect(find.text('System access'), findsOneWidget);
    expect(find.text('Audit log'), findsOneWidget);
    expect(find.text('Escalation rules'), findsOneWidget);

    await tester.tap(find.text('Audit log'));
    for (
      var i = 0;
      i < 30 && find.text('Governance audit log').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Governance audit log'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMain(WidgetTester tester, {bool isAdmin = false}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider()
            ..replaceUser(
              AppUser(
                id: '00000000-0000-4000-8000-000000000002',
                email: 'reviewer@hrms.local',
                role: isAdmin ? 'admin' : 'employee',
                fullName: 'Test Reviewer',
              ),
            ),
        ),
        ChangeNotifierProvider(create: (_) => DocuTrackerProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DocuTrackerMain(isAdmin: isAdmin)),
        ),
      ),
    ),
  );
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final createReady = find
        .byKey(const ValueKey('docutracker-create-document'))
        .evaluate()
        .isNotEmpty;
    final actionsReady = find.text('Required actions').evaluate().isNotEmpty;
    if (createReady && actionsReady) {
      break;
    }
  }
  await tester.pump();
}
