/// Step 6: Escalation rules - configurable by admin per document type and department.
class EscalationConfig {
  const EscalationConfig({
    this.id,
    required this.documentType,
    this.departmentId,
    this.escalationTargetRole,
    this.escalationDelayMinutes = 60,
    this.maxEscalationLevel = 3,
    this.notifyOriginalSender = true,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String documentType;
  final String? departmentId;
  /// Role to escalate to (e.g. dept_head, admin)
  final String? escalationTargetRole;
  /// Minutes after deadline before escalating
  final int escalationDelayMinutes;
  final int maxEscalationLevel;
  final bool notifyOriginalSender;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'docutracker_escalation_configs';

  factory EscalationConfig.fromJson(Map<String, dynamic> json) {
    return EscalationConfig(
      id: json['id']?.toString(),
      documentType: json['document_type'] as String? ?? 'memo',
      departmentId: json['department_id']?.toString(),
      escalationTargetRole: json['escalation_target_role']?.toString(),
      escalationDelayMinutes:
          (json['escalation_delay_minutes'] as num?)?.toInt() ?? 60,
      maxEscalationLevel:
          (json['max_escalation_level'] as num?)?.toInt() ?? 3,
      notifyOriginalSender: json['notify_original_sender'] != false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'document_type': documentType,
        if (departmentId != null) 'department_id': departmentId,
        if (escalationTargetRole != null)
          'escalation_target_role': escalationTargetRole,
        'escalation_delay_minutes': escalationDelayMinutes,
        'max_escalation_level': maxEscalationLevel,
        'notify_original_sender': notifyOriginalSender,
        'updated_at': DateTime.now().toIso8601String(),
      };
}
