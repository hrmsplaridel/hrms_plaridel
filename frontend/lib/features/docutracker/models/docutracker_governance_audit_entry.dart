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
      targetRoleId: json['target_role_id']?.toString(),
      beforeState: mapValue(json['before_state']),
      afterState: mapValue(json['after_state']),
      reason: json['reason']?.toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}
