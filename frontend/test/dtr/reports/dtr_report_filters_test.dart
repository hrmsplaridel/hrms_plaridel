import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_filters.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'filters preserve self-service restrictions at mobile=$mobile',
      (tester) async {
        tester.view.physicalSize = Size(mobile ? 420 : 1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final search = TextEditingController();
        addTearDown(search.dispose);
        final calls = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DtrReportFilters(
                  isMobile: mobile,
                  selfService: true,
                  searchController: search,
                  departments: const [],
                  selectedDepartmentId: null,
                  selectedEmployeeStatus: 'Active',
                  selectedMonth: 2,
                  selectedYear: 2026,
                  availableReportYears: const [2026],
                  rangeStartDay: 1,
                  rangeEndDay: 28,
                  selectedCount: 0,
                  bulkExportBusy: false,
                  bulkExportPrepared: 0,
                  bulkExportTotal: 0,
                  officialActionsEnabled: false,
                  hasUnverifiedBulkAttendance: false,
                  onSearchChanged: (_) {},
                  onDepartmentChanged: (_) {},
                  onEmployeeStatusChanged: (_) {},
                  onMonthChanged: (v) => calls.add('month:$v'),
                  onYearChanged: (_) {},
                  onRangeStartChanged: (_) {},
                  onRangeEndChanged: (_) {},
                  onReset: () => calls.add('reset'),
                  onBulkPrint: () {},
                  onBulkExport: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Current employee status'), findsNothing);
        expect(find.text('All departments'), findsNothing);
        expect(find.text('Bulk print'), findsNothing);
        expect(find.text('Habitual tardiness'), findsNothing);
        final months = find.byWidgetPredicate(
          (w) =>
              w is DropdownButton<int> &&
              w.items!.any(
                (i) => i.child is Text && (i.child as Text).data == 'February',
              ),
        );
        tester.widget<DropdownButton<int>>(months).onChanged!(3);
        await tester.tap(find.widgetWithText(OutlinedButton, 'RESET'));
        expect(calls, ['month:3', 'reset']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
