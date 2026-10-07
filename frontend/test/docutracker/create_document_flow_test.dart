import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_create_document_dialog.dart';

void main() {
  final travelOrder = DocumentType.fromDisplayName('Travel Order');

  Future<void> pumpFlow(WidgetTester tester, List<DocumentType> types) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocuTrackerCreateDocumentFlow(
            provider: DocuTrackerProvider(),
            createdBy: 'user-1',
            typeOptions: types,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('admin-published types are offered alongside built-in types', () {
    final options = docuTrackerCreatableTypeOptions([
      DocumentType.memo,
      travelOrder,
      DocumentType.memo,
    ]);

    expect(options, [DocumentType.memo, travelOrder]);
    expect(docuTrackerCreatableTypeOptions([travelOrder]), [travelOrder]);
    expect(docuTrackerCreatableTypeOptions(null), isEmpty);
    expect(docuTrackerCreatableTypeOptions(const []), isEmpty);
  });

  test('source-module types are never offered for manual creation', () {
    final types = docuTrackerManuallyCreatableTypes([
      travelOrder,
      DocumentType.fromValue('dtr'),
      DocumentType.fromValue('ld'),
      DocumentType.fromValue('rsp'),
      DocumentType.memo,
      travelOrder,
    ]);

    expect(types, [DocumentType.memo, travelOrder]);
  });

  test('route labels never expose user ids', () {
    expect(
      docuTrackerCreateStepLabel(
        const WorkflowStep(
          stepOrder: 1,
          assigneeType: 'user',
          assigneeSource: 'submitter_department_reviewers',
        ),
      ),
      'Your department reviewer',
    );
    expect(
      docuTrackerCreateStepLabel(
        const WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          userIds: ['9f1c-secret-id'],
        ),
      ),
      'Step 2 reviewer',
    );
    expect(
      docuTrackerCreateStepLabel(
        const WorkflowStep(stepOrder: 3, assigneeType: 'user', label: 'HR'),
      ),
      'HR',
    );
  });

  testWidgets('choosing a type moves to details and Back returns', (
    tester,
  ) async {
    await pumpFlow(tester, [DocumentType.memo, travelOrder]);

    expect(find.text('What are you creating?'), findsOneWidget);
    expect(find.text('Travel Order'), findsOneWidget);

    await tester.tap(
      find.byKey(Key('docutracker-create-type-${travelOrder.value}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draft details'), findsOneWidget);
    expect(find.byKey(const Key('docutracker-create-title')), findsOneWidget);
    expect(
      find.byKey(const Key('docutracker-create-next-steps')),
      findsOneWidget,
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What are you creating?'), findsOneWidget);
  });

  testWidgets('a single allowed type skips the picker', (tester) async {
    await pumpFlow(tester, [travelOrder]);

    expect(find.text('Draft details'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('creating without a title shows an inline error', (tester) async {
    await pumpFlow(tester, [travelOrder]);

    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a document title.'), findsOneWidget);
  });

  testWidgets('no creatable types shows a permission message', (tester) async {
    await pumpFlow(tester, const []);

    expect(
      find.text('You do not have permission to create any document type.'),
      findsOneWidget,
    );
  });
}
