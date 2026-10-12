import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/turn_around_time_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<TurnAroundTimeEntry>> pumpEditor(
    WidgetTester tester,
    TurnAroundTimeEntry entry,
  ) async {
    final saved = <TurnAroundTimeEntry>[];
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TurnAroundTimeEditor(
              entry: entry,
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

  Finder labeled(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
  }

  String fieldText(WidgetTester tester, String label) {
    final field = tester.widget<TextFormField>(labeled(label));
    return field.controller?.text ?? '';
  }

  test('table status still follows named applicants and assumption to duty', () {
    expect(tatEntryStatus(const TurnAroundTimeEntry()), 'Draft');
    expect(
      tatEntryStatus(
        const TurnAroundTimeEntry(
          applicants: [TurnAroundTimeApplicant(name: 'Named applicant')],
        ),
      ),
      'In Progress',
    );
    expect(
      tatEntryStatus(
        const TurnAroundTimeEntry(
          applicants: [
            TurnAroundTimeApplicant(
              name: 'Named applicant',
              dateAssumptionToDuty: 'October 1, 2026',
            ),
          ],
        ),
      ),
      'Completed',
    );
  });

  testWidgets('empty text still renders the historical dash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => rspRecordsTextCell(context, '')),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('blank form blocks save when position and office are empty', (
    tester,
  ) async {
    final saved = await pumpEditor(tester, const TurnAroundTimeEntry());

    await save(tester);

    expect(find.text('Position is required.'), findsOneWidget);
    expect(find.text('Office is required.'), findsOneWidget);
    expect(find.text('Position *'), findsOneWidget);
    expect(find.text('Office *'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('create blocks a filled position with a blank office', (
    tester,
  ) async {
    final saved = await pumpEditor(tester, const TurnAroundTimeEntry());
    await tester.enterText(labeled('Position *'), 'Clerk');

    await save(tester);

    expect(find.text('Position is required.'), findsNothing);
    expect(find.text('Office is required.'), findsOneWidget);
    expect(fieldText(tester, 'Position *'), 'Clerk');
    expect(saved, isEmpty);
  });

  testWidgets('create blocks a blank position with a filled office', (
    tester,
  ) async {
    final saved = await pumpEditor(tester, const TurnAroundTimeEntry());
    await tester.enterText(labeled('Office *'), 'Budget Office');

    await save(tester);

    expect(find.text('Position is required.'), findsOneWidget);
    expect(find.text('Office is required.'), findsNothing);
    expect(fieldText(tester, 'Office *'), 'Budget Office');
    expect(saved, isEmpty);
  });

  testWidgets('create blocks whitespace-only position and office', (
    tester,
  ) async {
    final saved = await pumpEditor(tester, const TurnAroundTimeEntry());
    await tester.enterText(labeled('Position *'), '   ');
    await tester.enterText(labeled('Office *'), ' \n ');

    await save(tester);

    expect(find.text('Position is required.'), findsOneWidget);
    expect(find.text('Office is required.'), findsOneWidget);
    expect(fieldText(tester, 'Position *'), '   ');
    expect(saved, isEmpty);
  });

  testWidgets('create allows trimmed position and office', (tester) async {
    final saved = await pumpEditor(tester, const TurnAroundTimeEntry());
    await tester.enterText(labeled('Position *'), '  IT Coder  ');
    await tester.enterText(labeled('Office *'), '  Office of the Municipal Mayor  ');

    await save(tester);

    expect(saved, hasLength(1));
    expect(saved.single.position, 'IT Coder');
    expect(saved.single.office, 'Office of the Municipal Mayor');
    expect(saved.single.id, isNull);
  });

  testWidgets('vacancy prefill keeps position and still requires office', (
    tester,
  ) async {
    const applicant = TurnAroundTimeApplicant(
      applicationId: '006b730a-a9c3-4a98-bfcc-3242ae7b7605',
      name: 'Eligible Applicant',
    );
    final saved = await pumpEditor(
      tester,
      const TurnAroundTimeEntry(
        position: 'IT Coder',
        noOfVacantPosition: '10',
        endSearch: 'October 22, 2026',
        applicants: [applicant],
      ),
    );

    expect(fieldText(tester, 'Position *'), 'IT Coder');
    expect(find.text('Eligible Applicant'), findsOneWidget);

    await save(tester);

    expect(find.text('Office is required.'), findsOneWidget);
    expect(find.text('Position is required.'), findsNothing);
    expect(fieldText(tester, 'Position *'), 'IT Coder');
    expect(find.text('Eligible Applicant'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.enterText(labeled('Position *'), 'Administrative Officer II');
    await tester.enterText(labeled('Office *'), 'Office of the Municipal Mayor');
    await save(tester);

    expect(saved, hasLength(1));
    expect(saved.single.position, 'Administrative Officer II');
    expect(saved.single.office, 'Office of the Municipal Mayor');
    expect(saved.single.noOfVacantPosition, '10');
    expect(saved.single.endSearch, 'October 22, 2026');
    expect(saved.single.applicants.single.applicationId, applicant.applicationId);
    expect(saved.single.applicants.single.name, 'Eligible Applicant');
  });

  testWidgets('edit still saves a historical row with blank position and office', (
    tester,
  ) async {
    const applicant = TurnAroundTimeApplicant(name: 'Code Crafters VI');
    final saved = await pumpEditor(
      tester,
      const TurnAroundTimeEntry(
        id: '3c4d87b9-4eed-420c-aec6-fb02b79f66b5',
        applicants: [applicant],
      ),
    );

    expect(find.text('Position *'), findsNothing);
    expect(find.text('Office *'), findsNothing);
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);

    await save(tester);

    expect(find.text('Position is required.'), findsNothing);
    expect(find.text('Office is required.'), findsNothing);
    expect(saved, hasLength(1));
    expect(saved.single.id, '3c4d87b9-4eed-420c-aec6-fb02b79f66b5');
    expect(saved.single.position, isNull);
    expect(saved.single.office, isNull);
    expect(saved.single.applicants.single.name, 'Code Crafters VI');
  });
}
