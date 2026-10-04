import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_governance_audit_entry.dart';

void main() {
  test(
    'parses governance audit payloads without losing before and after states',
    () {
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
    },
  );

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

  test('describes a role access change in plain language', () {
    final entry = DocuTrackerGovernanceAuditEntry.fromJson({
      'id': 'audit-3',
      'actor_id': 'admin-1',
      'actor_name': 'System Admin',
      'event_type': 'permission_saved',
      'entity_type': 'permission',
      'document_type': '*',
      'target_role_id': 'employee',
      'before_state': {
        'id': 'p1',
        'action': 'create_draft',
        'granted': true,
        'role_id': 'employee',
        'document_type': '*',
        'updated_at': '2026-08-27T04:09:51.948Z',
      },
      'after_state': {
        'id': 'p1',
        'action': 'create_draft',
        'granted': false,
        'role_id': 'employee',
        'document_type': '*',
        'updated_at': '2026-09-30T23:46:29.286Z',
      },
    });

    expect(entry.title, 'Access rule changed');
    expect(entry.category, DocuTrackerAuditCategory.access);
    expect(
      entry.summary,
      'Employee · Create document drafts · All document types: '
      'Allowed → Blocked',
    );
    final changes = entry.changes;
    expect(changes, hasLength(1));
    expect(changes.single.field, 'Access');
    expect(changes.single.before, 'Allowed');
    expect(changes.single.after, 'Blocked');
  });

  test('names the employee for personal exceptions and resets', () {
    final entry = DocuTrackerGovernanceAuditEntry.fromJson({
      'id': 'audit-4',
      'actor_id': 'admin-1',
      'event_type': 'permission_reset',
      'entity_type': 'permission',
      'document_type': 'memo',
      'target_user_id': 'u-1',
      'target_user_name': 'Tope Reyes',
      'before_state': {'action': 'submit', 'granted': true, 'user_id': 'u-1'},
    });

    expect(entry.title, 'Access rule removed');
    expect(entry.actorLabel, 'System');
    expect(
      entry.summary,
      'Tope Reyes · Submit own drafts · Memo: was Allowed, now inherits',
    );
  });

  test('summarizes workflow publishing with its version', () {
    final entry = DocuTrackerGovernanceAuditEntry.fromJson({
      'id': 'audit-5',
      'actor_id': 'admin-1',
      'event_type': 'workflow_published',
      'entity_type': 'workflow_version',
      'document_type': 'memo',
      'workflow_version': 13,
    });

    expect(entry.category, DocuTrackerAuditCategory.workflow);
    expect(entry.summary, 'Memo workflow v13 is now live');
  });

  test(
    'signature replacements and signatory corrections are signature events',
    () {
      for (final (eventType, title) in [
        ('source_signature_replaced', 'Source signature replaced'),
        ('official_signatory_corrected', 'Official signatory corrected'),
      ]) {
        final entry = DocuTrackerGovernanceAuditEntry.fromJson({
          'id': 'audit-$eventType',
          'actor_id': 'admin-1',
          'event_type': eventType,
          'entity_type': 'idp_entries',
        });

        expect(entry.category, DocuTrackerAuditCategory.signature);
        expect(entry.title, title);
        expect(
          DocuTrackerAuditCategory.signature.eventTypes,
          contains(eventType),
        );
      }
    },
  );
}
