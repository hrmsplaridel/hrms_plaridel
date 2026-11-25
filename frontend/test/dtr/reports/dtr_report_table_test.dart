import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_formatting.dart';
import 'package:hrms_plaridel/features/dtr/reports/presentation/widgets/dtr_report_table.dart';

TimeRecord _record(Map<String, dynamic> json) => TimeRecord.fromJson({
  'id': 'r-${json['record_date']}',
  'user_id': 'employee',
  ...json,
});

void main() {
  test('formatting helpers', () {
    expect(formatDtrReportDate(DateTime(2026, 12, 2)), '2 Wed');
    expect(formatDtrMinutes(null), '—');
    expect(formatDtrMinutes(0), '—');
    expect(formatDtrMinutes(15), '15 min');
    expect(formatDtrMinutesOrHours(90, showMinutes: true), '90 min');
    expect(formatDtrMinutesOrHours(90, showMinutes: false), '1.50 hrs');
    expect(formatDtrMinutesOrHours(120, showMinutes: false), '2 hrs');
    expect(formatDtrMinutesOrHours(0, showMinutes: false), '0 hrs');
    expect(formatDtrEquivalentDay(0.125), '0.125');
    expect(formatDtrEquivalentDay(1), '1');
    expect(
      dtrReportRowRemark(
        record: null,
        isQuietPlaceholder: false,
        isMissingScheduledWorkDay: true,
      ),
      'Absent',
    );
    expect(
      dtrReportRowRemark(
        record: _record({'record_date': '2026-12-02', 'status': 'late'}),
        isQuietPlaceholder: false,
        isMissingScheduledWorkDay: false,
      ),
      'Late',
    );
  });

  testWidgets('table lists each date with punches, late and undertime', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dec1 = DateTime(2026, 12, 1);
    final dec2 = DateTime(2026, 12, 2);
    final records = {
      dec1: _record({
        'record_date': '2026-12-01',
        'status': 'late',
        'time_in': '2026-12-01T08:15:00+08:00',
        'break_out': '2026-12-01T12:00:00+08:00',
        'break_in': '2026-12-01T13:00:00+08:00',
        'time_out': '2026-12-01T16:30:00+08:00',
        'late_minutes': 15,
        'undertime_minutes': 30,
      }),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: DtrReportTable(
              end: dec2,
              recordsByDate: records,
              sortedDates: [dec1, dec2],
              showMinutesFormat: true,
              shiftPunchMode: 'full_day',
              reportLoading: false,
              statsInclusiveEnd: dec2,
              isScheduledWorkDay: (_) => true,
              assignmentEffectiveFrom: dec1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 Tue'), findsOneWidget);
    expect(find.text('2 Wed'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
