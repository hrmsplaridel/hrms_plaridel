import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/ojt_work_immersion_evaluation_section.dart';

const _linkedId = '11111111-2222-4333-8444-555555555555';

OjtWorkImmersionEvaluation _assignedEntry({
  String? ojtImmersion = 'Juan Dela Cruz',
  String? school = 'Plaridel National High School',
}) {
  return OjtWorkImmersionEvaluation(
    id: _linkedId,
    ojtImmersion: ojtImmersion,
    school: school,
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required OjtWorkImmersionEvaluation entry,
  bool applicantOnly = false,
  bool readOnly = false,
  Size surface = const Size(1400, 5200),
  void Function(OjtWorkImmersionEvaluation entry)? onSave,
  Future<void> Function(OjtWorkImmersionEvaluation entry)? onPreview,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OjtWorkImmersionEvaluationEditor(
          entry: entry,
          readOnly: readOnly,
          applicantOnly: applicantOnly,
          onSave: onSave ?? (_) {},
          onCancel: () {},
          onPreview: onPreview,
          onPrint: (_) async {},
          onDownloadPdf: (_) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _labeledField(String label) {
  return find.byWidgetPredicate((widget) {
    if (widget is! TextField) return false;
    return widget.decoration?.labelText == label;
  });
}

Finder _scoreInks() {
  return find.byWidgetPredicate((widget) {
    if (widget is! InkWell) return false;
    final child = widget.child;
    if (child is! Container) return false;
    final box = child.constraints;
    return box != null && box.minWidth == 44 && box.minHeight == 40;
  });
}

void main() {
  test('assigned OJT json with empty HR evaluation fields parses', () {
    final entry = OjtWorkImmersionEvaluation.fromJson({
      'id': _linkedId,
      'ojt_immersion': 'Juan Dela Cruz',
      'school': 'Plaridel National High School',
      'interview_date': null,
      'problem_solving_score': null,
      'problem_solving_notes': null,
      'communication_score': null,
      'communication_notes': null,
      'teamwork_score': null,
      'teamwork_notes': null,
      'adaptability_score': null,
      'adaptability_notes': null,
      'overall_recommendation': null,
      'key_strengths': null,
      'key_concerns': null,
      'interviewer': null,
    });
    expect(entry.id, _linkedId);
    expect(entry.ojtImmersion, 'Juan Dela Cruz');
    expect(entry.school, 'Plaridel National High School');
    expect(entry.interviewDate, isNull);
    expect(entry.problemSolvingScore, isNull);
    expect(entry.totalScore, isNull);
    expect(entry.interviewer, isNull);
  });

  test('applicant page submits OJT fields and does not open admin preview', () {
    final source = File(
      'lib/features/recruitment/presentation/applicant/pages/applicant_required_form_page.dart',
    ).readAsStringSync();
    expect(source.contains('openFormDocumentPreview'), isFalse);
    expect(source.contains('FormPdf.buildOjtWorkImmersionEvaluationPdf'), isFalse);
    expect(source.contains('onPreview'), isFalse);
    expect(source.contains("'school': entry.school"), isTrue);
    expect(source.contains("'problem_solving_notes': entry.problemSolvingNotes"), isTrue);
    expect(source.contains("'communication_notes': entry.communicationNotes"), isTrue);
    expect(source.contains("'teamwork_notes': entry.teamworkNotes"), isTrue);
    expect(source.contains("'adaptability_notes': entry.adaptabilityNotes"), isTrue);
    expect(source.contains('problem_solving_score'), isFalse);
    expect(source.contains('ApplicantBiFormHost'), isTrue);
  });

  testWidgets('applicant OJT renders the full form from applicant fields only', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      entry: _assignedEntry(),
      applicantOnly: true,
    );

    expect(find.text('Juan Dela Cruz'), findsWidgets);
    expect(find.text('APPLICANT / INTERVIEW INFORMATION'), findsOneWidget);
    expect(find.text('RATING SCALE'), findsOneWidget);
    expect(
      find.textContaining('Unsatisfactory', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Exceptional', findRichText: true),
      findsOneWidget,
    );
    for (var n = 1; n <= 4; n++) {
      expect(find.text('CRITERION $n'), findsOneWidget);
    }
    expect(find.text('Problem Solving and Decision Making'), findsOneWidget);
    expect(find.text('Communication and Clarity'), findsOneWidget);
    expect(find.text('Teamwork and Collaboration'), findsOneWidget);
    expect(find.text('Adaptability and Resilience'), findsOneWidget);
    expect(find.text('SUMMARY AND RECOMMENDATIONS'), findsOneWidget);
    expect(find.text('TOTAL SCORE'), findsOneWidget);
    expect(find.text('— / 20'), findsOneWidget);
    expect(find.text('INTERVIEWER SIGNATURE'), findsNothing);
    expect(find.text('Submit to HR'), findsOneWidget);
    expect(find.text('Preview Form'), findsNothing);
    expect(find.text('New Evaluation'), findsNothing);
    expect(find.text('Save Evaluation'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('View Records'), findsNothing);
    expect(find.text('Print Form'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Request Revision'), findsNothing);
    expect(find.byTooltip('PDF'), findsNothing);
    expect(find.byTooltip('Pick date'), findsNothing);

    final date = tester.widget<TextField>(_labeledField('Date of Interview'));
    expect(date.readOnly, isTrue);
    expect(date.controller?.text, isEmpty);
    expect(date.onTap, isNull);

    final ojt = tester.widget<TextField>(_labeledField('OJT / Immersion'));
    final school = tester.widget<TextField>(_labeledField('School'));
    expect(ojt.readOnly, isTrue);
    expect(school.readOnly, isFalse);

    final notes = tester.widgetList<TextField>(_labeledField('Evidence / Notes'));
    expect(notes, hasLength(4));
    expect(notes.every((field) => field.readOnly), isFalse);

    final strengths = tester.widget<TextField>(_labeledField('Key Strengths'));
    final concerns = tester.widget<TextField>(_labeledField('Key Concerns'));
    final recommendation = tester.widget<TextField>(
      _labeledField('Overall Recommendation'),
    );
    expect(strengths.readOnly, isTrue);
    expect(concerns.readOnly, isTrue);
    expect(recommendation.readOnly, isTrue);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    final scores = tester.widgetList<InkWell>(_scoreInks());
    expect(scores, hasLength(20));
    expect(scores.every((ink) => ink.onTap == null), isTrue);
  });

  testWidgets('applicant OJT still renders when every HR value is null', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      entry: OjtWorkImmersionEvaluation.fromJson(const {
        'id': _linkedId,
        'ojt_immersion': null,
        'school': null,
        'interview_date': null,
      }),
      applicantOnly: true,
    );

    expect(find.text('New OJT / Work Immersion Evaluation'), findsOneWidget);
    expect(find.text('Date of Interview'), findsOneWidget);
    expect(find.text('CRITERION 4'), findsOneWidget);
    expect(find.text('— / 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow applicant layout does not index past the info fields', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      entry: _assignedEntry(),
      applicantOnly: true,
      surface: const Size(480, 5200),
    );

    expect(find.text('Date of Interview'), findsOneWidget);
    expect(find.text('RATING SCALE'), findsOneWidget);
    expect(find.text('CRITERION 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applicant can type evidence notes, and those values submit', (
    tester,
  ) async {
    OjtWorkImmersionEvaluation? submitted;
    await _pumpEditor(
      tester,
      entry: _assignedEntry(),
      applicantOnly: true,
      onPreview: (_) async {},
      onSave: (entry) {
        submitted = entry;
      },
    );

    expect(find.text('Preview Form'), findsNothing);
    expect(find.text('Submit to HR'), findsOneWidget);

    final ojt = tester.widget<TextField>(_labeledField('OJT / Immersion'));
    final school = tester.widget<TextField>(_labeledField('School'));
    expect(ojt.readOnly, isTrue);
    expect(school.readOnly, isFalse);
    expect(ojt.controller?.text, 'Juan Dela Cruz');
    expect(school.controller?.text, 'Plaridel National High School');

    await tester.enterText(
      _labeledField('School'),
      'Plaridel Community College',
    );
    await tester.pump();

    final notes = _labeledField('Evidence / Notes');
    final noteFields = tester.widgetList<TextField>(notes).toList();
    expect(noteFields, hasLength(4));
    const answers = [
      'Solved the assigned case',
      'Explained the answer clearly',
      'Worked with the group',
      'Adjusted when the task changed',
    ];
    for (var i = 0; i < noteFields.length; i++) {
      await tester.enterText(notes.at(i), answers[i]);
      await tester.pump();
    }

    await tester.tap(_scoreInks().first);
    await tester.pump();
    expect(
      tester.widgetList<InkWell>(_scoreInks()).every((ink) => ink.onTap == null),
      isTrue,
    );
    expect(find.text('— / 20'), findsOneWidget);

    await tester.tap(find.text('Submit to HR'));
    await tester.pump();
    expect(submitted?.id, _linkedId);
    expect(submitted?.ojtImmersion, 'Juan Dela Cruz');
    expect(submitted?.school, 'Plaridel Community College');
    expect(submitted?.problemSolvingNotes, answers[0]);
    expect(submitted?.communicationNotes, answers[1]);
    expect(submitted?.teamworkNotes, answers[2]);
    expect(submitted?.adaptabilityNotes, answers[3]);
    expect(submitted?.problemSolvingScore, isNull);
    expect(submitted?.overallRecommendation, isNull);
    expect(submitted?.keyStrengths, isNull);
    expect(submitted?.interviewer, isNull);
  });

  testWidgets('HR reopens the same OJT record with editable evaluation fields', (
    tester,
  ) async {
    OjtWorkImmersionEvaluation? saved;
    await _pumpEditor(
      tester,
      entry: _assignedEntry(),
      onSave: (entry) {
        saved = entry;
      },
      onPreview: (_) async {},
    );

    expect(find.text('Juan Dela Cruz'), findsWidgets);
    expect(find.text('Plaridel National High School'), findsOneWidget);
    expect(find.text('INTERVIEWER SIGNATURE'), findsOneWidget);
    expect(find.text('Save Evaluation'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Preview Form'), findsOneWidget);
    expect(find.text('Print Form'), findsOneWidget);
    expect(find.byTooltip('PDF'), findsOneWidget);
    expect(find.byTooltip('Pick date'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    final notes = tester.widgetList<TextField>(_labeledField('Evidence / Notes'));
    expect(notes.every((field) => field.readOnly), isFalse);
    final scores = tester.widgetList<InkWell>(_scoreInks());
    expect(scores, hasLength(20));
    expect(scores.every((ink) => ink.onTap != null), isTrue);

    await tester.tap(_scoreInks().first);
    await tester.pump();
    expect(find.text('1 / 20'), findsOneWidget);
    expect(find.text('Submit to HR'), findsNothing);

    await tester.tap(find.text('Save Evaluation'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Date of interview is required.'), findsOneWidget);
    expect(find.text('Score every criterion from 1 to 5.'), findsOneWidget);
  });

  testWidgets('admin OJT section still opens a new evaluation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 5200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RspOjtWorkImmersionEvaluationSection())),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('New Evaluation'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.tap(find.text('New Evaluation'));
    await tester.pump();
    expect(find.text('Save Evaluation'), findsOneWidget);
    expect(find.text('APPLICANT / INTERVIEW INFORMATION'), findsOneWidget);
    expect(find.byTooltip('Pick date'), findsOneWidget);
  });

  testWidgets('background investigation applicant host still renders', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplicantBiFormHost(
            entry: const BiFormEntry(
              applicantName: 'Ana Cruz',
              respondentName: 'Unit Supervisor',
              respondentRelationship: 'supervisor',
            ),
            readOnly: false,
            onPersist: (_) async {},
            onSubmitToHr: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ana Cruz'), findsWidgets);
    expect(
      find.text('Applicant background investigation and competency assessment'),
      findsOneWidget,
    );
    expect(find.text('Next Page'), findsOneWidget);
    expect(find.text('Problem Solving and Decision Making'), findsNothing);
    expect(find.text('Save Evaluation'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
