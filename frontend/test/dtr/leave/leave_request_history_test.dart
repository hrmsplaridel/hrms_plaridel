import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request_history.dart';

void main() {
  test('maps a persisted return event without inventing approval steps', () {
    final entry = LeaveRequestHistoryEntry.fromJson({
      'id': 'history-1',
      'leave_request_id': 'request-1',
      'action': 'department_head_returned',
      'from_status': 'pending_department_head',
      'to_status': 'returned',
      'acted_by': 'reviewer-1',
      'actor_name': 'Department Head',
      'actor_role': 'department_head',
      'acted_at': '2026-09-14T08:30:00Z',
      'remarks': 'Correct the inclusive dates.',
      'metadata_json': {'number_of_days': 2},
    });

    expect(entry.actionLabel, 'Returned by Department Head');
    expect(entry.actorLabel, 'Department Head');
    expect(entry.fromStatus, 'pending_department_head');
    expect(entry.toStatus, 'returned');
    expect(entry.remarks, 'Correct the inclusive dates.');
  });

  test('maps resubmission as its own workflow event', () {
    final entry = LeaveRequestHistoryEntry.fromJson({
      'id': 'history-2',
      'leave_request_id': 'request-1',
      'action': 'resubmitted',
      'to_status': 'pending_department_head',
      'acted_at': '2026-09-15T01:00:00Z',
    });

    expect(entry.actionLabel, 'Resubmitted');
    expect(entry.actorLabel, 'System');
  });
}
