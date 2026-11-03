import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_dashboard_status_chip.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_dashboard_sections.dart';

const _creator = 'creator-1';
const _receiver = 'receiver-1';
const _outsider = 'outsider-1';

DocuTrackerDocument _notice({
  String createdBy = _creator,
  String status = 'approved',
  bool releaseRequired = true,
  String? releasedAt,
  bool viewerReleaseAccess = false,
  bool viewerCanRelease = false,
  String? currentHolderId,
  bool viewerIsRoutingAssignee = false,
  bool viewerParticipatedInSource = false,
  List<String> signatureSignerIds = const [],
}) {
  return DocuTrackerDocument.fromJson({
    'id': 'doc-6',
    'document_number': 'DOC-2026-000006',
    'document_type': 'memo',
    'title': 'Released notice',
    'status': status,
    'created_by': createdBy,
    'release_required': releaseRequired,
    'viewer_release_access': viewerReleaseAccess,
    'viewer_can_release': viewerCanRelease,
    'viewer_is_routing_assignee': viewerIsRoutingAssignee,
    'viewer_participated_in_source': viewerParticipatedInSource,
    'signature_signer_ids': signatureSignerIds,
    if (currentHolderId != null) 'current_holder_id': currentHolderId,
    if (releasedAt != null) 'released_at': releasedAt,
  });
}

void main() {
  group('creator dashboard release labels', () {
    test('after approval without a release requirement shows Approved', () {
      final doc = _notice(releaseRequired: false);
      expect(doc.status, DocumentStatus.approved);
      expect(docuTrackerDashboardStatusLabel(doc), 'Approved');
    });

    test('awaiting release shows Approved — awaiting release', () {
      final doc = _notice();
      expect(doc.status, DocumentStatus.approved);
      expect(doc.isAwaitingRelease, isTrue);
      expect(
        docuTrackerDashboardStatusLabel(doc),
        'Approved — awaiting release',
      );
      expect(
        docuTrackerReleasedViewDocuments(documents: [doc], userId: _creator),
        isEmpty,
      );
    });

    test('after release shows Released and keeps status approved', () {
      final doc = _notice(
        releasedAt: '2026-10-28T08:00:00',
        viewerReleaseAccess: true,
      );
      expect(doc.status, DocumentStatus.approved);
      expect(doc.isReleased, isTrue);
      expect(docuTrackerDashboardStatusLabel(doc), 'Released');
      expect(
        docuTrackerReleasedViewDocuments(documents: [doc], userId: _creator),
        isEmpty,
        reason: 'the creator already has the document in Completed',
      );
    });
  });

  group('receiving-department dashboard', () {
    test('lists a released document the backend already exposed', () {
      final doc = _notice(
        releasedAt: '2026-10-28T08:00:00',
        viewerReleaseAccess: true,
      );
      expect(
        DocuTrackerDocumentVisibility.isVisible(doc: doc, userId: _receiver),
        isTrue,
      );
      final listed = docuTrackerReleasedViewDocuments(
        documents: [doc],
        userId: _receiver,
      );
      expect(listed, [doc]);
      expect(doc.viewerCanRelease, isFalse);
      expect(docuTrackerDashboardStatusLabel(doc), 'Released');
    });

    test('does not treat an empty inbox as every accessible document', () {
      expect(
        docuTrackerEmployeeDashboardEmptyTitle,
        'No documents yet',
      );
      expect(
        docuTrackerEmployeeDashboardEmptyMessage,
        contains('work assigned to you'),
      );
      expect(
        docuTrackerEmployeeDashboardEmptyMessage,
        contains('released to your department'),
      );

      final awaitingForReleaser = _notice(viewerReleaseAccess: true);
      expect(
        docuTrackerReleasedViewDocuments(
          documents: [awaitingForReleaser],
          userId: _receiver,
        ),
        isEmpty,
      );
    });

    test('excludes an unrelated employee and a denied viewer', () {
      final released = _notice(releasedAt: '2026-10-28T08:00:00');
      expect(
        DocuTrackerDocumentVisibility.isVisible(doc: released, userId: _outsider),
        isFalse,
      );
      expect(
        docuTrackerReleasedViewDocuments(
          documents: [released],
          userId: _outsider,
        ),
        isEmpty,
      );

      final denied = _notice(
        releasedAt: '2026-10-28T08:00:00',
        viewerReleaseAccess: false,
      );
      expect(
        docuTrackerReleasedViewDocuments(
          documents: [denied],
          userId: _receiver,
        ),
        isEmpty,
      );
    });

    test('release visibility does not add release authority', () {
      final awaitingReleaser = _notice(viewerCanRelease: true);
      expect(awaitingReleaser.viewerCanRelease, isTrue);
      expect(
        docuTrackerReleasedViewDocuments(
          documents: [awaitingReleaser],
          userId: _receiver,
        ),
        isEmpty,
      );

      final released = _notice(
        releasedAt: '2026-10-28T08:00:00',
        viewerReleaseAccess: true,
        viewerCanRelease: true,
      );
      expect(
        docuTrackerReleasedViewDocuments(
          documents: [released],
          userId: _receiver,
        ),
        isEmpty,
        reason: 'a viewer who can still release is not a view-only recipient',
      );
    });

    test('refresh after release moves the label and the receiver entry', () {
      final before = _notice(viewerReleaseAccess: true);
      expect(
        docuTrackerDashboardStatusLabel(before),
        'Approved — awaiting release',
      );
      expect(
        docuTrackerReleasedViewDocuments(documents: [before], userId: _receiver),
        isEmpty,
      );

      final after = _notice(
        releasedAt: '2026-10-28T09:00:00',
        viewerReleaseAccess: true,
        viewerCanRelease: false,
      );
      expect(after.status, DocumentStatus.approved);
      expect(docuTrackerDashboardStatusLabel(after), 'Released');
      expect(
        docuTrackerReleasedViewDocuments(documents: [after], userId: _receiver),
        [after],
      );
      expect(
        docuTrackerReleasedViewDocuments(documents: [after], userId: _creator),
        isEmpty,
      );
    });
  });

  testWidgets('narrow dashboard chip keeps the awaiting-release label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 34, height: 34),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Released notice')),
                  const SizedBox(width: 8),
                  DocuTrackerDashboardStatusChip(
                    document: _notice(),
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Approved — awaiting release'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
