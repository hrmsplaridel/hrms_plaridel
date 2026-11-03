import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_action_feedback.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';

DocuTrackerDocument _doc({
  DocumentStatus status = DocumentStatus.inReview,
  String? assigneeName,
  bool releaseRequired = false,
  String? releasedAt,
}) {
  return DocuTrackerDocument(
    id: 'doc-1',
    documentType: 'memo',
    title: 'Supply request',
    status: status,
    assigneeName: assigneeName,
    releaseRequired: releaseRequired,
    releasedAt: releasedAt == null ? null : DateTime.parse(releasedAt),
  );
}

void main() {
  test(
    'success messages follow the updated document and name the next reviewer',
    () {
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'approve',
          document: _doc(assigneeName: 'Ana Reyes'),
        ),
        'Approved and moved to the next reviewer: Ana Reyes',
      );
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'approve',
          document: _doc(status: DocumentStatus.approved),
        ),
        'Final approval completed',
      );
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'approve',
          document: _doc(
            status: DocumentStatus.approved,
            releaseRequired: true,
          ),
        ),
        'Approved — awaiting release',
      );
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'forward',
          document: _doc(assigneeName: 'Ben Cruz'),
        ),
        'Forwarded to next workflow step: Ben Cruz',
      );
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'return',
          document: _doc(
            status: DocumentStatus.returned,
            assigneeName: 'Cara Lim',
          ),
        ),
        '$docuTrackerReturnSuccessMessage Cara Lim is now responsible.',
      );
      expect(
        docuTrackerWorkflowActionMessage(
          action: 'reject',
          document: _doc(status: DocumentStatus.rejected),
        ),
        'Rejected',
      );

      for (final action in [
        'approve',
        'forward',
        'return',
        'reject',
        'submit',
      ]) {
        final message = docuTrackerWorkflowActionMessage(
          action: action,
          document: _doc(
            status: action == 'approve'
                ? DocumentStatus.approved
                : DocumentStatus.inReview,
            releaseRequired: action == 'approve',
          ),
        );
        expect(message, isNot(contains('Released')));
      }
    },
  );

  test(
    'confirmation copy keeps Forward, Approve, Return, and Reject distinct',
    () {
      expect(
        docuTrackerApproveContinueMessage,
        contains('advances this document'),
      );
      expect(
        docuTrackerApproveContinueMessage,
        contains('does not finish the workflow'),
      );
      expect(
        docuTrackerForwardConfirmMessage,
        contains('does not record an approval'),
      );
      expect(docuTrackerForwardConfirmTitle, 'Forward without approval?');
      expect(docuTrackerReturnDialogTitle, 'Return to previous step');
      expect(
        docuTrackerRejectDialogExplanation,
        contains('stops the workflow'),
      );
      expect(
        docuTrackerRejectDialogExplanation,
        contains('reason is required'),
      );

      final release = docuTrackerFinalApproveConfirmCopy(
        typeRequiresRelease: true,
      );
      final none = docuTrackerFinalApproveConfirmCopy(
        typeRequiresRelease: false,
      );
      expect(release.message, contains('finishes workflow approval'));
      expect(release.message, contains('requires a release'));
      expect(none.message, contains('does not require a release'));
    },
  );

  testWidgets('forward confirmation is shown before the action continues', (
    tester,
  ) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text(docuTrackerForwardConfirmTitle),
                    content: const Text(docuTrackerForwardConfirmMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text(docuTrackerForwardConfirmLabel),
                      ),
                    ],
                  ),
                );
                confirmed = accepted == true;
              },
              child: const Text('Forward Without Approval'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Forward Without Approval'));
    await tester.pumpAndSettle();
    expect(find.text(docuTrackerForwardConfirmMessage), findsOneWidget);
    expect(confirmed, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
    expect(find.text(docuTrackerForwardConfirmMessage), findsNothing);
  });
}
