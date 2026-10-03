import 'dart:convert';

class AuditDescription {
  const AuditDescription({
    required this.title,
    required this.summary,
    required this.target,
    required this.changes,
  });

  final String title;
  final String summary;
  final String? target;
  final List<String> changes;
}

String auditLabel(String? code) {
  if (code == null || code.trim().isEmpty) return 'Unknown';
  const acronyms = {'dtr': 'DTR', 'hr': 'HR', 'id': 'ID', 'api': 'API'};
  return code
      .trim()
      .split('_')
      .map((part) => acronyms[part.toLowerCase()] ?? part)
      .join(' ');
}

String _title(String? action) {
  const titles = {
    'audit_log_viewed': 'Audit log viewed',
    'dtr_admin_access_changed': 'DTR access changed',
    'account_creation_access_changed': 'Account creation access changed',
  };
  final label = titles[action] ?? auditLabel(action);
  return label.isEmpty
      ? 'Unknown action'
      : '${label[0].toUpperCase()}${label.substring(1)}';
}

Map<String, dynamic>? _details(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    } catch (_) {
      /* Old rows may contain unstructured text. */
    }
  }
  return null;
}

String _field(String key) {
  const labels = {
    'reports_allowed': 'Report access',
    'manage_allowed': 'DTR management',
    'corrections_allowed': 'Corrections',
    'employees_allowed': 'Employees',
    'leave_allowed': 'Leave',
    'approvals_allowed': 'Approvals',
    'locator_allowed': 'Locator slips',
  };
  return labels[key] ?? auditLabel(key);
}

String _value(dynamic value) {
  if (value == true) return 'On';
  if (value == false) return 'Off';
  if (value == null) return 'Empty';
  if (value is Map || value is List) return 'Changed';
  return value.toString();
}

AuditDescription describeAuditEntry(Map<String, dynamic> entry) {
  final action = entry['action']?.toString();
  final details = _details(entry['details']);
  final target =
      (entry['target_name']?.toString().trim().isNotEmpty == true
              ? entry['target_name']
              : entry['target_email']?.toString().trim().isNotEmpty == true
              ? entry['target_email']
              : null)
          ?.toString();
  final before = details?['before'];
  final after = details?['after'];
  final changes = <String>[];
  if (before is Map && after is Map) {
    for (final key in after.keys) {
      if (before[key] != after[key]) {
        changes.add(
          '${_field(key.toString())}: ${_value(before[key])} → ${_value(after[key])}',
        );
      }
    }
  }

  String summary;
  if (action == 'audit_log_viewed') {
    final page = details?['page'];
    summary = page == null
        ? 'An administrator opened the audit log.'
        : 'Viewed audit log page $page.';
  } else if (action == 'dtr_admin_access_changed') {
    if (changes.isEmpty) {
      summary = 'DTR permissions were updated.';
    } else {
      final first = changes.first.split(': ');
      final granted = first.last.endsWith('→ On');
      summary =
          '${first.first} ${granted ? 'granted' : 'removed'}${changes.length > 1 ? ' and ${changes.length - 1} other permission${changes.length == 2 ? '' : 's'} changed' : ''}.';
    }
  } else if (action == 'account_creation_access_changed') {
    final oldValue = details?['previous_allowed'];
    final newValue = details?['allowed'];
    if (oldValue is bool && newValue is bool && oldValue != newValue) {
      changes.add(
        'Account creation: ${_value(oldValue)} → ${_value(newValue)}',
      );
    }
    summary = newValue == true
        ? 'Account creation access granted.'
        : 'Account creation access removed.';
  } else {
    final entity = auditLabel(entry['entity_type']?.toString());
    summary = '${entity[0].toUpperCase()}${entity.substring(1)}';
  }
  return AuditDescription(
    title: _title(action),
    summary: summary,
    target: target,
    changes: changes,
  );
}
