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
                        title: 'Edit step',
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
      expect(tester.takeException(), isNull);
      final approve = find.widgetWithText(
        CheckboxListTile,
        'Approve and continue',
      );
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Step'));
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
            title: 'Edit step',
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

    final primaryField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search by name, department, or position',
    );
    final backupField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search optional backup',
    );
    await tester.enterText(primaryField, 'Finance');
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos'), findsOneWidget);

    await tester.enterText(backupField, 'Maria');
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
