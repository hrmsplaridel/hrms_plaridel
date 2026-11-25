import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_summary_card.dart';

void main() {
  late List<String> calls;
  late int equivalentDayCalls;

  setUp(() {
    calls = [];
    equivalentDayCalls = 0;
  });

  Widget card({
    bool loading = false,
    bool actionsEnabled = true,
    bool hideCounts = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DtrReportSummaryCard(
            loading: loading,
            selectedName: 'Ana Cruz',
            periodLabel: 'December, 2026',
            workingDays: 21,
            absentCount: 1,
            totalLateMinutes: 90,
            totalUndertimeMinutes: 0,
            hideCounts: hideCounts,
            showMinutesFormat: true,
            onShowMinutesFormatChanged: (value) => calls.add('minutes:$value'),
            resolveEquivalentDay: () {
              equivalentDayCalls += 1;
              return 0.188;
            },
            actionsEnabled: actionsEnabled,
            onPreview: () => calls.add('preview'),
            onPrint: () => calls.add('print'),
            onExportPdf: () => calls.add('pdf'),
            onExportWord: () => calls.add('word'),
            onExportExcel: () => calls.add('excel'),
            fullWidth: true,
          ),
        ),
      ),
    );
  }

  testWidgets('shows totals and the equivalent day', (tester) async {
    await tester.pumpWidget(card());
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('December, 2026'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('90 min'), findsOneWidget);
    expect(find.text('Equivalent Day: 0.188'), findsOneWidget);
    expect(equivalentDayCalls, greaterThan(0));
  });

  testWidgets('hides counts while attendance is unverified', (tester) async {
    await tester.pumpWidget(card(hideCounts: true));
    expect(find.text('21'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('toggle, preview, print and export call back to the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(card());
    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tapText('Hrs');
    await tapText('PREVIEW');
    await tapText('PRINT CURRENT');
    await tapText('GENERATE');
    await tester.tap(find.text('Word (.doc)'));
    await tester.pumpAndSettle();
    expect(calls, ['minutes:false', 'preview', 'print', 'word']);
  });

  testWidgets('actions are disabled when the official report is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(card(actionsEnabled: false));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'PREVIEW'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'PRINT CURRENT'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('loading shows a skeleton without computing totals', (
    tester,
  ) async {
    await tester.pumpWidget(card(loading: true));
    expect(find.text('Ana Cruz'), findsNothing);
    expect(equivalentDayCalls, 0);
  });
}
