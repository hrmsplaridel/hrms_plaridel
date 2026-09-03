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
