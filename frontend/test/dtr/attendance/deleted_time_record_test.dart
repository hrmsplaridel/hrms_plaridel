import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';

void main() {
  test('deleted time record exposes active deletion state', () {
    final record = DeletedTimeRecord.fromJson({
      'id': 'deletion-1',
      'deleted_dtr_summary_id': 'summary-1',
      'employee_id': 'employee-1',
      'attendance_date': '2026-06-16',
      'source': 'system',
      'reason': 'Incorrect biometric identification',
      'deleted_at': '2026-08-14T03:00:00.000Z',
      'employee_name': 'Employee One',
      'deleted_by_name': 'Admin User',
    });

    expect(record.recordDate, DateTime(2026, 6, 16));
    expect(record.isRestored, isFalse);
    expect(record.reason, 'Incorrect biometric identification');
  });

  test('deleted time record exposes restoration audit state', () {
    final record = DeletedTimeRecord.fromJson({
      'id': 'deletion-1',
      'deleted_dtr_summary_id': 'summary-1',
      'employee_id': 'employee-1',
      'attendance_date': '2026-06-16',
      'source': 'system',
      'reason': 'Incorrect biometric identification',
      'deleted_at': '2026-08-14T03:00:00.000Z',
      'restored_at': '2026-08-14T04:00:00.000Z',
      'restored_by_name': 'Admin User',
      'restoration_reason': 'Deletion targeted the wrong employee',
    });

    expect(record.isRestored, isTrue);
    expect(record.restoredByName, 'Admin User');
    expect(record.restorationReason, 'Deletion targeted the wrong employee');
  });
}
