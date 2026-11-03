import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_release.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/widgets/docutracker_release_policy_tile.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_release_section.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

Map<String, dynamic> _memoJson({
  bool releaseRequired = true,
  String status = 'approved',
  String? releasedAt,
  bool viewerReleaseAccess = false,
  bool viewerCanRelease = false,
  String? currentHolderId,
  List<String> signatureSignerIds = const [],
  bool viewerIsRoutingAssignee = false,
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
  if (currentHolderId != null) 'current_holder_id': currentHolderId,
  'signature_signer_ids': signatureSignerIds,
  'viewer_is_routing_assignee': viewerIsRoutingAssignee,
};

DocuTrackerDocument _memo({
  bool releaseRequired = true,
  String status = 'approved',
  String? releasedAt,
  bool viewerReleaseAccess = false,
  bool viewerCanRelease = false,
  String? currentHolderId,
  List<String> signatureSignerIds = const [],
  bool viewerIsRoutingAssignee = false,
}) => DocuTrackerDocument.fromJson(
  _memoJson(
    releaseRequired: releaseRequired,
    status: status,
    releasedAt: releasedAt,
    viewerReleaseAccess: viewerReleaseAccess,
    viewerCanRelease: viewerCanRelease,
    currentHolderId: currentHolderId,
    signatureSignerIds: signatureSignerIds,
    viewerIsRoutingAssignee: viewerIsRoutingAssignee,
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

    test('release-required approved copy does not say workflow complete', () {
      final awaiting = _memo();
      expect(
        docuTrackerApprovedWorkflowMessage(awaiting),
        'Approved — awaiting release',
      );
      expect(
        docuTrackerApprovedWorkflowDetail(awaiting),
        contains('must still be released'),
      );
      expect(
        docuTrackerApprovedWorkflowMessage(awaiting),
        isNot(contains('workflow is complete')),
      );

      final noRelease = _memo(releaseRequired: false);
      expect(
        docuTrackerApprovedWorkflowMessage(noRelease),
        'This workflow is complete.',
      );
      expect(docuTrackerApprovedWorkflowDetail(noRelease), isNull);

      final released = _memo(releasedAt: '2026-10-09T15:42:00');
      expect(
        docuTrackerApprovedWorkflowMessage(released),
        'This workflow is complete.',
      );
    });

    test(
      'final-approve confirm copy uses the type policy, not the snapshot',
      () {
        final withRelease = docuTrackerFinalApproveConfirmCopy(
          typeRequiresRelease: true,
        );
        expect(withRelease.message, contains('finishes workflow approval'));
        expect(withRelease.message, contains('requires a release'));
        expect(withRelease.message, isNot(contains('Released')));

        final without = docuTrackerFinalApproveConfirmCopy(
          typeRequiresRelease: false,
        );
        expect(without.message, contains('does not require a release'));
        expect(without.confirmLabel, 'Approve and Complete');

        final unknown = docuTrackerFinalApproveConfirmCopy(
          typeRequiresRelease: null,
        );
        expect(unknown.message, 'This finishes workflow approval.');
        expect(unknown.message, isNot(contains('release')));
      },
    );

    test('released department recipient sees view-only; actors do not', () {
      final released = _memo(
        releasedAt: '2026-10-09T15:42:00',
        viewerReleaseAccess: true,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: released,
          userId: 'eng-1',
        ),
        isTrue,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: released,
          userId: 'eng-1',
          hasActiveAction: true,
        ),
        isFalse,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: _memo(
            releasedAt: '2026-10-09T15:42:00',
            viewerReleaseAccess: true,
            viewerCanRelease: true,
          ),
          userId: 'hr-1',
        ),
        isFalse,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: _memo(
            releasedAt: '2026-10-09T15:42:00',
            viewerReleaseAccess: true,
            signatureSignerIds: const ['eng-1'],
          ),
          userId: 'eng-1',
        ),
        isFalse,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: _memo(
            releasedAt: '2026-10-09T15:42:00',
            viewerReleaseAccess: true,
            currentHolderId: 'eng-1',
          ),
          userId: 'eng-1',
        ),
        isFalse,
      );
      expect(
        docuTrackerShowReleasedViewOnlyMessage(
          document: _memo(
            releasedAt: '2026-10-09T15:42:00',
            viewerReleaseAccess: true,
            viewerIsRoutingAssignee: true,
          ),
          userId: 'eng-1',
        ),
        isFalse,
      );
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

    Future<void> expectBrandReleaseStyle(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DocuTrackerReleaseSection(
              document: _memo(viewerCanRelease: true),
              onRelease: () {},
            ),
          ),
        ),
      );
      final context = tester.element(
        find.byKey(const ValueKey('docutracker-release-button')),
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('docutracker-release-button')),
      );
      final brand = DocuTrackerStyles.primaryBrandButtonStyle(context);
      for (final states in <Set<WidgetState>>[
        const {},
        {WidgetState.disabled},
        {WidgetState.hovered},
        {WidgetState.focused},
        {WidgetState.pressed},
      ]) {
        expect(
          button.style?.backgroundColor?.resolve(states),
          brand.backgroundColor?.resolve(states),
        );
        expect(
          button.style?.foregroundColor?.resolve(states),
          brand.foregroundColor?.resolve(states),
        );
      }
      expect(
        button.style?.backgroundColor?.resolve(const {}),
        DocuTrackerTokens.brand,
      );
    }

    testWidgets('Release Document uses the primary brand style (light)', (
      tester,
    ) async {
      await expectBrandReleaseStyle(tester, ThemeData.light());
    });

    testWidgets('Release Document uses the primary brand style (dark)', (
      tester,
    ) async {
      await expectBrandReleaseStyle(tester, ThemeData.dark());
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

  group('release department filter', () {
    test('filters case-insensitively and returns all when query empty', () {
      const departments = [
        DocuTrackerReleaseDepartment(id: '1', name: 'Engineering'),
        DocuTrackerReleaseDepartment(id: '2', name: 'Finance'),
        DocuTrackerReleaseDepartment(
          id: '3',
          name: 'Municipal Planning and Development Office',
        ),
      ];
      expect(docuTrackerFilterReleaseDepartments(departments, ''), departments);
      expect(docuTrackerFilterReleaseDepartments(departments, '  '), departments);
      expect(
        docuTrackerFilterReleaseDepartments(departments, 'eng').map((d) => d.id),
        ['1'],
      );
      expect(
        docuTrackerFilterReleaseDepartments(departments, 'FINANCE').map(
          (d) => d.id,
        ),
        ['2'],
      );
      expect(
        docuTrackerFilterReleaseDepartments(departments, 'planning').map(
          (d) => d.id,
        ),
        ['3'],
      );
      expect(
        docuTrackerFilterReleaseDepartments(departments, 'zzz'),
        isEmpty,
      );
    });
  });

  group('release dialog', () {
    Future<DocuTrackerDocument?> openDialog(
      WidgetTester tester, {
      required DocuTrackerReleaseOptions options,
      required DocuTrackerReleaseSubmitter submit,
      ThemeData? theme,
      Size surfaceSize = const Size(800, 900),
      DocuTrackerDocument? document,
      Future<DocuTrackerReleaseOptions> Function(String)? loadOptions,
    }) async {
      final view = tester.view;
      view.physicalSize = surfaceSize;
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
      DocuTrackerDocument? popped;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: MediaQuery(
            data: MediaQueryData(size: surfaceSize),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await showDocuTrackerReleaseDialog(
                    context,
                    document: document ?? _memo(viewerCanRelease: true),
                    loadOptions: loadOptions ?? (_) async => options,
                    submit: submit,
                  );
                },
                child: const Text('open'),
              ),
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

    Future<void> selectDepartment(
      WidgetTester tester,
      String departmentId,
    ) async {
      await tester.tap(
        find.byKey(ValueKey('docutracker-release-department-$departmentId')),
      );
      await tester.pumpAndSettle();
    }

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

      expect(find.text('Release Document'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-info')),
        findsOneWidget,
      );
      expect(find.text(docuTrackerReleaseInfoViewOnly), findsOneWidget);
      expect(find.text(docuTrackerReleaseInfoIrreversible), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);

      await selectDepartment(tester, 'dept-eng');
      await tester.enterText(
        find.byKey(const ValueKey('docutracker-release-remarks')),
        'For implementation',
      );
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(find.textContaining('Will release to Engineering'), findsOneWidget);

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

    testWidgets('search filters departments and shows empty state', (
      tester,
    ) async {
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
            }) async => throw StateError('must not submit'),
      );

      expect(find.text('Engineering'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('docutracker-release-department-search')),
        'fin',
      );
      await tester.pumpAndSettle();
      expect(find.text('Finance'), findsOneWidget);
      expect(find.text('Engineering'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('docutracker-release-department-search')),
        'zzz-no-match',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('docutracker-release-department-empty')),
        findsOneWidget,
      );
      expect(find.text(docuTrackerReleaseNoDepartmentsFound), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('long department names remain selectable without overflow', (
      tester,
    ) async {
      const longName =
          'Office of the Municipal Planning and Development Coordinator '
          'for Infrastructure and Special Projects';
      await openDialog(
        tester,
        surfaceSize: const Size(360, 780),
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          departments: [
            DocuTrackerReleaseDepartment(id: 'dept-long', name: longName),
            ..._departments,
          ],
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async => DocuTrackerSuccess(
              _memo(releasedAt: '2026-10-09T15:42:00Z'),
            ),
      );

      final title = tester.widget<Text>(
        find.descendant(
          of: find.byKey(
            const ValueKey('docutracker-release-department-dept-long'),
          ),
          matching: find.byType(Text),
        ),
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);

      await selectDepartment(tester, 'dept-long');
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
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
      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('duplicate confirm taps submit only once', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          suggestedDepartmentId: 'dept-eng',
          departments: _departments,
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async {
              calls++;
              await gate.future;
              return DocuTrackerSuccess(
                _memo(releasedAt: '2026-10-09T15:42:00Z'),
              );
            },
      );

      final confirm = find.byKey(const ValueKey('docutracker-release-confirm'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(calls, 1);
      expect(confirmButton(tester).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DocuTrackerReleaseDialog), findsNothing);
    });

    testWidgets('load failure shows error and keeps confirm disabled', (
      tester,
    ) async {
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          departments: _departments,
        ),
        loadOptions: (_) async => throw Exception('Network unavailable'),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async => throw StateError('must not submit'),
      );

      expect(
        find.byKey(const ValueKey('docutracker-release-error')),
        findsOneWidget,
      );
      expect(find.textContaining('Network unavailable'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
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

    testWidgets('uses bottom sheet on narrow screens', (tester) async {
      await openDialog(
        tester,
        surfaceSize: const Size(390, 844),
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
            }) async => throw StateError('must not submit'),
      );

      expect(
        find.byKey(const ValueKey('docutracker-release-sheet-handle')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Release Document'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-department-search')),
        findsOneWidget,
      );
    });

    testWidgets('desktop dialog remains usable', (tester) async {
      await openDialog(
        tester,
        surfaceSize: const Size(1280, 900),
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
            }) async => throw StateError('must not submit'),
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('docutracker-release-sheet-handle')),
        findsNothing,
      );
    });

    testWidgets('renders in dark theme without exceptions', (tester) async {
      await openDialog(
        tester,
        theme: ThemeData.dark(),
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
            }) async => throw StateError('must not submit'),
      );

      expect(find.text('Release Document'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final dialog = tester.widget<Material>(
        find.byKey(const ValueKey('docutracker-release-dialog')),
      );
      expect(
        dialog.color,
        DocuTrackerTokens.surfaceOf(
          tester.element(
            find.byKey(const ValueKey('docutracker-release-dialog')),
          ),
        ),
      );
    });

    testWidgets('remarks stay optional with character counter limit', (
      tester,
    ) async {
      await openDialog(
        tester,
        options: const DocuTrackerReleaseOptions(
          releaseRequired: true,
          released: false,
          canRelease: true,
          suggestedDepartmentId: 'dept-eng',
          departments: _departments,
        ),
        submit:
            ({
              required documentId,
              required departmentId,
              remarks,
              idempotencyKey,
            }) async => DocuTrackerSuccess(
              _memo(releasedAt: '2026-10-09T15:42:00Z'),
            ),
      );

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('docutracker-release-remarks')),
      );
      expect(field.maxLength, docuTrackerReleaseRemarksMaxLength);
      expect(field.enabled, isTrue);
      expect(confirmButton(tester).onPressed, isNotNull);
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
