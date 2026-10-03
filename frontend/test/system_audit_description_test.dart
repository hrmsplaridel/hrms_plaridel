import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/system_audit_description.dart';

void main() {
  test(
    'explains a DTR permission change and names the affected administrator',
    () {
      final event = describeAuditEntry({
        'action': 'dtr_admin_access_changed',
        'entity_type': 'user',
        'entity_id': 'uuid-1',
        'target_name': 'Maria Santos',
        'actor_name': 'System Administrator',
        'details': {
          'before': {'reports_allowed': false, 'manage_allowed': true},
          'after': {'reports_allowed': true, 'manage_allowed': true},
        },
      });
      expect(event.title, 'DTR access changed');
      expect(event.summary, contains('Report access granted'));
      expect(event.target, 'Maria Santos');
      expect(event.changes, ['Report access: Off → On']);
    },
  );

  test('page views and account access use plain language', () {
    final view = describeAuditEntry({
      'action': 'audit_log_viewed',
      'entity_type': 'audit_logs',
      'details': '{"page":2,"limit":50,"action":"dtr"}',
    });
    expect(view.title, 'Audit log viewed');
    expect(view.summary, contains('page 2'));
    final access = describeAuditEntry({
      'action': 'account_creation_access_changed',
      'details': {'previous_allowed': false, 'allowed': true},
    });
    expect(access.summary, contains('granted'));
  });

  test('unknown actions and malformed details remain readable', () {
    final event = describeAuditEntry({
      'action': 'new_custom_action',
      'entity_type': 'policy_assignment',
      'details': '{broken',
    });
    expect(event.title, 'New custom action');
    expect(event.summary, 'Policy assignment');
    expect(event.changes, isEmpty);
  });
}
