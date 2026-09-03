import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';

void main() {
  test('current leave coverage is marked as active', () {
    final record = TimeRecord.fromJson({
      'id': 'summary-1',
      'user_id': 'employee-1',
      'record_date': '2026-06-09',
      'status': 'on_leave',
      'leave_request_id': 'leave-1',
      'leave_coverage_id': 'coverage-1',
      'is_leave_covered': true,
    });

    expect(record.isLeaveCovered, isTrue);
  });

  test('legacy on-leave record is also marked as active', () {
    final record = TimeRecord.fromJson({
      'id': 'summary-1',
      'user_id': 'employee-1',
      'record_date': '2026-06-09',
      'status': 'on_leave',
      'leave_request_id': 'leave-1',
      'leave_coverage_id': null,
    });

    expect(record.isLeaveCovered, isTrue);
  });
}
