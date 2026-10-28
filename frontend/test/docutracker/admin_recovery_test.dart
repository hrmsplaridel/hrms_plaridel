import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_admin_recovery_card.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_workflow_step_strip.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_admin_recovery.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_progress.dart';

DocuTrackerDocument _flagged({
  DocumentStatus status = DocumentStatus.overdue,
  bool needsAdminIntervention = true,
  String? sourceModule,
  bool sourceOnly = false,
}) {
  return DocuTrackerDocument(
    id: 'doc-1',
    documentNumber: 'DOC-2026-000099',
    documentType: 'memo',
    title: 'Supply request',
    status: status,
    currentStep: 2,
    needsAdminIntervention: needsAdminIntervention,
    sourceModule: sourceModule,
    sourceOnly: sourceOnly,
  );
}

Future<DocuTrackerRecoveryOptions> _departmentOptions() {
  return Future.value(
    docuTrackerRecoveryOptionsFromJson(const {
      'department_name': 'Engineering',
      'assignee_source': 'submitter_department_reviewers',
      'candidates': [
        {'user_id': 'ben', 'name': 'Ben Cruz', 'role_label': 'Backup 2'},
      ],
      'message': null,
    }),
  );
}

void main() {
  test('recovery notice and action follow the document and the admin role', () {
    final flagged = _flagged();
    expect(docuTrackerShowAdminRecoveryNotice(flagged), isTrue);
    expect(
      docuTrackerShowAdminRecoveryAction(doc: flagged, isAdmin: true),
      isTrue,
    );
    expect(
      docuTrackerShowAdminRecoveryAction(doc: flagged, isAdmin: false),
      isFalse,
    );
    expect(
      docuTrackerShowAdminRecoveryNotice(
        _flagged(sourceModule: 'dtr', sourceOnly: true),
      ),
      isFalse,
    );
    expect(
      docuTrackerShowAdminRecoveryAction(
        doc: _flagged(status: DocumentStatus.approved),
        isAdmin: true,
      ),
      isFalse,
    );
  });

  test('recovery options show the backend list and department unchanged', () {
    final options = docuTrackerRecoveryOptionsFromJson(const {
      'department_name': 'Engineering',
      'assignee_source': 'submitter_department_reviewers',
      'candidates': [
        {'user_id': 'ben', 'name': 'Ben Cruz', 'role_label': 'Backup 1'},
        {'user_id': 'cara', 'name': 'Cara Lim', 'role_label': 'Backup 2'},
      ],
    });

    expect(options.departmentName, 'Engineering');
    expect(options.candidates.map((person) => person.userId), ['ben', 'cara']);
    expect(options.message, isNull);
    expect(options.canSelect, isTrue);
  });

  test(
    'an empty backend list keeps the explanation and stays unselectable',
    () {
      final options = docuTrackerRecoveryOptionsFromJson(const {
        'department_name': 'Engineering',
        'candidates': [],
        'message':
            'No eligible replacement reviewer is configured for this step.',
      });

      expect(options.departmentName, 'Engineering');
      expect(options.candidates, isEmpty);
      expect(options.canSelect, isFalse);
      expect(options.message, docuTrackerNoReplacementReviewerMessage);
    },
  );

  test('the recorded intervention reason is the newest matching history row', () {
    final reason = docuTrackerAdminRecoveryReason([
      DocumentHistoryEntry(
        documentId: 'doc-1',
        action: 'overdue',
        remarks: 'Older Admin Recovery note',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
      DocumentHistoryEntry(
        documentId: 'doc-1',
        action: 'remark',
        remarks: 'A routine comment',
        createdAt: DateTime.utc(2026, 10, 3),
      ),
      DocumentHistoryEntry(
        documentId: 'doc-1',
        action: 'overdue',
        remarks:
            'Escalation stopped: no other eligible department reviewer is available. Admin Recovery is required.',
        createdAt: DateTime.utc(2026, 10, 2),
      ),
    ]);

    expect(reason, contains('no other eligible department reviewer'));
  });

  testWidgets(
    'an administrator sees Recover Assignment and an employee does not',
    (tester) async {
      await tester.pumpWidget(
        _host(
          child: Column(
            children: [
              DocuTrackerAdminRecoveryCard(
                showAction: true,
                documentNumber: 'DOC-2026-000099',
                documentTitle: 'Supply request',
                stepLabel: 'Step 2 · Department review',
                currentReviewer: 'Ana Reyes',
                reason: 'Admin Recovery is required.',
                loadOptions: _departmentOptions,
                onSubmit: (_, _) async => null,
              ),
              const DocuTrackerAdminRecoveryCard(
                showAction: false,
                documentNumber: 'DOC-2026-000099',
                documentTitle: 'Supply request',
                stepLabel: 'Step 2',
                currentReviewer: 'Ana Reyes',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Admin attention required'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('docutracker-admin-recovery-action')),
        findsOneWidget,
      );
      expect(find.text('Admin Recovery is required.'), findsOneWidget);
    },
  );

  testWidgets('the dialog lists only the eligible replacement', (tester) async {
    await tester.pumpWidget(
      _host(
        child: DocuTrackerAdminRecoveryCard(
          showAction: true,
          documentNumber: 'DOC-2026-000099',
          documentTitle: 'Supply request',
          stepLabel: 'Step 2 · Department review',
          currentReviewer: 'Ana Reyes',
          loadOptions: _departmentOptions,
          onSubmit: (_, _) async => null,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Ben Cruz'), findsOneWidget);
    expect(find.text('Cara Lim'), findsNothing);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('DOC-2026-000099 · Supply request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remarks are required before recovery is submitted', (
    tester,
  ) async {
    var submitted = 0;
    await tester.pumpWidget(
      _host(
        child: DocuTrackerAdminRecoveryCard(
          showAction: true,
          documentNumber: 'DOC-2026-000099',
          documentTitle: 'Supply request',
          stepLabel: 'Step 2',
          currentReviewer: 'Ana Reyes',
          loadOptions: _departmentOptions,
          onSubmit: (_, _) async {
            submitted += 1;
            return null;
          },
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();

    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text(docuTrackerRecoveryRemarksRequired), findsOneWidget);
    expect(submitted, 0);

    await tester.enterText(
      find.byKey(const ValueKey('docutracker-admin-recovery-remarks')),
      'Primary reviewer unavailable',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const ValueKey('docutracker-admin-recovery-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('a backend rejection stays visible and reloads candidates', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      _host(
        child: DocuTrackerAdminRecoveryCard(
          showAction: true,
          documentNumber: 'DOC-2026-000099',
          documentTitle: 'Supply request',
          stepLabel: 'Step 2',
          currentReviewer: 'Ana Reyes',
          loadOptions: () async {
            loads += 1;
            if (loads == 1) return _departmentOptions();
            return docuTrackerRecoveryOptionsFromJson(const {
              'department_name': 'Engineering',
              'current_step': 3,
              'step_label': 'Mayor review',
              'current_holder_name': 'Luis Santos',
              'candidates': [],
              'message':
                  'No eligible replacement reviewer is configured for this step.',
            });
          },
          onSubmit: (_, _) async =>
              'The recovery assignee is not configured for the current workflow step',
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('docutracker-admin-recovery-remarks')),
      'Primary reviewer unavailable',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'The recovery assignee is not configured for the current workflow step',
      ),
      findsOneWidget,
    );
    expect(find.text(docuTrackerNoReplacementReviewerMessage), findsOneWidget);
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Step 3 · Mayor review'), findsOneWidget);
    expect(find.text('Luis Santos'), findsOneWidget);
    expect(loads, 2);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('docutracker-admin-recovery-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('a successful recovery updates the workflow strip', (
    tester,
  ) async {
    await tester.pumpWidget(const _RecoveryHarness());
    expect(find.text('Ana Reyes'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('docutracker-admin-recovery-remarks')),
      'Primary reviewer unavailable',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Ben Cruz'), findsWidgets);
    expect(find.textContaining('Assignment recovered'), findsOneWidget);
    expect(find.text('Current step'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('docutracker-admin-recovery-dialog')),
      findsNothing,
    );
  });

  testWidgets('an empty candidate list explains why recovery cannot continue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: DocuTrackerAdminRecoveryCard(
          showAction: true,
          documentNumber: 'DOC-2026-000099',
          documentTitle: 'Supply request',
          stepLabel: 'Step 1 · Department review',
          currentReviewer: 'Ana Reyes',
          loadOptions: () async => docuTrackerRecoveryOptionsFromJson(const {
            'department_name': 'Engineering',
            'candidates': [],
            'message':
                'No eligible replacement reviewer is configured for this step.',
          }),
          onSubmit: (_, _) async => null,
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Engineering'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('docutracker-admin-recovery-empty')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('docutracker-admin-recovery-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the recovery dialog fits a narrow dark layout', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: DocuTrackerAdminRecoveryCard(
              showAction: true,
              documentNumber: 'DOC-2026-000099',
              documentTitle: 'Supply request with a long title',
              stepLabel: 'Step 2 · Department review',
              currentReviewer: 'Ana Reyes',
              loadOptions: _departmentOptions,
              onSubmit: (_, _) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Recover Assignment'), findsWidgets);
    expect(find.text('Ben Cruz'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 280,
            child: DocuTrackerAdminRecoveryCard(
              showAction: false,
              documentNumber: 'DOC-2026-000099',
              documentTitle: 'Supply request',
              stepLabel: 'Step 2',
              currentReviewer: 'Ana Reyes',
              reason: 'Admin intervention is required.',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Admin attention required'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('docutracker-admin-recovery-action')),
      findsNothing,
    );
  });
}

Widget _host({required Widget child}) {
  return MaterialApp(home: Scaffold(body: child));
}

class _RecoveryHarness extends StatefulWidget {
  const _RecoveryHarness();

  @override
  State<_RecoveryHarness> createState() => _RecoveryHarnessState();
}

class _RecoveryHarnessState extends State<_RecoveryHarness> {
  String _reviewer = 'Ana Reyes';

  @override
  Widget build(BuildContext context) {
    final doc = DocuTrackerDocument(
      id: 'doc-1',
      documentType: 'memo',
      title: 'Supply request',
      status: DocumentStatus.overdue,
      currentStep: 2,
      assigneeName: _reviewer,
      needsAdminIntervention: true,
    );
    final progress = docuTrackerWorkflowProgress(
      doc: doc,
      steps: const [
        WorkflowStep(stepOrder: 1, assigneeType: 'user', label: 'Receiving'),
        WorkflowStep(
          stepOrder: 2,
          assigneeType: 'user',
          label: 'Department review',
        ),
      ],
      history: const [],
    );
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            DocuTrackerAdminRecoveryCard(
              showAction: true,
              documentNumber: 'DOC-2026-000099',
              documentTitle: doc.title,
              stepLabel: 'Step 2 · Department review',
              currentReviewer: _reviewer,
              loadOptions: _departmentOptions,
              onSubmit: (candidate, remarks) async {
                expect(remarks, 'Primary reviewer unavailable');
                expect(candidate.userId, 'ben');
                setState(() => _reviewer = candidate.name);
                return null;
              },
            ),
            DocuTrackerWorkflowStepStrip(progress: progress),
          ],
        ),
      ),
    );
  }
}
