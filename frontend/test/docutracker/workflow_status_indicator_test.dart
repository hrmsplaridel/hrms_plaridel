import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_progress.dart';

DocuTrackerDocument _document({
  required DocumentStatus status,
  int currentStep = 2,
  DateTime? deadline,
}) {
  return DocuTrackerDocument(
    id: 'document-1',
    documentType: 'memo',
    title: 'Test document',
    status: status,
    currentStep: currentStep,
    deadlineTime: deadline,
  );
}

void main() {
  test(
    'returned document phase says it is awaiting review at the previous step',
    () {
      final phase = DocuTrackerWorkflowPhase.forDocument(
        doc: _document(status: DocumentStatus.returned, currentStep: 1),
        totalEnabledSteps: 3,
        currentStepLabel: 'Department Review',
      );

      expect(phase.label, 'Returned to previous step');
      expect(phase.detail, contains('Step 1 of 3'));
      expect(phase.detail, contains('Awaiting review at this step'));
      expect(phase.detail, isNot(contains('Changes')));
    },
  );

  test('final approved step is approved instead of current', () {
    final indicator = docuTrackerIndicatorForStep(
      doc: _document(status: DocumentStatus.approved),
      stepOrder: 2,
    );

    expect(indicator.kind, DocuTrackerStepIndicatorKind.approved);
    expect(indicator.label, 'Approved');
    expect(indicator.isCompleted, isTrue);
  });

  test('completed step distinguishes forwarding from approval', () {
    final doc = _document(status: DocumentStatus.inReview, currentStep: 2);
    final forwarded = docuTrackerIndicatorForStep(
      doc: doc,
      stepOrder: 1,
      history: <DocumentHistoryEntry>[
        DocumentHistoryEntry(
          documentId: 'document-1',
          action: 'forwarded',
          fromStep: 1,
          toStep: 2,
          createdAt: DateTime.utc(2026, 9, 17, 8),
        ),
      ],
    );
    final approved = docuTrackerIndicatorForStep(
      doc: doc,
      stepOrder: 1,
      history: <DocumentHistoryEntry>[
        DocumentHistoryEntry(
          documentId: 'document-1',
          action: 'approved',
          fromStep: 1,
          toStep: 2,
          createdAt: DateTime.utc(2026, 9, 17, 8),
        ),
      ],
    );

    expect(forwarded.label, 'Forwarded');
    expect(approved.label, 'Approved');
  });

  test('returned current step and future step use different indicators', () {
    final doc = _document(status: DocumentStatus.returned, currentStep: 1);
    final current = docuTrackerIndicatorForStep(doc: doc, stepOrder: 1);
    final upcoming = docuTrackerIndicatorForStep(doc: doc, stepOrder: 2);

    expect(current.label, 'Current step');
    expect(current.detail, 'Returned');
    expect(current.kind, isNot(DocuTrackerStepIndicatorKind.approved));
    expect(upcoming.label, 'Pending');
  });

  test('approved phase names release separately from workflow approval', () {
    final awaiting = DocuTrackerWorkflowPhase.forDocument(
      doc: DocuTrackerDocument(
        id: 'document-1',
        documentType: 'memo',
        title: 'Test document',
        status: DocumentStatus.approved,
        currentStep: 2,
        releaseRequired: true,
      ),
    );
    expect(awaiting.label, 'Approved');
    expect(awaiting.detail, 'Awaiting release');

    final released = DocuTrackerWorkflowPhase.forDocument(
      doc: DocuTrackerDocument(
        id: 'document-1',
        documentType: 'memo',
        title: 'Test document',
        status: DocumentStatus.approved,
        currentStep: 2,
        releaseRequired: true,
        releasedAt: DateTime.utc(2026, 10, 9),
      ),
    );
    expect(released.label, 'Released');
    expect(released.detail, 'Approved and released');
  });

  test('expired deadline never replaces a terminal status', () {
    final now = DateTime.utc(2026, 9, 17, 12);
    final expired = now.subtract(const Duration(hours: 1));

    expect(
      docuTrackerStatusForDisplay(
        _document(status: DocumentStatus.approved, deadline: expired),
        now: now,
      ),
      DocumentStatus.approved,
    );
    expect(
      docuTrackerStatusForDisplay(
        _document(status: DocumentStatus.inReview, deadline: expired),
        now: now,
      ),
      DocumentStatus.overdue,
    );
  });
}
