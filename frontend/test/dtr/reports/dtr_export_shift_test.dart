import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';

void main() {
  test('PM-only absence uses the shift column and scheduled duration', () {
    final date = DateTime(2024, 7, 1);

    final html = DtrExport.generateWordHtmlSync(
      employeeName: 'PM Employee',
      year: date.year,
      month: date.month,
      start: date,
      end: date,
      recordsByDate: const {},
      officialHours: '06:00PM-07:00PM',
      scheduledWorkHoursPerDay: 1,
      punchMode: 'pm_only',
      workingDays: const [DateTime.monday],
      assignmentEffectiveFrom: date,
    );

    expect(
      html,
      contains(
        '<tr><td>1 Mon</td>'
        '<td class="center" style="color:#E65100;"></td>'
        '<td class="center" style="color:#E65100;"></td>'
        '<td class="center" style="color:#E65100;">ABSENT</td>'
        '<td class="center" style="color:#E65100;"></td>'
        '<td class="right" style="color:#E65100;">1</td>'
        '<td class="right" style="color:#E65100;">0</td></tr>',
      ),
    );
  });

  test('combined policy adds late to the official undertime column only', () {
    final date = DateTime(2026, 8, 14);
    final record = TimeRecord(
      userId: 'employee-1',
      recordDate: date,
      breakIn: DateTime(2026, 8, 14, 16, 41),
      timeOut: DateTime(2026, 8, 14, 17, 36),
      lateMinutes: 216,
      undertimeMinutes: 240,
      status: 'incomplete',
      combineLateAndUndertime: true,
    );

    final html = DtrExport.generateWordHtmlSync(
      employeeName: 'Combined Employee',
      year: date.year,
      month: date.month,
      start: date,
      end: date,
      recordsByDate: {date: record},
      scheduledWorkHoursPerDay: 8,
      workingDays: const [DateTime.friday],
      assignmentEffectiveFrom: date,
    );

    expect(
      html,
      contains(
        '<td class="right">7</td><td class="right">36</td>',
      ),
    );
  });
}
