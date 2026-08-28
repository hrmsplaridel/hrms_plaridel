import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_governance_audit_entry.dart';

void main() {
  test('parses governance audit payloads without losing before and after states', () {
    final entry = DocuTrackerGovernanceAuditEntry.fromJson({
      'id': 'audit-1',
      'actor_id': 'user-1',
      'actor_name': 'Admin User',
      'event_type': 'workflow_published',
      'entity_type': 'workflow_version',
      'entity_id': 'memo:2',
      'document_type': 'memo',
      'workflow_version': 2,
      'before_state': {'version': 1},
      'after_state': {'version': 2, 'steps': 3},
      'created_at': '2026-08-27T08:30:00.000Z',
    });

    expect(entry.id, 'audit-1');
    expect(entry.actorName, 'Admin User');
    expect(entry.workflowVersion, 2);
    expect(entry.beforeState, {'version': 1});
    expect(entry.afterState, {'version': 2, 'steps': 3});
    expect(entry.createdAt, DateTime.parse('2026-08-27T08:30:00.000Z'));
  });

  test('handles nullable audit values safely', () {
    final entry = DocuTrackerGovernanceAuditEntry.fromJson({
      'id': 'audit-2',
      'actor_id': 'user-2',
      'event_type': 'permission_saved',
      'entity_type': 'permission',
    });

    expect(entry.documentType, isNull);
    expect(entry.beforeState, isNull);
    expect(entry.afterState, isNull);
    expect(entry.createdAt, isNull);
  });
}
