import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/workflow_step_editor_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/simplified_workflow_step_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Interceptor directoryInterceptor;
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

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('step editor preserves assignees and action edits at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      WorkflowStep? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showWorkflowStepEditor(
                        context,
                        title: 'Edit Step',
                        initial: const WorkflowStep(
                          stepOrder: 1,
                          assigneeType: 'user',
                          label: 'Department Review',
                          userIds: ['primary', 'backup', 'older-backup'],
                          allowedActions: ['approve', 'reject'],
                        ),
                      );
                    },
                    child: const Text('Open editor'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('Primary Assignee'), findsOneWidget);
      expect(find.text('Backup Assignee (Optional)'), findsOneWidget);
      expect(find.text('Assign Mode'), findsOneWidget);
      expect(find.text('Specific people'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final approve = find.byKey(const ValueKey('workflow-step-action-approve'));
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-step-save')));
      await tester.pumpAndSettle();
      expect(result?.userIds, ['primary', 'backup', 'older-backup']);
      expect(result?.allowedActions, ['reject']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('assignee search uses department and excludes duplicates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(768, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SimplifiedWorkflowStepEditor(
            title: 'Edit Step',
            initial: WorkflowStep(
              stepOrder: 1,
              assigneeType: 'user',
              label: 'Department Review',
              userIds: ['primary', 'backup'],
              allowedActions: ['approve'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workflow-step-primary')),
        matching: find.byTooltip('Clear'),
      ),
    );
    await tester.pumpAndSettle();

    final primaryField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search by name, department, or position',
    );
    await tester.enterText(primaryField, 'Finance');
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos'), findsOneWidget);

    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workflow-step-backup')),
        matching: find.byTooltip('Clear'),
      ),
    );
    await tester.pumpAndSettle();

    final backupField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search optional backup',
    );
    await tester.enterText(backupField, 'Maria');
    await tester.pumpAndSettle();
    // Primary chip still shows Maria; options list must not offer her again.
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Maria Santos'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add step dialog shows mockup sections and validates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    WorkflowStep? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showWorkflowStepEditor(
                    context,
                    title: 'Add Step',
                    initial: const WorkflowStep(
                      stepOrder: 1,
                      assigneeType: 'user',
                      label: '',
                      allowedActions: ['approve', 'return', 'reject'],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add Step'), findsOneWidget);
    expect(
      find.text('Set who handles this step and what they can do.'),
      findsOneWidget,
    );
    expect(find.text('Step Name'), findsOneWidget);
    expect(find.text('Assign Mode'), findsOneWidget);
    expect(find.text('Allowed Actions'), findsOneWidget);
    expect(
      find.text('Note: At least one action must be selected.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('workflow-step-save')));
    await tester.pump();
    expect(find.text('Step name is required.'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('workflow-step-name')),
      'Department Head Review',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workflow-step-save')));
    await tester.pump();
    expect(find.text('Choose a primary assignee.'), findsOneWidget);
  });
}
