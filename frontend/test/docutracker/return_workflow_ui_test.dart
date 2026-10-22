import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_returned_info_card.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_content_lock.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_history_presentation.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_return_text.dart';

DocumentHistoryEntry _returned({
  required DateTime at,
  String? actor = 'Maria Santos',
  String? remarks,
}) {
  return DocumentHistoryEntry(
    id: 'h-${at.millisecondsSinceEpoch}',
    documentId: 'doc-1',
    action: 'returned',
    actorName: actor,
    fromStep: 2,
    toStep: 1,
    fromStatus: DocumentStatus.inReview,
    toStatus: DocumentStatus.returned,
    remarks: remarks,
    createdAt: at,
  );
}

final _misleading = RegExp(
  r'correct|resubmit|sender|for changes|changes are required',
  caseSensitive: false,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required ThemeMode mode,
  DocumentHistoryEntry? entry,
  String? returnedTo = 'Juan Dela Cruz',
  String nextAction = 'Next action text',
  double width = 640,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: DocuTrackerReturnedInfoCard(
              returnEntry: entry,
              returnedTo: returnedTo,
              currentStep: 'Step 1 - Department Review',
              nextAction: nextAction,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Return labels', () {
    test('describe a move to the previous workflow step', () {
      expect(docuTrackerReturnButtonLabel, 'Return to Previous Step');
      expect(docuTrackerReturnTooltip, contains('previous workflow step'));
      expect(
        docuTrackerReturnTooltip,
        contains('reviewer becomes responsible'),
      );
      expect(docuTrackerReturnDialogTitle, 'Return to previous step');
      expect(docuTrackerReturnDialogExplanation, contains('read-only'));
      expect(
        docuTrackerReturnDialogExplanation,
        contains('no correction task is created for the author'),
      );
      expect(docuTrackerReturnReasonLabel, contains('optional'));
      expect(docuTrackerReturnSuccessMessage, contains('previous step'));
      for (final text in [
        docuTrackerReturnButtonLabel,
        docuTrackerReturnTooltip,
        docuTrackerReturnDialogTitle,
        docuTrackerReturnSuccessMessage,
      ]) {
        expect(text, isNot(matches(_misleading)), reason: text);
      }
    });

    test('detail screen no longer uses the old Return wording', () {
      final source = File(
        'lib/features/docutracker/presentation/shared/pages/'
        'docutracker_document_detail_screen.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('Send back to sender')));
      expect(source, isNot(contains('Return for Changes')));
      expect(source, contains('docuTrackerReturnTooltip'));
      expect(source, contains('docuTrackerReturnButtonLabel'));
      expect(source, contains('docuTrackerReturnDialogExplanation'));
    });
  });

  group('Returned information', () {
    test('uses the latest return event and its recorded reason', () {
      final older = _returned(
        at: DateTime.utc(2026, 10, 1, 8),
        remarks: 'Older reason',
      );
      final newer = _returned(
        at: DateTime.utc(2026, 10, 2, 9),
        actor: 'Pedro Reyes',
        remarks: '  Attach the signed annex.  ',
      );
      final other = DocumentHistoryEntry(
        documentId: 'doc-1',
        action: 'approved',
        createdAt: DateTime.utc(2026, 10, 3),
      );

      final latest = docuTrackerLatestReturnEntry([older, other, newer]);
      expect(latest, same(newer));
      expect(docuTrackerReturnReasonText(latest), 'Attach the signed annex.');
    });

    test(
      'missing reason reads neutrally and missing history is not invented',
      () {
        expect(
          docuTrackerReturnReasonText(_returned(at: DateTime.utc(2026, 10, 2))),
          'No reason provided.',
        );
        expect(
          docuTrackerReturnReasonText(
            _returned(at: DateTime.utc(2026, 10, 2), remarks: '   '),
          ),
          'No reason provided.',
        );
        expect(docuTrackerLatestReturnEntry(const []), isNull);
        expect(docuTrackerReturnReasonText(null), docuTrackerReturnNotRecorded);
      },
    );

    test('responsible reviewer is told the document is at their step', () {
      final text = docuTrackerReturnedNextAction(
        isResponsibleReviewer: true,
        isCreator: false,
      );
      expect(text, contains('returned to your review step'));
      expect(text, isNot(matches(_misleading)));
    });

    test(
      'creator is told the document is read-only and awaiting a reviewer',
      () {
        final text = docuTrackerReturnedNextAction(
          isResponsibleReviewer: false,
          isCreator: true,
        );
        expect(text, contains('read-only'));
        expect(text, contains('waiting for the reviewer'));
        expect(text, isNot(matches(_misleading)));
      },
    );

    test('returned native content stays locked', () {
      const doc = DocuTrackerDocument(
        id: 'doc-1',
        documentType: 'memo',
        title: 'Memo',
        status: DocumentStatus.returned,
        currentStep: 1,
        currentHolderId: 'reviewer-1',
      );
      expect(docuTrackerNativeContentIsLocked(doc), isTrue);
      expect(
        docuTrackerNativeContentLockMessage(doc),
        'This document is no longer a draft, so its content is read-only.',
      );
    });
  });

  group('Returned info card', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('shows recorded details in ${mode.name} mode', (
        tester,
      ) async {
        final at = DateTime.utc(2026, 10, 2, 9, 30);
        await _pumpCard(
          tester,
          mode: mode,
          entry: _returned(at: at, remarks: 'Attach the signed annex.'),
          nextAction: docuTrackerReturnedNextAction(
            isResponsibleReviewer: false,
            isCreator: true,
          ),
        );

        expect(find.text('Returned to previous step'), findsOneWidget);
        expect(find.text('Maria Santos'), findsOneWidget);
        expect(find.text(docuTrackerHistoryTimestamp(at)), findsOneWidget);
        expect(find.text('Attach the signed annex.'), findsOneWidget);
        expect(find.text('Juan Dela Cruz'), findsOneWidget);
        expect(find.text('Step 1 - Department Review'), findsOneWidget);
        expect(find.textContaining('read-only'), findsOneWidget);
        expect(
          find.textContaining(RegExp('resubmit', caseSensitive: false)),
          findsNothing,
        );
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('handles a missing reason in ${mode.name} mode', (
        tester,
      ) async {
        await _pumpCard(
          tester,
          mode: mode,
          entry: _returned(at: DateTime.utc(2026, 10, 2)),
          width: 320,
        );

        expect(find.text('No reason provided.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not invent details when history is unavailable', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        mode: ThemeMode.light,
        entry: null,
        returnedTo: null,
      );

      expect(find.text(docuTrackerReturnNotRecorded), findsNWidgets(3));
      expect(find.text('Not assigned'), findsOneWidget);
      expect(find.text('Maria Santos'), findsNothing);
    });
  });
}
