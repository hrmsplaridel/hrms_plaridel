import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';

/// Immutable configuration change recorded by the DocuTracker backend.
class DocuTrackerGovernanceAuditEntry {
  const DocuTrackerGovernanceAuditEntry({
    required this.id,
    required this.actorId,
    required this.eventType,
    required this.entityType,
    required this.createdAt,
    this.actorName,
    this.entityId,
    this.documentType,
    this.workflowVersion,
    this.targetUserId,
    this.targetUserName,
    this.targetRoleId,
    this.beforeState,
    this.afterState,
    this.reason,
  });

  final String id;
  final String actorId;
  final String? actorName;
  final String eventType;
  final String entityType;
  final String? entityId;
  final String? documentType;
  final int? workflowVersion;
  final String? targetUserId;
  final String? targetUserName;
  final String? targetRoleId;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final String? reason;
  final DateTime? createdAt;

  factory DocuTrackerGovernanceAuditEntry.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? mapValue(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    return DocuTrackerGovernanceAuditEntry(
      id: json['id']?.toString() ?? '',
      actorId: json['actor_id']?.toString() ?? '',
      actorName: json['actor_name']?.toString(),
      eventType: json['event_type']?.toString() ?? 'configuration_updated',
      entityType: json['entity_type']?.toString() ?? 'configuration',
      entityId: json['entity_id']?.toString(),
      documentType: json['document_type']?.toString(),
      workflowVersion: (json['workflow_version'] as num?)?.toInt(),
      targetUserId: json['target_user_id']?.toString(),
      targetUserName: json['target_user_name']?.toString(),
      targetRoleId: json['target_role_id']?.toString(),
      beforeState: mapValue(json['before_state']),
      afterState: mapValue(json['after_state']),
      reason: json['reason']?.toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  String get actorLabel =>
      actorName?.trim().isNotEmpty == true ? actorName!.trim() : 'System';

  DocuTrackerAuditCategory get category =>
      DocuTrackerAuditCategory.forEvent(eventType);

  /// Who an access rule applies to: an employee or a role.
  String? get targetLabel {
    if (targetUserName?.trim().isNotEmpty == true) {
      return targetUserName!.trim();
    }
    if (targetUserId != null) return 'An employee';
    final role = targetRoleId ?? _stateValue('role_id');
    return role == null ? null : _roleLabel(role);
  }

  String get documentScopeLabel => docuTrackerAuditScopeLabel(documentType);

  String get title => switch (eventType) {
    'permission_saved' => 'Access rule changed',
    'permission_reset' => 'Access rule removed',
    'workflow_published' => 'Workflow published',
    'step_assignees_updated' => 'Step assignees updated',
    'escalation_created' => 'Escalation settings created',
    'escalation_updated' => 'Escalation settings updated',
    'source_signer_assigned' => 'Source signer assigned',
    'source_signed' => 'Source document signed',
    'source_signature_replaced' => 'Source signature replaced',
    'official_signatory_configured' => 'Official signatory configured',
    'official_signatory_corrected' => 'Official signatory corrected',
    _ => _humanize(eventType),
  };

  /// One-line, plain-language description of what changed.
  String get summary {
    switch (eventType) {
      case 'permission_saved':
        final action = _actionLabel(_stateValue('action'));
        final before = _grantedLabel(_grantedFrom(beforeState));
        final after = _grantedLabel(_grantedFrom(afterState));
        return '${targetLabel ?? 'Rule'} · $action · $documentScopeLabel: '
            '$before → $after';
      case 'permission_reset':
        final action = _actionLabel(_stateValue('action'));
        return '${targetLabel ?? 'Rule'} · $action · $documentScopeLabel: '
            'was ${_grantedLabel(_grantedFrom(beforeState))}, now inherits';
      case 'workflow_published':
        final version = workflowVersion == null ? '' : ' v$workflowVersion';
        return '$documentScopeLabel workflow$version is now live';
      case 'step_assignees_updated':
        final assignees = afterState?['assignees'];
        final count = assignees is List ? assignees.length : null;
        return count == null
            ? 'Workflow step reviewers were changed'
            : '$count reviewer${count == 1 ? '' : 's'} assigned to a workflow step';
      case 'escalation_created' || 'escalation_updated':
        return 'Overdue escalation rules for $documentScopeLabel';
      case 'source_signer_assigned' ||
          'source_signed' ||
          'source_signature_replaced':
        return '${_sourceLabel(entityType)} source signature'
            '${targetLabel == null ? '' : ' · $targetLabel'}';
      case 'official_signatory_configured' || 'official_signatory_corrected':
        return 'Official signatory settings were updated';
    }
    return [
      if (documentType != null) documentScopeLabel,
      _humanize(entityType),
    ].join(' · ');
  }

  /// Field-level differences between the before and after snapshots.
  List<DocuTrackerAuditChange> get changes {
    final before = beforeState ?? const <String, dynamic>{};
    final after = afterState ?? const <String, dynamic>{};
    const hidden = {'id', 'updated_at', 'created_at'};
    final keys = <String>{...before.keys, ...after.keys}
      ..removeWhere(hidden.contains);
    final out = <DocuTrackerAuditChange>[];
    for (final key in keys.toList()..sort()) {
      final oldValue = before[key];
      final newValue = after[key];
      if (beforeState != null &&
          afterState != null &&
          '$oldValue' == '$newValue') {
        continue;
      }
      out.add(
        DocuTrackerAuditChange(
          field: _fieldLabel(key),
          before: beforeState == null ? null : _valueLabel(key, oldValue),
          after: afterState == null ? null : _valueLabel(key, newValue),
        ),
      );
    }
    return out;
  }

  String? _stateValue(String key) {
    final value = afterState?[key] ?? beforeState?[key] ?? _firstRule()?[key];
    return value?.toString();
  }

  Map<String, dynamic>? _firstRule() {
    final rules = beforeState?['rules'];
    if (rules is List && rules.isNotEmpty && rules.first is Map) {
      return Map<String, dynamic>.from(rules.first as Map);
    }
    return null;
  }

  bool? _grantedFrom(Map<String, dynamic>? state) {
    if (state == null) return null;
    final direct = state['granted'];
    if (direct is bool) return direct;
    final rules = state['rules'];
    if (rules is List && rules.isNotEmpty && rules.first is Map) {
      final granted = (rules.first as Map)['granted'];
      if (granted is bool) return granted;
    }
    return null;
  }
}

class DocuTrackerAuditChange {
  const DocuTrackerAuditChange({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final String? before;
  final String? after;
}

enum DocuTrackerAuditCategory {
  access('Access rules', {'permission_saved', 'permission_reset'}),
  workflow('Workflows', {'workflow_published', 'step_assignees_updated'}),
  escalation('Escalations', {'escalation_created', 'escalation_updated'}),
  signature('Signatures', {
    'source_signer_assigned',
    'source_signed',
    'source_signature_replaced',
    'official_signatory_configured',
    'official_signatory_corrected',
  }),
  other('Other', <String>{});

  const DocuTrackerAuditCategory(this.label, this.eventTypes);

  final String label;
  final Set<String> eventTypes;

  static DocuTrackerAuditCategory forEvent(String eventType) =>
      values.firstWhere(
        (category) => category.eventTypes.contains(eventType),
        orElse: () => other,
      );
}

String docuTrackerAuditScopeLabel(String? documentType) {
  final value = documentType?.trim() ?? '';
  if (value.isEmpty) return 'DocuTracker';
  if (value == '*') return 'All document types';
  return switch (value) {
    'dtr' => 'DTR',
    'ld' => 'L&D',
    'rsp' => 'RSP',
    _ => DocumentType.fromValue(value).displayName,
  };
}

String _roleLabel(String roleId) => switch (roleId) {
  'admin' => 'Administrator',
  'hr' || 'hr_staff' => 'HR',
  'supervisor' || 'dept_head' => 'Supervisor',
  'employee' => 'Employee',
  'mayor' => 'Mayor',
  _ => _humanize(roleId),
};

String _actionLabel(String? action) => switch (action) {
  'view' => 'Open related documents',
  'create' || 'create_draft' => 'Create document drafts',
  'submit' => 'Submit own drafts',
  'download' => 'Download attachments',
  null => 'Access',
  _ => _humanize(action),
};

String _grantedLabel(bool? granted) => switch (granted) {
  true => 'Allowed',
  false => 'Blocked',
  null => 'Not set',
};

String _sourceLabel(String entityType) {
  if (entityType.startsWith('rsp')) return 'RSP';
  if (entityType.startsWith('ld')) return 'L&D';
  if (entityType.startsWith('dtr')) return 'DTR';
  return 'Source';
}

String _fieldLabel(String key) => switch (key) {
  'role_id' => 'Role',
  'user_id' => 'Employee',
  'document_type' => 'Document type',
  'action' => 'Permission',
  'granted' => 'Access',
  'rules' => 'Rules',
  'assignees' => 'Assignees',
  'version' || 'workflow_version' => 'Workflow version',
  _ => _humanize(key),
};

String _valueLabel(String key, Object? value) {
  if (value == null) return '—';
  return switch (key) {
    'granted' when value is bool => _grantedLabel(value),
    'role_id' => _roleLabel(value.toString()),
    'action' => _actionLabel(value.toString()),
    'document_type' => docuTrackerAuditScopeLabel(value.toString()),
    _ when value is List =>
      '${value.length} item${value.length == 1 ? '' : 's'}',
    _ when value is Map =>
      '${value.length} field${value.length == 1 ? '' : 's'}',
    _ => value.toString(),
  };
}

String _humanize(String value) {
  final text = value.replaceAll('_', ' ').trim();
  if (text.isEmpty) return value;
  return text[0].toUpperCase() + text.substring(1);
}
