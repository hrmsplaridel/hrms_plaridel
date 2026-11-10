import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/utils/biometric_attendance_log_parser.dart';

void main() {
  group('BiometricAttendanceLogParser', () {
    test('parses tab-separated DAT content', () {
      final preview = BiometricAttendanceLogParser.parse(
        content: '001\t2026-07-16 08:01:22\t1\t0\t0',
        fileName: 'attendance.dat',
      );

      expect(preview.detectedFormat, 'Tab-separated');
      expect(preview.validParsedRows, 1);
      expect(preview.parsedRows.single.biometricUserId, '001');
    });

    test('parses comma-separated CSV content including quoted fields', () {
      final preview = BiometricAttendanceLogParser.parse(
        content: '001,"2026-07-16 08:01:22",1,0,"work,office"',
        fileName: 'attendance.csv',
      );

      expect(preview.detectedFormat, 'CSV (comma-separated)');
      expect(preview.validParsedRows, 1);
      expect(preview.parsedRows.single.workCode, 'work,office');
    });

    test('parses semicolon-separated text content', () {
      final preview = BiometricAttendanceLogParser.parse(
        content: '001;2026/07/16 08:01:22\n002;2026/07/16 17:02:10',
        fileName: 'attendance.txt',
      );

      expect(preview.detectedFormat, 'CSV (semicolon-separated)');
      expect(preview.validParsedRows, 2);
      expect(preview.uniqueBiometricUserIds, 2);
    });

    test('parses short and full English month names as Manila time', () {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      for (var index = 0; index < months.length; index++) {
        for (final name in [months[index], months[index].substring(0, 3)]) {
          final timestamp = '10 $name 2026 17:00';
          final preview = BiometricAttendanceLogParser.parse(
            content: '010,$timestamp',
            fileName: 'attendance.csv',
          );
          expect(preview.validParsedRows, 1, reason: timestamp);
          expect(preview.invalidRows, 0);
          expect(preview.parsedRows.single.biometricUserId, '010');
          expect(
            preview.parsedRows.single.loggedAt,
            DateTime.utc(2026, index + 1, 10, 9),
            reason: timestamp,
          );
        }
      }
    });

    test(
      'month-name timestamps support AM/PM, seconds and case variations',
      () {
        final preview = BiometricAttendanceLogParser.parse(
          content:
              '10,"10 jAn 2026 5:00:30 PM"\n'
              '10,10 JANUARY 2026 12:00 AM\n'
              '10,10 Jan 2026 12:00 PM\n'
              '10,29 February 2024 08:00:00',
          fileName: 'attendance.csv',
        );
        expect(preview.validParsedRows, 4);
        expect(preview.parsedRows.map((row) => row.loggedAt), [
          DateTime.utc(2026, 1, 10, 9, 0, 30),
          DateTime.utc(2026, 1, 9, 16),
          DateTime.utc(2026, 1, 10, 4),
          DateTime.utc(2024, 2, 29),
        ]);
      },
    );

    test('rejects invalid named dates and ambiguous numeric dates', () {
      const invalidTimestamps = [
        '31 Apr 2026 17:00',
        '29 February 2026 17:00',
        '0 Jan 2026 17:00',
        '32 Jan 2026 17:00',
        '10 Jann 2026 17:00',
        '10 Jan 2026 24:00',
        '10 Jan 2026 17:60',
        '10 Jan 2026 17:00:60',
        '10 Jan 2026 13:00 PM',
        '10 Jan 2026 0:00 AM',
        '01/09/2026 17:00',
        '09/01/2026 17:00',
      ];
      final preview = BiometricAttendanceLogParser.parse(
        content: invalidTimestamps.map((value) => '10,$value').join('\n'),
        fileName: 'attendance.csv',
      );
      expect(preview.validParsedRows, 0);
      expect(preview.invalidRows, invalidTimestamps.length);
    });

    test(
      'mixed named, numeric and offset timestamps keep their exact instants',
      () {
        final preview = BiometricAttendanceLogParser.parse(
          content:
              '10;10 Jan 2026 17:00\n'
              '10;2026-01-10 17:00:00\n'
              '10;2026-01-10T17:00:00+08:00\n'
              '10;2026-01-10T09:00:00Z',
          fileName: 'attendance.txt',
        );
        expect(preview.validParsedRows, 4);
        expect(
          preview.parsedRows.map((row) => row.loggedAt),
          everyElement(DateTime.utc(2026, 1, 10, 9)),
        );
        expect(preview.earliestTimestamp, DateTime.utc(2026, 1, 10, 9));
        expect(preview.latestTimestamp, DateTime.utc(2026, 1, 10, 9));
      },
    );

    test('rejects unsupported and binary content', () {
      expect(
        () => BiometricAttendanceLogParser.parse(
          content: '\u0000\u0001not a text export',
          fileName: 'attendance.dat',
        ),
        throwsFormatException,
      );
    });

    test('counts a header and malformed records as invalid rows', () {
      final preview = BiometricAttendanceLogParser.parse(
        content: 'employee_id,timestamp\n001,invalid\n002,2026-07-16 08:00:00',
        fileName: 'attendance.csv',
      );

      expect(preview.totalNonEmptyRows, 3);
      expect(preview.validParsedRows, 1);
      expect(preview.invalidRows, 2);
    });
  });
}
