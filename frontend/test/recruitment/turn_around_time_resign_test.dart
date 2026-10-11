import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_rsp_signature_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/turn_around_time_section.dart';

void main() {
  test('turn around time stays editable and shows renewal from audit state', () {
    final source = File(
      'lib/features/recruitment/presentation/admin/sections/turn_around_time_section.dart',
    ).readAsStringSync();
    expect(source.contains('signatureStatus: _signatureStatus'), isTrue);
    expect(source.contains('onChanged: _onSignaturesChanged'), isTrue);
    expect(source.contains('View edit history'), isTrue);
    expect(
      source.contains('Signatures need renewal because the form was updated.'),
      isTrue,
    );
    expect(source.contains('tatSignaturesNeedRenewal('), isTrue);
    expect(source.contains('showLockedIndicator'), isFalse);
    expect(source.contains("readOnly: _signatureStatus"), isFalse);
    expect(source.contains('int? _tatDaysBetween('), isTrue);
    expect(source.contains('days.abs().toString()'), isTrue);
    expect(source.contains('static const int _turnAroundRowsPerPage = 5'), isFalse);
    expect(
      tatSignaturesNeedRenewal(
        signatureStatus: 'awaiting_signatures',
        edits: const [
          {'renewal_required': true},
        ],
      ),
      isTrue,
    );
    expect(
      tatSignaturesNeedRenewal(
        signatureStatus: 'completed',
        edits: const [
          {'renewal_required': true},
        ],
      ),
      isFalse,
    );
    expect(
      tatSignaturesNeedRenewal(
        signatureStatus: 'awaiting_signatures',
        edits: const [
          {'renewal_required': false},
        ],
      ),
      isFalse,
    );
  });

  test('turn around time PDF uses current signatures and five rows per page', () {
    final source = File('lib/core/utils/form_pdf.dart').readAsStringSync();
    final start = source.indexOf('static Future<pw.Document> buildTurnAroundTimePdf');
    final end = source.indexOf('static Future<pw.Document> buildTrainingNeedAnalysisPdf');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body.contains('MARCELO'), isFalse);
    expect(body.contains('CAÑARES'), isFalse);
    expect(body.contains('HRMO III'), isFalse);
    expect(body.contains('HRMO Staff'), isFalse);
    expect(body.contains('_signatureName'), isTrue);
    expect(body.contains('_signatureImage'), isTrue);
    expect(body.contains("signatureFor('prepared_by')"), isTrue);
    expect(body.contains("signatureFor('noted_by')"), isTrue);
    expect(source.contains('static const int _turnAroundRowsPerPage = 5'), isTrue);
    expect(body.contains('_turnAroundRowsPerPage'), isTrue);
    final image = source.substring(
      source.indexOf('static pw.Widget _signatureImage'),
      source.indexOf('static pw.Widget _signatureImage') + 500,
    );
    expect(image.contains('if (signature?.isSigned != true)'), isTrue);
  });

  test('Applicants Profile lock and other form history stay in place', () {
    final profile = File(
      'lib/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart',
    ).readAsStringSync();
    expect(profile.contains('showLockedIndicator: true'), isTrue);
    final lock = File(
      '../backend/src/services/applicantsProfileSignatureLock.js',
    ).readAsStringSync();
    expect(lock.contains('APPLICANTS_PROFILE_LOCKED'), isTrue);
    expect(lock.contains('turn_around_time'), isFalse);
    final scoring = File(
      'lib/features/recruitment/presentation/admin/sections/computation_of_points_section.dart',
    ).readAsStringSync();
    expect(scoring.contains("_ScoreCriterion('education', 'Education', 25)"), isTrue);
    expect(scoring.contains('showLockedIndicator'), isFalse);
  });

  testWidgets('edit history shows the revision and the earlier signatures', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TurnAroundTimeEditHistoryView(
            edits: [
              {
                'edited_at': '2026-10-11T04:00:00.000Z',
                'edited_by_name': 'Form Creator',
                'signed_before_edit': true,
                'renewal_required': true,
                'integrity_note':
                    'The names and times below are for the earlier revision, not this one.',
                'changes': [
                  {
                    'applicant': 'Ana Cruz',
                    'label': 'Exam result',
                    'previous': 'Passed',
                    'next': 'Failed',
                  },
                ],
                'signatures_cleared': [
                  {
                    'slot_key': 'prepared_by',
                    'signer_name_snapshot': 'Form Creator',
                    'signed_at': '2026-10-02T01:00:00.000Z',
                  },
                  {
                    'slot_key': 'noted_by',
                    'signer_name_snapshot': 'HRMDO Official',
                    'signed_at': '2026-10-02T02:00:00.000Z',
                  },
                ],
              },
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Form Creator'), findsWidgets);
    expect(
      find.textContaining('belong to the earlier revision'),
      findsOneWidget,
    );
    expect(
      find.textContaining('earlier revision, not this one'),
      findsOneWidget,
    );
    expect(find.text('Ana Cruz · Exam result: Passed → Failed'), findsOneWidget);
    expect(find.textContaining('Earlier Noted by signature: HRMDO Official'), findsOneWidget);
  });

  testWidgets('signature status shows Needs Setup, Awaiting Signatures, and Completed', (
    tester,
  ) async {
    Future<void> expectStatus(String status, String label) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocuTrackerRspSignatureSection(
              sourceTable: 'turn_around_time_entries',
              sourceRecordId: '22222222-2222-4222-8222-222222222222',
              signatureStatus: status,
              slots: const [],
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
    }

    await expectStatus('needs_setup', 'Needs Setup');
    await expectStatus('awaiting_signatures', 'Awaiting Signatures');
    await expectStatus('completed', 'Completed');
  });
}
