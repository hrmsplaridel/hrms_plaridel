import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_workflow_event.dart';

void main() {
  test('parses persisted locator workflow events', () {
    final event = LocatorWorkflowEvent.fromJson({
      'id': 'event-1',
      'action': 'hr_rejected',
      'title': 'Rejected by HR',
      'from_status': 'pending_hr',
      'to_status': 'rejected_by_hr',
      'actor_id': 'actor-1',
      'actor_name': 'HR Reviewer',
      'actor_role': 'hr',
      'remarks': 'Missing supporting document.',
      'created_at': '2026-08-12T08:30:00.000Z',
    });

    expect(event.title, 'Rejected by HR');
    expect(event.actorName, 'HR Reviewer');
    expect(event.remarks, 'Missing supporting document.');
    expect(event.createdAt, DateTime.utc(2026, 8, 12, 8, 30));
  });

  test('normalizes blank optional values to null', () {
    final event = LocatorWorkflowEvent.fromJson({
      'id': 'event-2',
      'action': 'submitted',
      'title': 'Submitted',
      'actor_name': ' ',
      'remarks': '',
    });

    expect(event.actorName, isNull);
    expect(event.remarks, isNull);
    expect(event.createdAt, isNull);
  });
}
