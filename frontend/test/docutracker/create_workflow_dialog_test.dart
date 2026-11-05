import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_create_workflow_dialog.dart';

void main() {
  Future<DocumentType?> openDialog(
    WidgetTester tester, {
    List<DocumentType> types = const [DocumentType.memo, DocumentType.purchaseRequest],
    Map<String, int> usage = const {'memo': 2},
    Map<String, int> versions = const {'memo': 5},
  }) async {
    DocumentType? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDocuTrackerCreateWorkflowDialog(
                    context: context,
                    documentTypes: types,
                    workflowUsageByType: usage,
                    latestVersionByType: versions,
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
    return result;
  }

  testWidgets('defaults to existing type mode and continues with selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    DocumentType? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDocuTrackerCreateWorkflowDialog(
                    context: context,
                    documentTypes: const [
                      DocumentType.memo,
                      DocumentType.purchaseRequest,
                    ],
                    workflowUsageByType: const {'memo': 2},
                    latestVersionByType: const {'memo': 5},
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

    expect(find.text('Create workflow'), findsOneWidget);
    expect(
      find.text(
        'Choose which document type this approval workflow will apply to.',
      ),
      findsOneWidget,
    );
    expect(find.text('Use an existing document type'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-workflow-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-workflow-new-type')), findsNothing);
    expect(find.textContaining('latest version 5'), findsOneWidget);

    final purchaseTile = find.byKey(
      ValueKey('create-workflow-type-${DocumentType.purchaseRequest.value}'),
    );
    await tester.ensureVisible(purchaseTile);
    await tester.tap(purchaseTile);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-workflow-continue')));
    await tester.pumpAndSettle();

    expect(result, DocumentType.purchaseRequest);
  });

  testWidgets('new type mode hides the list and validates duplicates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openDialog(tester);

    await tester.tap(find.text('Create a new document type'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('create-workflow-search')), findsNothing);
    expect(find.byKey(const ValueKey('create-workflow-new-type')), findsOneWidget);
    expect(find.text('Memo'), findsNothing);

    final continueBtn = find.byKey(const ValueKey('create-workflow-continue'));
    expect(tester.widget<FilledButton>(continueBtn).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('create-workflow-new-type')),
      'Memo',
    );
    await tester.pump();
    expect(
      find.text(
        '“Memo” already exists. Choose Use an existing document type instead.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(continueBtn).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('create-workflow-new-type')),
      'Travel Order',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(continueBtn).onPressed, isNotNull);

    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('cancel closes without a selection', (tester) async {
    DocumentType? result = DocumentType.memo;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDocuTrackerCreateWorkflowDialog(
                    context: context,
                    documentTypes: const [DocumentType.memo],
                    workflowUsageByType: const {},
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
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('search filters existing types', (tester) async {
    await openDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('create-workflow-search')),
      'purchase',
    );
    await tester.pump();
    expect(find.text('Purchase Request'), findsOneWidget);
    expect(find.text('Memo'), findsNothing);
  });
}
