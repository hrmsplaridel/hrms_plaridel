const workflowTestCatalog = <Map<String, dynamic>>[
  {
    'id': 'standard',
    'name': 'Standard approval',
    'current_version': 1,
    'is_active': true,
    'steps': ['department', 'hr'],
  },
  {
    'id': 'manual',
    'name': 'Manual Mayor signing',
    'current_version': 1,
    'is_active': true,
    'steps': ['department', 'manual_mayor'],
  },
  {
    'id': 'direct',
    'name': 'Direct Mayor approval',
    'current_version': 1,
    'is_active': true,
    'steps': ['mayor'],
  },
  {
    'id': 'restricted',
    'name': 'Restricted Mayor signing',
    'current_version': 1,
    'is_active': true,
    'steps': ['department', 'manual_mayor'],
    'employment_types': ['permanent', 'casual'],
  },
];
