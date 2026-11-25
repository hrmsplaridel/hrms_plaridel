import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_official_hours.dart';

String fmt(String start, String end) => '$start-$end';

void main() {
  test('regular schedule keeps the shift hours', () {
    expect(
      reportOfficialHours(
        startTime: '08:00:00',
        endTime: '17:00:00',
        scheduleOverrides: const [
          {'date': '2026-12-05', 'is_working_day': true},
        ],
        format: fmt,
      ),
      '08:00:00-17:00:00',
    );
  });

  test('any duty roster day marks the hours as per roster', () {
    expect(
      reportOfficialHours(
        startTime: '08:00:00',
        endTime: '17:00:00',
        scheduleOverrides: const [
          {
            'date': '2026-12-02',
            'is_working_day': true,
            'shift_id': 'night',
            'start_time': '22:00:00',
            'end_time': '06:00:00',
          },
        ],
        format: fmt,
      ),
      dutyRosterOfficialHours,
    );
  });

  test('missing shift times give no official hours', () {
    expect(
      reportOfficialHours(
        startTime: null,
        endTime: '17:00:00',
        scheduleOverrides: null,
        format: fmt,
      ),
      isNull,
    );
  });
}
