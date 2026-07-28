import 'package:flutter_test/flutter_test.dart';
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
}
