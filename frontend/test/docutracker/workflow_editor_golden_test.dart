import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_workflow_editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DocumentRoutingConfig buildConfig() {
    return const DocumentRoutingConfig(
      documentType: DocumentType.memo,
      reviewDeadlineHours: 24,
      version: 1,
      steps: [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Draft Intake'),
        WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          label: 'Finance Review',
        ),
        WorkflowStep(
          stepOrder: 3,
          assigneeType: 'user',
          label: 'Final Approval',
        ),
      ],
    );
  }

  DocumentRoutingConfig buildLongConfig() {
    return DocumentRoutingConfig(
      documentType: DocumentType.memo,
      reviewDeadlineHours: 24,
      version: 1,
      steps: const [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Draft Intake'),
        WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          label: 'Records Check',
        ),
        WorkflowStep(stepOrder: 3, assigneeType: 'user', label: 'HR Review'),
        WorkflowStep(
          stepOrder: 4,
          assigneeType: 'user',
          label: 'Finance Review',
        ),
        WorkflowStep(stepOrder: 5, assigneeType: 'user', label: 'Legal Review'),
        WorkflowStep(
          stepOrder: 6,
          assigneeType: 'user',
          label: 'Department Head',
        ),
        WorkflowStep(
          stepOrder: 7,
          assigneeType: 'user',
          label: 'Final Approval',
        ),
        WorkflowStep(stepOrder: 8, assigneeType: 'user', label: 'Release'),
      ],
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size viewport,
    required DocumentRoutingConfig config,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewport;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(home: DocuTrackerWorkflowEditorScreen(initialConfig: config)),
    );
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('workflow editor shell golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1440, 2400),
      config: buildConfig(),
    );

    expect(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile('goldens/docutracker/workflow_editor_shell.png'),
    );
  });

  testWidgets('workflow editor narrow viewport golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1024, 1800),
      config: buildConfig(),
    );

    expect(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile('goldens/docutracker/workflow_editor_shell_narrow.png'),
    );
  });

  testWidgets('workflow editor long-list golden', (tester) async {
    await pumpScreen(
      tester,
      viewport: const Size(1440, 2400),
      config: buildLongConfig(),
    );

    expect(
      find.byType(DocuTrackerWorkflowEditorScreen),
      matchesGoldenFile(
        'goldens/docutracker/workflow_editor_shell_long_list.png',
      ),
    );
  });
}
