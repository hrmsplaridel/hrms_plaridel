import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_create_workflow_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_effective_access_preview.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/simplified_workflow_step_editor.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/workflow_step_editor_panel.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_access_policy.dart';

/// Final responsive verification for redesigned DocuTracker admin UIs.
///
/// Pumps isolated screens/dialogs at required widths and fails on Flutter
/// layout exceptions (overflow/clip). Does not bypass mobile admin route
/// restrictions in the live app shell.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Interceptor directoryInterceptor;
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  final widths = <double>[360, 390, 600, 800, 1280];

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
    directoryInterceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.uri.path == '/api/employees') {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'employees': [
                  {
                    'id': 'primary',
                    'full_name': 'Maria Santos',
                    'current_department_name': 'Finance Department',
                    'current_position_name': 'Department Head',
                  },
                  {
                    'id': 'backup',
                    'full_name': 'Juan Dela Cruz',
                    'current_department_name': 'Human Resources',
                    'current_position_name': 'Assistant Department Head',
                  },
                ],
              },
            ),
          );
          return;
        }
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: const <String, dynamic>{},
          ),
        );
      },
    );
    ApiClient.instance.dio.interceptors.add(directoryInterceptor);
  });

  tearDownAll(() {
    ApiClient.instance.dio.interceptors.remove(directoryInterceptor);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, null);
  });

  Future<void> setWidth(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('mobile admin route policy remains restricted under 600px', () {
    expect(DocuTrackerAccessPolicy.isMobileWidth(360), isTrue);
    expect(DocuTrackerAccessPolicy.isMobileWidth(390), isTrue);
    expect(DocuTrackerAccessPolicy.isMobileWidth(599), isTrue);
    expect(DocuTrackerAccessPolicy.isMobileWidth(600), isFalse);
    expect(
      DocuTrackerAccessPolicy.canAccessAdminSurface(
        isMobile: true,
        isAdmin: true,
      ),
      isFalse,
    );
    expect(
      DocuTrackerAccessPolicy.canAccessAdminSurface(
        isMobile: false,
        isAdmin: true,
      ),
      isTrue,
    );
    expect(
      DocuTrackerAccessPolicy.isRouteRestrictedOnMobile(
        '/docutracker/workflow-editor',
      ),
      isTrue,
    );
    expect(
      DocuTrackerAccessPolicy.isRouteRestrictedOnMobile(
        '/docutracker/permissions',
      ),
      isTrue,
    );
  });

  for (final width in widths) {
    testWidgets('Create Workflow dialog layout at ${width.toInt()}px', (
      tester,
    ) async {
      await setWidth(tester, width);
      FlutterErrorDetails? layoutError;
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.toString();
        if (text.contains('overflowed') || text.contains('RenderFlex')) {
          layoutError = details;
        }
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showDocuTrackerCreateWorkflowDialog(
                    context: context,
                    documentTypes: const [
                      DocumentType.memo,
                      DocumentType.purchaseRequest,
                    ],
                    workflowUsageByType: const {'memo': 1},
                    latestVersionByType: const {'memo': 2},
                  );
                },
                child: const Text('Open create'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open create'));
      await tester.pumpAndSettle();

      expect(find.text('Create workflow'), findsOneWidget);
      expect(find.text('Continue to workflow setup'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(layoutError, isNull, reason: layoutError?.toString());
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Create a new document type'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('create-workflow-new-type')), findsOneWidget);
      expect(layoutError, isNull, reason: layoutError?.toString());
    });

    testWidgets('Add Step editor layout at ${width.toInt()}px', (tester) async {
      await setWidth(tester, width);
      FlutterErrorDetails? layoutError;
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.toString();
        if (text.contains('overflowed') || text.contains('RenderFlex')) {
          layoutError = details;
        }
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showWorkflowStepEditor(
                    context,
                    title: 'Add Step',
                    initial: const WorkflowStep(
                      stepOrder: 1,
                      assigneeType: 'user',
                      label: 'Department Head Review',
                      userIds: ['primary', 'backup'],
                      allowedActions: ['approve', 'return', 'reject'],
                    ),
                  );
                },
                child: const Text('Open step'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open step'));
      await tester.pumpAndSettle();

      expect(find.text('Add Step'), findsOneWidget);
      expect(find.text('Save Step'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Primary Assignee'), findsOneWidget);
      expect(layoutError, isNull, reason: layoutError?.toString());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Effective Access Preview layout at ${width.toInt()}px', (
      tester,
    ) async {
      await setWidth(tester, width);
      FlutterErrorDetails? layoutError;
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.toString();
        if (text.contains('overflowed') || text.contains('RenderFlex')) {
          layoutError = details;
        }
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: width == 390 ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocuTrackerEffectiveAccessPreviewCard(
                employees: const [],
                selectedUserId: null,
                documentType: '*',
                documentTypes: const ['*', 'memo'],
                documentTypeLabel: (value) =>
                    value == '*' ? 'All document types' : 'Memo',
                roleLabel: (_) => 'Employee',
                loading: false,
                error: null,
                preview: null,
                hasUnsavedChanges: false,
                onUserChanged: (_) {},
                onDocumentTypeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Effective access preview'), findsOneWidget);
      expect(layoutError, isNull, reason: layoutError?.toString());
      expect(tester.takeException(), isNull);
    });

    testWidgets('Step editor dark theme layout at ${width.toInt()}px', (
      tester,
    ) async {
      await setWidth(tester, width);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: SimplifiedWorkflowStepEditor(
              title: 'Add Step',
              initial: WorkflowStep(
                stepOrder: 1,
                assigneeType: 'user',
                label: 'Review',
                allowedActions: ['approve'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add Step'), findsOneWidget);
      expect(find.text('Save Step'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
