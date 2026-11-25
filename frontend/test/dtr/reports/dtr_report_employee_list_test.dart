import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_employee_list.dart';

const _ana = EmployeeOption(id: 'a', fullName: 'Ana Cruz', employeeNumber: 7);
const _ben = EmployeeOption(id: 'b', fullName: 'Ben Reyes', employeeNumber: 8);

void main() {
  late List<String> calls;

  setUp(() => calls = []);

  Widget host({
    bool multiSelect = false,
    Set<String> checked = const {},
    bool compact = false,
    bool loading = false,
  }) {
    const employees = [_ana, _ben];
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 500,
          child: DtrReportEmployeeList(
            loading: loading,
            employees: employees,
            selectedEmployeeId: 'a',
            checkedEmployeeIds: checked,
            multiSelectMode: multiSelect,
            toolbar: DtrEmployeeSelectionToolbar(
              employees: employees,
              selectedEmployeeIds: checked,
              multiSelectMode: multiSelect,
              bulkExportBusy: false,
              bulkExportPrepared: 0,
              bulkExportTotal: 0,
              onSelectAll: () => calls.add('all'),
              onClear: () => calls.add('clear'),
              onExit: () => calls.add('exit'),
              compact: compact,
            ),
            onEmployeeTap: (e) => calls.add('tap:${e.id}'),
            onCheckedChanged: (id, value) => calls.add('check:$id:$value'),
            compact: compact,
          ),
        ),
      ),
    );
  }

  for (final compact in [false, true]) {
    testWidgets('${compact ? 'compact' : 'side'} list taps an employee', (
      tester,
    ) async {
      await tester.pumpWidget(host(compact: compact));
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('Exit multi-select (Esc)'), findsNothing);
      await tester.tap(find.text('Ben Reyes'));
      expect(calls, ['tap:b']);
    });
  }

  testWidgets('multi-select shows checkboxes and the toolbar', (tester) async {
    await tester.pumpWidget(host(multiSelect: true, checked: {'a'}));
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).last);
    await tester.tap(find.byTooltip('Select all filtered employees'));
    await tester.tap(find.byTooltip('Clear selected employees'));
    await tester.tap(find.byTooltip('Exit multi-select (Esc)'));
    expect(calls, ['check:b:true', 'all', 'clear', 'exit']);
  });

  testWidgets('loading shows a skeleton instead of names', (tester) async {
    await tester.pumpWidget(host(loading: true));
    expect(find.text('Ana Cruz'), findsNothing);
  });
}
