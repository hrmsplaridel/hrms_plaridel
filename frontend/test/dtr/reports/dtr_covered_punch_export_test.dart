import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 9, 1);

  test(
    'partial locator export preserves an uncovered clock-out without clock-ins',
    () async {
      final row = TimeRecord(
        userId: 'employee',
        recordDate: date,
        status: 'present',
        breakOut: DateTime.parse('2026-09-01T12:00:00+08:00'),
        locatorSlipId: 'locator',
        locatorSlipSegments: const ['AM IN', 'PM IN', 'PM OUT'],
        lateMinutes: 0,
        undertimeMinutes: 0,
      );
      final word = DtrExport.generateWordHtmlSync(
        employeeName: 'Employee',
        year: 2026,
        month: 9,
        start: date,
        end: date,
        recordsByDate: {date: row},
        reportableThrough: date,
      );
      expect(word, contains('12:00 PM'));
      expect(word, contains('ON FIELD'));
      final bytes = await DtrExport.generateExcel(
        employeeName: 'Employee',
        year: 2026,
        month: 9,
        start: date,
        end: date,
        recordsByDate: {date: row},
        reportableThrough: date,
        signatories: DtrExportSignatories.empty,
      );
      final text = Excel.decodeBytes(bytes).tables.values
          .expand((sheet) => sheet.rows)
          .expand((row) => row)
          .map((cell) => cell?.value.toString() ?? '')
          .join('\n');
      expect(text, contains('12:00 PM'));
      expect(text, contains('ON FIELD'));
    },
  );

  for (final status in ['on_leave', 'holiday', 'on_field']) {
    test(
      'full $status projection prints coverage instead of biometric times',
      () {
        final row = TimeRecord(
          userId: 'employee',
          recordDate: date,
          status: status,
          leaveTypeName: status == 'on_leave' ? 'Sick Leave' : null,
          holidayName: status == 'holiday' ? 'Local Holiday' : null,
          coverage: status == 'holiday' ? 'whole_day' : null,
          locatorSlipId: status == 'on_field' ? 'locator' : null,
          locatorSlipSegments: status == 'on_field'
              ? const ['AM IN', 'AM OUT', 'PM IN', 'PM OUT']
              : null,
          lateMinutes: 0,
          undertimeMinutes: 0,
        );
        final word = DtrExport.generateWordHtmlSync(
          employeeName: 'Employee',
          year: 2026,
          month: 9,
          start: date,
          end: date,
          recordsByDate: {date: row},
          reportableThrough: date,
        );
        expect(
          word.toUpperCase(),
          contains(
            status == 'on_leave'
                ? 'SICK LEAVE'
                : status == 'holiday'
                ? 'LOCAL HOLIDAY'
                : 'ON FIELD',
          ),
        );
        expect(word, isNot(contains('8:15 AM')));
      },
    );
  }
}
