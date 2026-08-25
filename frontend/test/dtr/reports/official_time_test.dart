import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/official_time.dart';

void main() {
  group('official Philippine report time', () {
    test('converts UTC timestamps to UTC+8', () {
      final timestamp = DateTime.parse('2026-08-14T00:00:00Z');

      expect(formatOfficialPhilippineTime(timestamp), '8:00 AM');
    });

    test('preserves an explicit Asia/Manila timestamp', () {
      final timestamp = DateTime.parse('2026-08-14T08:15:00+08:00');

      expect(formatOfficialPhilippineTime(timestamp), '8:15 AM');
    });

    test('moves late UTC timestamps to the next Philippine date', () {
      final timestamp = DateTime.parse('2026-08-14T20:30:00Z');
      final official = toOfficialPhilippineTime(timestamp);

      expect(official.year, 2026);
      expect(official.month, 8);
      expect(official.day, 15);
      expect(formatOfficialPhilippineTime(timestamp), '4:30 AM');
    });

    test('preserves offset-less official wall-clock values', () {
      final timestamp = DateTime.parse('2026-08-14T16:41:00');

      expect(formatOfficialPhilippineTime(timestamp), '4:41 PM');
    });

    test('supports the compact lowercase print format', () {
      final timestamp = DateTime.parse('2026-08-14T09:05:00Z');

      expect(
        formatOfficialPhilippineTime(
          timestamp,
          lowercasePeriod: true,
          padHour: true,
        ),
        '05:05pm',
      );
    });

    test('uses the requested placeholder for a missing timestamp', () {
      expect(formatOfficialPhilippineTime(null, emptyValue: '-'), '-');
    });
  });
}
