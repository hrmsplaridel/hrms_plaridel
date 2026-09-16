import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_workflow_editor_screen.dart';

void main() {
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

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DocuTrackerWorkflowEditorScreen(initialConfig: buildConfig()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollMainUntilVisible(
    WidgetTester tester,
    Finder target, {
    int maxScrolls = 8,
  }) async {
    final mainScrollable = find.byType(Scrollable).first;
    for (var i = 0; i < maxScrolls; i++) {
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        return;
      }
      await tester.drag(mainScrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('renders the simplified workflow editor', (tester) async {
    await pumpEditor(tester);

    expect(find.text('Memo workflow'), findsOneWidget);
    expect(find.text('Default deadline (hours)'), findsOneWidget);
    expect(find.text('Publish workflow'), findsOneWidget);
    expect(find.text('Save workflow'), findsNothing);
    expect(find.text('Route preview'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordered step list renders later-step labels', (tester) async {
    await pumpEditor(tester);

    expect(find.text('Draft Intake'), findsOneWidget);
    expect(find.text('Finance Review'), findsOneWidget);
    expect(find.text('Final Approval'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add after opens the step editor dialog', (tester) async {
    await pumpEditor(tester);

    final more = find.byTooltip('More step actions');
    await scrollMainUntilVisible(tester, more);
    expect(more, findsWidgets);
    await tester.tap(more.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add step after').last);
    await tester.pumpAndSettle();

    expect(find.text('Add step after 1'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag handle reorder does not throw render exceptions', (
    tester,
  ) async {
    await pumpEditor(tester);

    final handles = find.byIcon(Icons.drag_indicator_rounded);
    await scrollMainUntilVisible(tester, handles);
    expect(handles, findsWidgets);
    final handle = handles.first;
    await tester.drag(handle, const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
