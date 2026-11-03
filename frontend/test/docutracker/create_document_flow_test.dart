import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_create_document_dialog.dart';

class _FakeCreateProvider extends DocuTrackerProvider {
  _FakeCreateProvider({
    this.fail = false,
    this.delay = Duration.zero,
  });

  final bool fail;
  final Duration delay;
  int createCalls = 0;

  @override
  String? get error => fail ? 'Server rejected the draft.' : null;

  @override
  Future<DocuTrackerDocument?> createDocument({
    required String title,
    required DocumentType documentType,
    String? description,
    String? filePath,
    String? fileName,
    required String createdBy,
  }) async {
    createCalls += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (fail) return null;
    return DocuTrackerDocument(
      id: 'draft-$createCalls',
      documentType: documentType.value,
      title: title,
      description: description,
      createdBy: createdBy,
    );
  }
}

void main() {
  final travelOrder = DocumentType.fromDisplayName('Travel Order');

  Future<void> pumpFlow(
    WidgetTester tester, {
    required List<DocumentType> types,
    DocuTrackerProvider? provider,
    Size size = const Size(1000, 900),
    ThemeData? theme,
    bool isMobile = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(
          body: DocuTrackerCreateDocumentFlow(
            provider: provider ?? DocuTrackerProvider(),
            createdBy: 'user-1',
            typeOptions: types,
            isMobile: isMobile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectAndContinue(
    WidgetTester tester,
    DocumentType type,
  ) async {
    final useType = find.byKey(Key('docutracker-create-use-${type.value}'));
    await tester.scrollUntilVisible(useType, 120);
    await tester.pumpAndSettle();
    await tester.tap(useType);
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

  test('type cards expose honest icons and descriptions', () {
    expect(docuTrackerCreateTypeIcon(DocumentType.memo), Icons.article_outlined);
    expect(
      docuTrackerCreateTypeIcon(DocumentType.purchaseRequest),
      Icons.shopping_cart_outlined,
    );
    expect(
      docuTrackerCreateTypeDescription(DocumentType.memo),
      contains('memorandum'),
    );
    expect(
      docuTrackerCreateTypeDescription(DocumentType.purchaseRequest),
      contains('not a certified LGU PR form'),
    );
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

  testWidgets('type selection highlights then Continue opens details', (
    tester,
  ) async {
    await pumpFlow(tester, types: [DocumentType.memo, travelOrder]);

    expect(find.text('What are you creating?'), findsOneWidget);
    expect(find.text('Travel Order'), findsOneWidget);
    expect(find.textContaining('not a certified'), findsNothing);
    expect(find.byKey(const Key('docutracker-create-continue')), findsOneWidget);

    expect(find.byKey(const Key('docutracker-create-continue')), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const Key('docutracker-create-continue')),
          )
          .onPressed,
      isNull,
    );

    await selectAndContinue(tester, travelOrder);

    expect(find.text('Draft details'), findsOneWidget);
    expect(find.byKey(const Key('docutracker-create-title')), findsOneWidget);
    expect(find.text('Create Draft'), findsOneWidget);
    expect(
      find.byKey(const Key('docutracker-create-next-steps')),
      findsOneWidget,
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What are you creating?'), findsOneWidget);
  });

  testWidgets('a single allowed type skips the picker', (tester) async {
    await pumpFlow(tester, types: [travelOrder]);

    expect(find.text('Draft details'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Create Draft'), findsOneWidget);
  });

  testWidgets('creating without a title shows an inline error', (tester) async {
    await pumpFlow(tester, types: [travelOrder]);

    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a document title.'), findsOneWidget);
  });

  testWidgets('Cancel closes the flow from the picker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 640,
                        height: 560,
                        child: DocuTrackerCreateDocumentFlow(
                          provider: DocuTrackerProvider(),
                          createdBy: 'user-1',
                          typeOptions: [DocumentType.memo, travelOrder],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('What are you creating?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('docutracker-create-secondary')));
    await tester.pumpAndSettle();
    expect(find.text('What are you creating?'), findsNothing);
  });

  testWidgets('Create Draft succeeds and pops a result', (tester) async {
    final provider = _FakeCreateProvider();
    DocuTrackerCreateDocumentResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<DocuTrackerCreateDocumentResult>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 640,
                        height: 560,
                        child: DocuTrackerCreateDocumentFlow(
                          provider: provider,
                          createdBy: 'user-1',
                          typeOptions: [DocumentType.memo],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('docutracker-create-title')),
      'Budget memo',
    );
    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pumpAndSettle();

    expect(provider.createCalls, 1);
    expect(result?.document.title, 'Budget memo');
    expect(result?.message, contains('Draft created'));
  });

  testWidgets('duplicate taps do not create multiple drafts', (tester) async {
    final provider = _FakeCreateProvider(
      delay: const Duration(milliseconds: 400),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 640,
                        height: 560,
                        child: DocuTrackerCreateDocumentFlow(
                          provider: provider,
                          createdBy: 'user-1',
                          typeOptions: [DocumentType.memo],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('docutracker-create-title')),
      'Once only',
    );

    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pump();
    expect(find.text('Creating…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(provider.createCalls, 1);
  });

  testWidgets('create failure shows an error banner', (tester) async {
    final provider = _FakeCreateProvider(fail: true);
    await pumpFlow(
      tester,
      types: [DocumentType.memo],
      provider: provider,
    );

    await tester.enterText(
      find.byKey(const Key('docutracker-create-title')),
      'Will fail',
    );
    await tester.tap(find.byKey(const Key('docutracker-create-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('docutracker-create-error')), findsOneWidget);
    expect(find.text('Server rejected the draft.'), findsOneWidget);
    expect(find.text('Create Draft'), findsOneWidget);
  });

  testWidgets('no creatable types shows a permission message', (tester) async {
    await pumpFlow(tester, types: const []);

    expect(
      find.text('You do not have permission to create any document type.'),
      findsOneWidget,
    );
  });

  testWidgets('mobile layout keeps create actions reachable', (tester) async {
    await pumpFlow(
      tester,
      types: [DocumentType.memo, travelOrder],
      size: const Size(390, 780),
      isMobile: true,
    );

    await selectAndContinue(tester, DocumentType.memo);
    expect(find.text('Create Draft'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Optional'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme keeps create flow readable', (tester) async {
    await pumpFlow(
      tester,
      types: [DocumentType.memo, DocumentType.purchaseRequest],
      theme: AppTheme.darkTheme,
    );

    expect(find.text('Memo'), findsOneWidget);
    expect(find.text('Purchase Request'), findsOneWidget);
    expect(find.textContaining('not a certified LGU PR form'), findsOneWidget);

    await selectAndContinue(tester, DocumentType.purchaseRequest);
    expect(find.text('Draft details'), findsOneWidget);
    expect(find.text('Create Draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
