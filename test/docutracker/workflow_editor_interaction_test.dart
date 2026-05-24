import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/docutracker/screens/docutracker_workflow_editor_screen.dart';

void main() {
  DocumentRoutingConfig buildConfig() {
    return const DocumentRoutingConfig(
      documentType: DocumentType.memo,
      reviewDeadlineHours: 24,
      version: 1,
      steps: [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Draft Intake'),
        WorkflowStep(stepOrder: 2, assigneeType: 'user', label: 'Finance Review'),
        WorkflowStep(stepOrder: 3, assigneeType: 'user', label: 'Final Approval'),
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
      await tester.drag(mainScrollable, const Offset(0, -260));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('tapping a workflow card updates highlighted step', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Step 1 highlighted'), findsOneWidget);

    final financeText = find.text('Finance Review');
    await scrollMainUntilVisible(tester, financeText);
    expect(financeText, findsWidgets);

    final financeCardTapTarget = find
        .ancestor(
          of: financeText.first,
          matching: find.byType(InkWell),
        )
        .hitTestable()
        .first;

    await tester.tap(financeCardTapTarget);
    await tester.pumpAndSettle();

    expect(find.text('Step 2 highlighted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping route preview chip updates highlighted step', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Step 1 highlighted'), findsOneWidget);

    final previewScrollable = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(previewScrollable, findsOneWidget);

    final previewStep = find
        .descendant(
          of: previewScrollable,
          matching: find.text('Final Approval'),
        )
        .hitTestable();
    expect(previewStep, findsOneWidget);

    await tester.tap(previewStep.first);
    await tester.pumpAndSettle();

    expect(find.text('Step 3 highlighted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
