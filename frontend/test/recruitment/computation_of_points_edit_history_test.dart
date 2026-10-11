import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_rsp_signature_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/computation_of_points_section.dart';

void main() {
  test('computation of points keeps the screen score formula', () {
    final source = File(
      'lib/features/recruitment/presentation/admin/sections/computation_of_points_section.dart',
    ).readAsStringSync();
    expect(source.contains("_ScoreCriterion('education', 'Education', 25)"), isTrue);
    expect(source.contains("_ScoreCriterion('eligibility', 'Eligibility', 20)"), isTrue);
    expect(source.contains("_ScoreCriterion('experience', 'Experience', 15)"), isTrue);
    expect(source.contains("_ScoreCriterion('training', 'Training', 10)"), isTrue);
    expect(source.contains("_ScoreCriterion('performance', 'Performance', 10)"), isTrue);
    expect(source.contains("_ScoreCriterion('potential', 'Potential', 10)"), isTrue);
    expect(
      source.contains("_ScoreCriterion('workAttitude', 'Work Attitude', 10)"),
      isTrue,
    );
    expect(source.contains('sum += v.clamp(0, c.max)'), isTrue);
    expect(source.contains("row['total']!.text = sum.toStringAsFixed(2)"), isTrue);
    expect(source.contains('signatureStatus: _signatureStatus'), isTrue);
    expect(source.contains('View edit history'), isTrue);
    expect(source.contains('showLockedIndicator'), isFalse);
    expect(source.contains('readOnly: _signatureStatus'), isFalse);
  });

  test('computation PDF uses the real signer and does not invent an official name', () {
    final source = File('lib/core/utils/form_pdf.dart').readAsStringSync();
    final start = source.indexOf(
      'static Future<pw.Document> buildComputationOfPointsPdf',
    );
    final end = source.indexOf(
      'static Future<pw.Document> buildWorkExperienceSheetPdf',
    );
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body.contains('MARCELO'), isFalse);
    expect(body.contains('CAÑARES'), isFalse);
    expect(body.contains('WILMAMAE'), isFalse);
    expect(body.contains('Administrative Officer V'), isFalse);
    expect(body.contains('_signatureName'), isTrue);
    expect(body.contains('_signatureImage'), isTrue);
    expect(body.contains("signatureFor('prepared_by')"), isTrue);
  });

  test('Applicants Profile and Selection Line-Up history wiring stays in place', () {
    final profile = File(
      'lib/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart',
    ).readAsStringSync();
    expect(profile.contains('showLockedIndicator: true'), isTrue);
    expect(profile.contains('View edit history'), isTrue);
    expect(profile.contains('SelectionLineupEntry.tableName'), isTrue);
    final lock = File(
      '../backend/src/services/applicantsProfileSignatureLock.js',
    ).readAsStringSync();
    expect(lock.contains('APPLICANTS_PROFILE_LOCKED'), isTrue);
    expect(lock.contains('computation_of_points'), isFalse);
    final lineup = File(
      '../backend/src/services/selectionLineupEditAudit.js',
    ).readAsStringSync();
    expect(lineup.contains('selection_lineup_content_edited'), isTrue);
    expect(lineup.contains('computation_of_points'), isFalse);
  });

  testWidgets('edit history shows the candidate, criterion, and signing state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComputationOfPointsEditHistoryView(
            edits: [
              {
                'edited_at': '2026-10-11T02:00:00.000Z',
                'edited_by_name': 'Form Creator',
                'signed_when_edited': true,
                'changes': [
                  {
                    'candidate': 'Ana Cruz',
                    'label': 'Education',
                    'previous': '20',
                    'next': '25',
                    'value_kind': 'entered',
                  },
                  {
                    'candidate': 'Ana Cruz',
                    'label': 'Total',
                    'previous': '20.00',
                    'next': '25.00',
                    'value_kind': 'calculated',
                  },
                ],
              },
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Form Creator'), findsOneWidget);
    expect(
      find.textContaining(
        'Edited after signature. The signature was kept and does not approve this revision.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ana Cruz · Education: 20 → 25'), findsOneWidget);
    expect(
      find.text('Ana Cruz · Total (calculated): 20.00 → 25.00'),
      findsOneWidget,
    );
  });

  testWidgets('signature status shows the DocuTracker state without a lock chip', (
    tester,
  ) async {
    Future<void> expectStatus(String status, String label) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocuTrackerRspSignatureSection(
              sourceTable: 'computation_of_points_entries',
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
