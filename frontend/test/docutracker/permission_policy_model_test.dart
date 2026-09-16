import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_permission_policy.dart';

void main() {
  test('permission policy parses role, override, and effective decisions', () {
    final policy = DocuTrackerPermissionPolicy.fromJson({
      'document_type': 'memo',
      'actions': ['view'],
      'role_defaults': [
        {
          'role_id': 'employee',
          'permissions': {
            'view': {'granted': true, 'source': 'all_document_types'},
          },
        },
      ],
      'selected_user': {
        'id': 'user-1',
        'full_name': 'Test Employee',
        'role': 'employee',
      },
      'user_overrides': {'view': false},
      'inherited_user_overrides': {'view': true},
      'effective': {
        'view': {'granted': false, 'source': 'explicit_permission'},
      },
      'updated_at': '2026-09-14T13:00:00.000Z',
    });

    expect(policy.documentType, 'memo');
    expect(policy.roleDefaults.single.permissions['view']?.granted, true);
    expect(policy.userOverrides['view'], false);
    expect(policy.inheritedUserOverrides['view'], true);
    expect(policy.effective['view']?.granted, false);
    expect(policy.updatedAt, isNotNull);
  });
}
