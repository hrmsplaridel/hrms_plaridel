import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/habitual_attendance_report.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/pages/habitual_attendance_page.dart';

Map<String, dynamic> _metric(List<int> monthly, bool habitual) => {
  'monthly': monthly,
  'qualifying_months': [
    for (var i = 0; i < monthly.length; i++)
      if (monthly[i] >= 10) i + 1,
  ],
  'habitual': habitual,
};

final _payload = <String, dynamic>{
  'year': 2026,
  'through': '2026-04-15',
  'threshold': 10,
  'employees': [
    {
      'employee_id': 'a',
      'employee_name': 'Ana Late',
      'tardiness': _metric([0, 10, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0], true),
      'undertime': _metric(List.filled(12, 0), false),
    },
    {
      'employee_id': 'b',
      'employee_name': 'Ben Once',
      'tardiness': _metric([11, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], false),
      'undertime': _metric(List.filled(12, 0), false),
    },
  ],
};

Widget _host(HabitualAttendanceLoader loader) => MaterialApp(
  home: HabitualAttendancePage(
    loader: loader,
    initialYear: 2026,
    departments: const [DepartmentOption(id: 'd1', name: 'Treasury')],
  ),
);

void main() {
  test('parses the habitual attendance report', () {
    final report = HabitualAttendanceReport.fromJson(_payload);
    expect(report.year, 2026);
    expect(report.threshold, 10);
    expect(report.employees, hasLength(2));
    final ana = report.employees.first;
    expect(ana.employeeName, 'Ana Late');
    expect(ana.tardiness.habitual, isTrue);
    expect(ana.tardiness.qualifyingMonths, [2, 3]);
    expect(ana.tardiness.monthly[2], 12);
    expect(ana.isHabitual, isTrue);
    expect(report.employees.last.isHabitual, isFalse);
  });

  testWidgets('shows habitual and warning employees for the year', (
    tester,
  ) async {
    final calls = <(int, String?)>[];
    await tester.pumpWidget(
      _host((year, departmentId) async {
        calls.add((year, departmentId));
        return HabitualAttendanceReport.fromJson(_payload);
      }),
    );
    await tester.pumpAndSettle();

    expect(calls, [(2026, null)]);
    expect(find.text('Ana Late'), findsOneWidget);
    expect(find.text('Habitual tardiness'), findsOneWidget);
    expect(find.text('Ben Once'), findsOneWidget);
    expect(find.text('Warning: 1 month'), findsOneWidget);
  });

  testWidgets('shows an empty message when nobody qualifies', (tester) async {
    await tester.pumpWidget(
      _host(
        (_, _) async => HabitualAttendanceReport.fromJson({
          ..._payload,
          'employees': <dynamic>[],
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No employee reached 10 instances'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error with retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _host((_, _) async {
        attempts += 1;
        if (attempts == 1) throw Exception('offline');
        return HabitualAttendanceReport.fromJson(_payload);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Late'), findsOneWidget);
  });
}
