import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/turn_around_time_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vacancy selection fills position and leaves applicants empty', () {
    final entry = turnAroundTimeEntryFromVacancy(
      position: ' IT Coder ',
      noOfVacantPosition: '10',
      endSearch: 'October 22, 2026',
      qualificationStandard: 'Education: Bachelor degree',
    );

    expect(entry.position, 'IT Coder');
    expect(entry.noOfVacantPosition, '10');
    expect(entry.endSearch, 'October 22, 2026');
    expect(entry.qs, 'Education: Bachelor degree');
    expect(entry.applicants, isEmpty);
  });

  test('qualification standard prints one item on each underline', () {
    expect(
      turnAroundQsLines(
        'Education: Grade 12\nExperience: 2 yrs relevant experience',
      ),
      [
        'Education: Grade 12',
        'Experience: 2 yrs relevant experience',
      ],
    );
    expect(
      turnAroundQsLines(
        'Education: Grade 12 Experience: 2 yrs Training: 72 hours',
      ),
      [
        'Education: Grade 12',
        'Experience: 2 yrs',
        'Training: 72 hours',
      ],
    );
    expect(turnAroundQsLines('  '), isEmpty);
  });

  test('a selected position keeps only applications for that position title', () {
    const rows = [
      {
        'id': '006b730a-a9c3-4a98-bfcc-3242ae7b7605',
        'full_name': 'Lord Wampipti',
        'position_applied_for': 'IT Coder',
      },
      {
        'id': '11111111-2222-4333-8444-555555555555',
        'full_name': 'Other Applicant',
        'position_applied_for': 'Documenter',
      },
    ];

    final matched = [
      for (final row in rows)
        if (tatApplicationMatchesSelectedPosition(row, 'it coder')) row['id'],
    ];
    expect(matched, ['006b730a-a9c3-4a98-bfcc-3242ae7b7605']);
    expect(
      rows.where((row) => tatApplicationMatchesSelectedPosition(row, '')).length,
      2,
    );
  });

  test('applicant search text includes name, number, and position', () {
    final text = tatApplicantChoiceSearchText(
      name: 'Lord Wampipti',
      applicantNumber: 'PLR-LORD1234',
      position: 'IT Coder',
      statusLabel: 'Exam Passed',
    );
    expect(text, contains('lord wampipti'));
    expect(text, contains('plr-lord1234'));
    expect(text, contains('it coder'));
  });

  test('the same application id cannot be added twice', () {
    const id = '006b730a-a9c3-4a98-bfcc-3242ae7b7605';
    final existing = [
      {'application_id': id, 'name': 'Lord Wampipti'},
    ];

    expect(tatApplicantIdAlreadyTracked(existing, id.toUpperCase()), isTrue);
    expect(tatApplicantIdAlreadyTracked(existing, ''), isFalse);
    expect(
      tatApplicantIdAlreadyTracked(
        const [
          {'name': 'Typed only'},
        ],
        id,
      ),
      isFalse,
    );
  });

  Future<List<TurnAroundTimeEntry>> pumpEditor(
    WidgetTester tester,
    TurnAroundTimeEntry entry, {
    Future<List<Map<String, dynamic>>> Function()? loadLinkableApplications,
  }) async {
    final saved = <TurnAroundTimeEntry>[];
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TurnAroundTimeEditor(
              entry: entry,
              loadLinkableApplications: loadLinkableApplications ??
                  () async => const [],
              onSave: saved.add,
              onCancel: () {},
              onPrint: (_) async {},
              onDownloadPdf: (_) async {},
            ),
          ),
        ),
      ),
    );
    return saved;
  }

  testWidgets('a new form starts with the manual applicant empty state', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      const TurnAroundTimeEntry(position: 'IT Coder'),
    );

    expect(find.text('IT Coder'), findsWidgets);
    expect(find.text('Lord Wampipti'), findsNothing);
    expect(
      find.text(
        'No applicants added yet. Click Add Applicant to manually include applicants in this Turn-Around Time form.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 Applicants'), findsOneWidget);
  });

  testWidgets('Add Applicant keeps a typed name and a selected application id', (
    tester,
  ) async {
    const applicationId = '006b730a-a9c3-4a98-bfcc-3242ae7b7605';
    final saved = await pumpEditor(
      tester,
      const TurnAroundTimeEntry(position: 'IT Coder', office: 'IT Office'),
      loadLinkableApplications: () async => [
        {
          'id': applicationId,
          'full_name': 'Lord Wampipti',
          'applicant_number': 'PLR-LORD1234',
          'position_applied_for': 'IT Coder',
          'status': 'passed',
        },
      ],
    );

    await tester.ensureVisible(find.text('Add Applicant'));
    await tester.tap(find.text('Add Applicant'));
    await tester.pumpAndSettle();

    final applicationField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search name, applicant number, or position',
    );
    await tester.enterText(applicationField, 'plr-lord');
    await tester.pump();
    await tester.tap(find.text('Lord Wampipti · PLR-LORD1234 · IT Coder · Exam Passed').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Applicant'));
    await tester.pumpAndSettle();

    expect(find.text('Lord Wampipti'), findsWidgets);
    expect(find.text('1 Applicant'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saved.single.applicants.single.name, 'Lord Wampipti');
    expect(saved.single.applicants.single.applicationId, applicationId);
    expect(saved.single.position, 'IT Coder');
  });

  testWidgets('a typed applicant is saved without an application id', (
    tester,
  ) async {
    final saved = await pumpEditor(
      tester,
      const TurnAroundTimeEntry(position: 'Clerk', office: 'HR'),
    );

    await tester.ensureVisible(find.text('Add Applicant'));
    await tester.tap(find.text('Add Applicant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name of Applicant'), 'Manual Applicant');
    await tester.tap(find.text('Save Applicant'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saved.single.applicants.single.name, 'Manual Applicant');
    expect(saved.single.applicants.single.applicationId, isNull);
  });

  testWidgets('changing position keeps a manually added applicant', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      const TurnAroundTimeEntry(
        position: 'IT Coder',
        office: 'IT Office',
        applicants: [
          TurnAroundTimeApplicant(
            applicationId: '006b730a-a9c3-4a98-bfcc-3242ae7b7605',
            name: 'Lord Wampipti',
          ),
        ],
      ),
    );

    final position = tester.widget<TextFormField>(
      find.ancestor(
        of: find.text('Position *'),
        matching: find.byType(TextFormField),
      ),
    );
    position.controller!.text = 'Administrative Officer II';
    await tester.pump();

    expect(find.text('Lord Wampipti'), findsOneWidget);
    expect(find.text('1 Applicant'), findsOneWidget);
  });

  testWidgets('removing an applicant clears that row', (tester) async {
    await pumpEditor(
      tester,
      const TurnAroundTimeEntry(
        applicants: [TurnAroundTimeApplicant(name: 'Manual Applicant')],
      ),
    );

    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Manual Applicant'), findsNothing);
    expect(find.text('0 Applicants'), findsOneWidget);
  });

  testWidgets('selecting the same application twice does not add a duplicate', (
    tester,
  ) async {
    const applicationId = '006b730a-a9c3-4a98-bfcc-3242ae7b7605';
    await pumpEditor(
      tester,
      const TurnAroundTimeEntry(
        position: 'IT Coder',
        applicants: [
          TurnAroundTimeApplicant(
            applicationId: applicationId,
            name: 'Lord Wampipti',
          ),
        ],
      ),
      loadLinkableApplications: () async => [
        {
          'id': applicationId,
          'full_name': 'Lord Wampipti',
          'applicant_number': 'PLR-LORD1234',
          'position_applied_for': 'IT Coder',
          'status': 'passed',
        },
      ],
    );

    await tester.ensureVisible(find.text('Add Applicant'));
    await tester.tap(find.text('Add Applicant'));
    await tester.pumpAndSettle();
    final applicationField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search name, applicant number, or position',
    );
    await tester.enterText(applicationField, 'plr-lord');
    await tester.pump();
    await tester.tap(find.text('Lord Wampipti · PLR-LORD1234 · IT Coder · Exam Passed').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Applicant'));
    await tester.pumpAndSettle();

    expect(find.text('This applicant is already on the form.'), findsOneWidget);
    expect(find.text('1 Applicant'), findsOneWidget);
  });

  testWidgets('a different position is not offered for selection', (tester) async {
    await pumpEditor(
      tester,
      const TurnAroundTimeEntry(position: 'Documenter', office: 'IT'),
      loadLinkableApplications: () async => [
        {
          'id': '006b730a-a9c3-4a98-bfcc-3242ae7b7605',
          'full_name': 'Lord Wampipti',
          'applicant_number': 'PLR-LORD1234',
          'position_applied_for': 'IT Coder',
          'status': 'passed',
        },
      ],
    );

    await tester.ensureVisible(find.text('Add Applicant'));
    await tester.tap(find.text('Add Applicant'));
    await tester.pumpAndSettle();

    expect(find.text('No matching applicants.'), findsOneWidget);
    expect(find.text('Lord Wampipti'), findsNothing);
  });
}
