import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_workflow_step_strip.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_progress.dart';

DocuTrackerDocument _doc({
  required DocumentStatus status,
  int? currentStep = 1,
  String? assigneeName,
  bool releaseRequired = false,
  DateTime? releasedAt,
}) {
  return DocuTrackerDocument(
    id: 'document-1',
    documentType: 'memo',
    title: 'Routing progress',
    status: status,
    currentStep: currentStep,
    assigneeName: assigneeName,
    releaseRequired: releaseRequired,
    releasedAt: releasedAt,
  );
}

WorkflowStep _step(int order, String label, {bool enabled = true}) {
  return WorkflowStep(
    stepOrder: order,
    assigneeType: 'user',
    label: label,
    enabled: enabled,
  );
}

DocumentHistoryEntry _event({
  required String action,
  required int fromStep,
  String? actorName,
  DateTime? createdAt,
  int? toStep,
}) {
  return DocumentHistoryEntry(
    documentId: 'document-1',
    action: action,
    fromStep: fromStep,
    toStep: toStep,
    actorName: actorName,
    createdAt: createdAt,
  );
}

List<WorkflowStep> get _threeSteps => [
  _step(1, 'Receiving'),
  _step(2, 'Department review'),
  _step(3, 'Final approval'),
];

void main() {
  test(
    'three-step workflow shows the recorded action and the current reviewer',
    () {
      final progress = docuTrackerWorkflowProgress(
        doc: _doc(
          status: DocumentStatus.inReview,
          currentStep: 2,
          assigneeName: 'Ben Cruz',
        ),
        steps: _threeSteps,
        history: [
          _event(
            action: 'forwarded',
            fromStep: 1,
            toStep: 2,
            actorName: 'Ana Reyes',
            createdAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );

      expect(progress.map((step) => step.name), [
        'Receiving',
        'Department review',
        'Final approval',
      ]);
      expect(progress[0].indicator.label, 'Forwarded');
      expect(
        progress[0].indicator.kind,
        DocuTrackerStepIndicatorKind.forwarded,
      );
      expect(progress[0].personName, 'Ana Reyes');
      expect(progress[1].isCurrent, isTrue);
      expect(progress[1].indicator.label, 'Current step');
      expect(progress[1].indicator.detail, 'In review');
      expect(progress[1].personName, 'Ben Cruz');
      expect(progress[2].indicator.label, 'Pending');
      expect(progress[2].personName, isNull);
    },
  );

  test('single-step workflow stays on the current reviewer', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(status: DocumentStatus.inReview, assigneeName: 'Ana Reyes'),
      steps: [_step(1, 'Review')],
    );

    expect(progress, hasLength(1));
    expect(progress.single.indicator.label, 'Current step');
    expect(progress.single.indicator.detail, 'In review');
    expect(progress.single.personName, 'Ana Reyes');
  });

  test(
    'approved and forwarded stay distinct and ignore routing-style approval',
    () {
      final progress = docuTrackerWorkflowProgress(
        doc: _doc(
          status: DocumentStatus.inReview,
          currentStep: 3,
          assigneeName: 'Cara Lim',
        ),
        steps: _threeSteps,
        history: [
          _event(
            action: 'approved',
            fromStep: 1,
            actorName: 'Ana Reyes',
            createdAt: DateTime.utc(2026, 10, 1),
          ),
          _event(
            action: 'forwarded',
            fromStep: 2,
            actorName: 'Ben Cruz',
            createdAt: DateTime.utc(2026, 10, 2),
          ),
        ],
      );

      expect(progress[0].indicator.label, 'Approved');
      expect(progress[0].personName, 'Ana Reyes');
      expect(progress[1].indicator.label, 'Forwarded');
      expect(
        progress[1].indicator.kind,
        DocuTrackerStepIndicatorKind.forwarded,
      );
      expect(progress[1].personName, 'Ben Cruz');
      expect(progress[2].indicator.label, 'Current step');
      expect(progress[2].personName, 'Cara Lim');
    },
  );

  test('a return keeps the current step and the earlier decision', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.returned,
        currentStep: 1,
        assigneeName: 'Ana Reyes',
      ),
      steps: _threeSteps,
      history: [
        _event(
          action: 'returned',
          fromStep: 2,
          toStep: 1,
          actorName: 'Ben Cruz',
          createdAt: DateTime.utc(2026, 10, 3),
        ),
        _event(
          action: 'approved',
          fromStep: 1,
          toStep: 2,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    );

    expect(progress[0].isCurrent, isTrue);
    expect(progress[0].indicator.label, 'Current step');
    expect(progress[0].indicator.detail, 'Returned · Previous visit: Approved');
    expect(progress[0].indicator.kind, DocuTrackerStepIndicatorKind.current);
    expect(progress[0].personName, 'Ana Reyes');
    expect(progress[1].indicator.label, 'Returned');
    expect(progress[1].personName, 'Ben Cruz');
    expect(progress[2].indicator.label, 'Pending');
    expect(progress[2].personName, isNull);
  });

  test('a repeated visit shows the latest decision and the earlier one', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.inReview,
        currentStep: 3,
        assigneeName: 'Cara Lim',
      ),
      steps: _threeSteps,
      history: [
        _event(
          action: 'approved',
          fromStep: 2,
          actorName: 'Ben Cruz',
          createdAt: DateTime.utc(2026, 10, 4),
        ),
        _event(
          action: 'returned',
          fromStep: 3,
          actorName: 'Cara Lim',
          createdAt: DateTime.utc(2026, 10, 3),
        ),
        _event(
          action: 'forwarded',
          fromStep: 2,
          actorName: 'Ben Cruz',
          createdAt: DateTime.utc(2026, 10, 2),
        ),
        _event(
          action: 'approved',
          fromStep: 1,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    );

    expect(progress[1].indicator.label, 'Approved');
    expect(progress[1].indicator.detail, 'Earlier visit: Forwarded');
    expect(progress[1].personName, 'Ben Cruz');
    expect(
      progress[1].indicator.kind,
      isNot(DocuTrackerStepIndicatorKind.current),
    );
    expect(progress[2].indicator.label, 'Current step');
    expect(
      progress[2].indicator.detail,
      'In review · Previous visit: Returned',
    );
    expect(progress[2].personName, 'Cara Lim');
  });

  test(
    'equal timestamps keep the newest history row as the latest decision',
    () {
      final at = DateTime.utc(2026, 10, 2);
      final progress = docuTrackerWorkflowProgress(
        doc: _doc(status: DocumentStatus.inReview, currentStep: 2),
        steps: _threeSteps,
        history: [
          _event(
            action: 'forwarded',
            fromStep: 1,
            actorName: 'Ben Cruz',
            createdAt: at,
          ),
          _event(
            action: 'approved',
            fromStep: 1,
            actorName: 'Ana Reyes',
            createdAt: at,
          ),
        ],
      );

      expect(progress[0].indicator.label, 'Forwarded');
      expect(progress[0].indicator.detail, 'Earlier visit: Approved');
      expect(progress[0].personName, 'Ben Cruz');
    },
  );

  test('overdue and escalated current steps name that state', () {
    final overdue = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.overdue,
        currentStep: 2,
        assigneeName: 'Ben Cruz',
      ),
      steps: _threeSteps,
    );
    expect(overdue[1].indicator.label, 'Current step');
    expect(overdue[1].indicator.detail, 'Overdue');
    expect(overdue[1].personName, 'Ben Cruz');

    final escalated = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.escalated,
        currentStep: 2,
        assigneeName: 'Ben Cruz',
      ),
      steps: _threeSteps,
      history: [
        _event(
          action: 'forwarded',
          fromStep: 1,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    );
    expect(escalated[1].indicator.label, 'Current step');
    expect(escalated[1].indicator.detail, 'Escalated');
    expect(escalated[0].indicator.label, 'Forwarded');
  });

  test('final approval awaiting release is not shown as distributed', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.approved,
        currentStep: 3,
        releaseRequired: true,
        assigneeName: 'Cara Lim',
      ),
      steps: _threeSteps,
      history: [
        _event(
          action: 'approved',
          fromStep: 3,
          actorName: 'Cara Lim',
          createdAt: DateTime.utc(2026, 10, 5),
        ),
        _event(
          action: 'forwarded',
          fromStep: 2,
          actorName: 'Ben Cruz',
          createdAt: DateTime.utc(2026, 10, 4),
        ),
        _event(
          action: 'approved',
          fromStep: 1,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 3),
        ),
      ],
    );

    expect(progress[2].indicator.label, 'Approved');
    expect(progress[2].indicator.detail, 'Awaiting release');
    expect(progress[2].indicator.detail, isNot(contains('Released')));
    expect(progress[2].personName, 'Cara Lim');
    expect(progress[2].isCurrent, isFalse);
    expect(progress[1].indicator.label, 'Forwarded');
  });

  test('a released document shows Released on the final step', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.approved,
        currentStep: 1,
        releaseRequired: true,
        releasedAt: DateTime.utc(2026, 10, 9),
      ),
      steps: [_step(1, 'Review')],
      history: [
        _event(
          action: 'approved',
          fromStep: 1,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 8),
        ),
      ],
    );

    expect(progress.single.indicator.label, 'Approved');
    expect(progress.single.indicator.detail, 'Released');
    expect(progress.single.personName, 'Ana Reyes');
  });

  test('missing history and names are left blank instead of invented', () {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.inReview,
        currentStep: 2,
        assigneeName: '  ',
      ),
      steps: [..._threeSteps, _step(4, 'Skipped', enabled: false)],
      history: [
        _event(action: 'commented', fromStep: 1, actorName: 'Not a decision'),
      ],
    );

    expect(progress, hasLength(3));
    expect(progress[0].indicator.label, 'Decision not recorded');
    expect(progress[0].personName, isNull);
    expect(progress[1].personName, isNull);
    expect(progress[1].indicator.detail, 'In review');
    expect(progress[2].indicator.label, 'Pending');
    expect(progress[2].personName, isNull);
  });

  test('the full history keeps an older decision a single page would drop', () {
    final older = _event(
      action: 'approved',
      fromStep: 1,
      actorName: 'Ana Reyes',
      createdAt: DateTime.utc(2026, 10, 1),
    );
    final newer = _event(
      action: 'forwarded',
      fromStep: 2,
      actorName: 'Ben Cruz',
      createdAt: DateTime.utc(2026, 10, 2),
    );
    final doc = _doc(status: DocumentStatus.inReview, currentStep: 3);
    final full = docuTrackerWorkflowProgress(
      doc: doc,
      steps: _threeSteps,
      history: [newer, older],
    );

    expect(full[0].indicator.label, 'Approved');
    expect(full[0].personName, 'Ana Reyes');
    expect(full[1].indicator.label, 'Forwarded');
  });

  testWidgets('strip and map stay consistent in a narrow dark layout', (
    tester,
  ) async {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.inReview,
        currentStep: 2,
        assigneeName: 'Ben Cruz with a long recorded name',
      ),
      steps: _threeSteps,
      history: [
        _event(
          action: 'approved',
          fromStep: 1,
          actorName: 'Ana Reyes',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ListView(
              children: [
                DocuTrackerWorkflowStepStrip(progress: progress),
                DocuTrackerWorkflowMapList(progress: progress),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('docutracker-workflow-step-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('docutracker-workflow-map')),
      findsOneWidget,
    );
    expect(find.text('Current step'), findsNWidgets(2));
    expect(find.text('In review'), findsNWidgets(2));
    expect(find.text('Approved'), findsNWidgets(2));
    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('Ana Reyes'), findsNWidgets(2));
    expect(find.text('Ben Cruz with a long recorded name'), findsNWidgets(2));
    expect(find.text('Final approval'), findsNWidgets(2));
  });

  testWidgets('light layout does not overflow a narrow strip', (tester) async {
    final progress = docuTrackerWorkflowProgress(
      doc: _doc(
        status: DocumentStatus.overdue,
        currentStep: 1,
        assigneeName: 'Ana Reyes',
      ),
      steps: [_step(1, 'Receiving office review')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: DocuTrackerWorkflowStepStrip(progress: progress),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Current step'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Receiving office review'), findsOneWidget);
  });
}
