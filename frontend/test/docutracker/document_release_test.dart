import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_release.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_release_policy_tile.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_release_section.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

Map<String, dynamic> _memoJson({
  bool releaseRequired = true,
  String status = 'approved',
  String? releasedAt,
  bool viewerReleaseAccess = false,
  bool viewerCanRelease = false,
}) => {
  'id': 'doc-1',
  'document_type': 'memo',
  'title': 'Road clearing memo',
  'status': status,
  'created_by': 'creator-1',
  'release_required': releaseRequired,
  if (releasedAt != null) ...{
    'released_at': releasedAt,
    'released_to_department_id': 'dept-eng',
    'released_to_department_name': 'Engineering',
    'released_by': 'hr-1',
    'released_by_name': 'Maria Santos',
    'release_remarks': 'For implementation',
  },
  'viewer_release_access': viewerReleaseAccess,
  'viewer_can_release': viewerCanRelease,
};

DocuTrackerDocument _memo({
  bool releaseRequired = true,
  String status = 'approved',
  String? releasedAt,
  bool viewerReleaseAccess = false,
  bool viewerCanRelease = false,
}) => DocuTrackerDocument.fromJson(
  _memoJson(
    releaseRequired: releaseRequired,
    status: status,
    releasedAt: releasedAt,
    viewerReleaseAccess: viewerReleaseAccess,
    viewerCanRelease: viewerCanRelease,
  ),
);

const _departments = [
  DocuTrackerReleaseDepartment(id: 'dept-eng', name: 'Engineering'),
  DocuTrackerReleaseDepartment(id: 'dept-fin', name: 'Finance'),
];

Future<void> _pumpHost(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('release model', () {
    test('approved release-required memo is awaiting release', () {
      final doc = _memo();
      expect(doc.status, DocumentStatus.approved);
      expect(doc.isAwaitingRelease, isTrue);
      expect(doc.isReleased, isFalse);
      expect(docuTrackerReleaseBadgeLabel(doc), 'Approved · Awaiting release');
      expect(
        docuTrackerReleaseBadgeLabel(doc, short: true),
        'Awaiting release',
      );
    });

    test('released memo keeps approved status and exposes release details', () {
      final doc = _memo(releasedAt: '2026-10-09T15:42:00');
      expect(doc.status, DocumentStatus.approved);
      expect(doc.isAwaitingRelease, isFalse);
      expect(doc.isReleased, isTrue);
      expect(doc.releasedToDepartmentName, 'Engineering');
      expect(doc.releasedByName, 'Maria Santos');
      expect(doc.releaseRemarks, 'For implementation');
      expect(docuTrackerReleaseBadgeLabel(doc), 'Released');
      expect(
        docuTrackerReleasedByLine(doc),
        'Released by Maria Santos · October 9, 2026, 3:42 PM',
      );
    });

    test('types without release behave as before', () {
      final doc = _memo(releaseRequired: false);
      expect(doc.isAwaitingRelease, isFalse);
      expect(doc.isReleased, isFalse);
      expect(docuTrackerReleaseBadgeLabel(doc), isNull);
    });

    test('pending release-required memo is not awaiting release yet', () {
      final doc = _memo(status: 'pending');
      expect(doc.isAwaitingRelease, isFalse);
      expect(docuTrackerReleaseBadgeLabel(doc), isNull);
    });

    test('release fields survive toJson round trip', () {
      final doc = _memo(
        releasedAt: '2026-10-09T15:42:00Z',
        viewerReleaseAccess: true,
      );
      final copy = DocuTrackerDocument.fromJson(doc.toJson());
      expect(copy.releaseRequired, isTrue);
      expect(copy.releasedToDepartmentId, 'dept-eng');
      expect(copy.releasedToDepartmentName, 'Engineering');
      expect(copy.releasedAt, doc.releasedAt);
      expect(copy.viewerReleaseAccess, isTrue);
    });

    test('release options parse departments and drop blank entries', () {
      final options = DocuTrackerReleaseOptions.fromJson({
        'release_required': true,
        'released': false,
        'can_release': true,
        'departments': [
          {'id': 'dept-eng', 'name': 'Engineering'},
          {'id': '', 'name': 'Broken'},
        ],
      });
      expect(options.canRelease, isTrue);
      expect(options.suggestedDepartmentId, isNull);
      expect(options.departments.map((d) => d.name), ['Engineering']);
    });

    test('released history entry and notification labels', () {
      final entry = DocumentHistoryEntry.fromJson({
        'document_id': 'doc-1',
        'action': 'released',
        'actor_name': 'Maria Santos',
        'metadata': {
          'released_to_department_id': 'dept-eng',
          'released_to_department_name': 'Engineering',
        },
      });
      expect(entry.releasedToDepartmentName, 'Engineering');

      const notification = DocumentNotification(
        documentId: 'doc-1',
        userId: 'eng-1',
        type: DocumentNotification.typeReleased,
      );
      expect(notification.displayType, 'Document released to your department');
    });
  });

  group('release visibility', () {
    test('receiving department member sees the document only via backend '
        'release access', () {
      expect(
        DocuTrackerDocumentVisibility.isVisible(doc: _memo(), userId: 'eng-1'),
        isFalse,
      );
      expect(
        DocuTrackerDocumentVisibility.isVisible(
          doc: _memo(
            releasedAt: '2026-10-09T15:42:00Z',
            viewerReleaseAccess: true,
          ),
          userId: 'eng-1',
        ),
        isTrue,
      );
    });
  });

  group('release section', () {
    testWidgets('renders nothing for types without release', (tester) async {
      await _pumpHost(
        tester,
        DocuTrackerReleaseSection(document: _memo(releaseRequired: false)),
      );
      expect(
        find.byKey(const ValueKey('docutracker-release-section')),
        findsNothing,
      );
    });

    testWidgets('awaiting release shows button only when allowed', (
      tester,
    ) async {
      await _pumpHost(tester, DocuTrackerReleaseSection(document: _memo()));
      expect(find.text('Approved · Awaiting release'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-button')),
        findsNothing,
      );

      var pressed = 0;
      await _pumpHost(
        tester,
        DocuTrackerReleaseSection(
          document: _memo(viewerCanRelease: true),
          onRelease: () => pressed++,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('docutracker-release-button')),
      );
      expect(pressed, 1);
    });

    testWidgets('released document shows department, actor and remarks '
        'without a release button', (tester) async {
      await _pumpHost(
        tester,
        DocuTrackerReleaseSection(
          document: _memo(releasedAt: '2026-10-09T15:42:00'),
          onRelease: () {},
        ),
      );
      expect(find.text('Released to Engineering'), findsOneWidget);
      expect(
        find.text('Released by Maria Santos · October 9, 2026, 3:42 PM'),
        findsOneWidget,
      );
      expect(find.text('For implementation'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-button')),
        findsNothing,
      );
    });
  });

  group('release dialog', () {
    Future<DocuTrackerDocument?> openDialog(
      WidgetTester tester, {
      required DocuTrackerReleaseOptions options,
      required DocuTrackerReleaseSubmitter submit,
    }) async {
      DocuTrackerDocument? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await showDocuTrackerReleaseDialog(
                  context,
                  document: _memo(viewerCanRelease: true),
                  loadOptions: (_) async => options,
                  submit: submit,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    FilledButton confirmButton(WidgetTester tester) => tester.widget(
      find.byKey(const ValueKey('docutracker-release-confirm')),
    );

    testWidgets('confirm is disabled until a department is chosen, then '
        'submits once with remarks and pops the released document', (
      tester,
    ) async {
      final calls = <Map<String, String?>>[];
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          departments: _departments,
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async {
              calls.add({
                'documentId': documentId,
                'departmentId': departmentId,
                'remarks': remarks,
                'idempotencyKey': idempotencyKey,
              });
              return DocuTrackerSuccess(
                _memo(releasedAt: '2026-10-09T15:42:00Z'),
              );
            },
      );

      expect(confirmButton(tester).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('docutracker-release-department')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engineering').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('docutracker-release-remarks')),
        'For implementation',
      );
      expect(confirmButton(tester).onPressed, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey('docutracker-release-confirm')),
      );
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single['documentId'], 'doc-1');
      expect(calls.single['departmentId'], 'dept-eng');
      expect(calls.single['remarks'], 'For implementation');
      expect(calls.single['idempotencyKey'], isNotEmpty);
      expect(find.byType(DocuTrackerReleaseDialog), findsNothing);
    });

    testWidgets('backend failure keeps the dialog open with the error', (
      tester,
    ) async {
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          suggestedDepartmentId: 'dept-fin',
          departments: _departments,
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async => const DocuTrackerFailure(
              'This document was already released to Engineering. '
              'A release cannot be changed.',
              statusCode: 409,
            ),
      );

      expect(confirmButton(tester).onPressed, isNotNull);
      await tester.tap(
        find.byKey(const ValueKey('docutracker-release-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocuTrackerReleaseDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-error')),
        findsOneWidget,
      );
    });

    testWidgets('unauthorized viewer cannot confirm', (tester) async {
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: false,
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async => throw StateError('must not submit'),
      );
      expect(
        find.text('You are not authorized to release this document.'),
        findsOneWidget,
      );
      expect(confirmButton(tester).onPressed, isNull);
    });
  });

  group('release policy tile', () {
    testWidgets('loads the type policy and saves toggles, reverting on '
        'failure', (tester) async {
      final saved = <bool>[];
      var fail = false;
      await _pumpHost(
        tester,
        DocuTrackerReleasePolicyTile(
          documentType: 'memo',
          loadPolicies: () async => const [
            DocuTrackerReleasePolicy(
              documentType: 'memo',
              requiresRelease: true,
            ),
            DocuTrackerReleasePolicy(
              documentType: 'purchaseRequest',
              requiresRelease: false,
            ),
          ],
          savePolicy:
              ({required documentType, required requiresRelease}) async {
                saved.add(requiresRelease);
                if (fail) return const DocuTrackerFailure('Save failed');
                return DocuTrackerSuccess(
                  DocuTrackerReleasePolicy(
                    documentType: documentType,
                    requiresRelease: requiresRelease,
                  ),
                );
              },
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('docutracker-release-policy-switch'),
      );
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(saved, [false]);
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

      fail = true;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(saved, [false, true]);
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
      expect(find.text('Save failed'), findsOneWidget);
    });
  });
}
