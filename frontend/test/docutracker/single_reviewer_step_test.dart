import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_document_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';

void main() {
  const config = DocumentRoutingConfig(
    documentType: DocumentType.memo,
    steps: [
      WorkflowStep(
        stepOrder: 1,
        assigneeType: 'user',
        assigneeSource: 'submitter_department_reviewers',
      ),
      WorkflowStep(
        stepOrder: 2,
        assigneeType: 'user',
        assigneeSource: 'specific_users',
        userIds: ['hr-1', 'hr-2'],
      ),
    ],
  );

  // An older routing snapshot that still lists the backups as assignees.
  final departmentReviewDoc = DocuTrackerDocument.fromJson(<String, dynamic>{
    'id': 'doc-1',
    'document_type': 'memo',
    'title': 'Memo',
    'status': 'in_review',
    'current_step': 1,
    'created_by': 'staff-1',
    'current_holder_id': 'head-1',
    'viewer_is_routing_assignee': true,
  });

  test(
    'department review steps are single-reviewer; specific-person steps are not',
    () {
      expect(docuTrackerIsSingleReviewerStep(config, 1), isTrue);
      expect(docuTrackerIsSingleReviewerStep(config, 2), isFalse);
      expect(docuTrackerIsSingleReviewerStep(null, 1), isFalse);
    },
  );

  test(
    'a backup in an old snapshot is not presented as the active reviewer',
    () {
      const snapshot = ['head-1', 'backup-1'];
      expect(
        docuTrackerIsCurrentStepReviewer(
          document: departmentReviewDoc,
          userId: 'head-1',
          snapshotAssigneeIds: snapshot,
          singleReviewerStep: true,
        ),
        isTrue,
      );
      expect(
        docuTrackerIsCurrentStepReviewer(
          document: departmentReviewDoc,
          userId: 'backup-1',
          snapshotAssigneeIds: snapshot,
          singleReviewerStep: true,
        ),
        isFalse,
      );
    },
  );

  test('specific-person steps still present every snapshot assignee', () {
    expect(
      docuTrackerIsCurrentStepReviewer(
        document: departmentReviewDoc,
        userId: 'hr-2',
        snapshotAssigneeIds: const ['hr-1', 'hr-2'],
        singleReviewerStep: false,
      ),
      isTrue,
    );
  });

  test(
    'department queue backups do not get a Required action for the step',
    () {
      bool singleReviewer(DocuTrackerDocument d) =>
          docuTrackerIsSingleReviewerStep(config, d.currentStep ?? 1);

      expect(
        docuTrackerRequiredActionDocuments(
          documents: [departmentReviewDoc],
          userId: 'backup-1',
          isSingleReviewerStep: singleReviewer,
        ),
        isEmpty,
      );
      expect(
        docuTrackerRequiredActionDocuments(
          documents: [departmentReviewDoc],
          userId: 'head-1',
          isSingleReviewerStep: singleReviewer,
        ),
        [departmentReviewDoc],
      );
    },
  );
}
