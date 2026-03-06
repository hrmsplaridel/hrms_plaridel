import 'document_status.dart';

/// Step 6 & 9: Audit trail entry - logs actions, overdue, escalation. - logs actions, overdue, escalation.
/// Every document has complete tracking history.
class DocumentHistoryEntry {
  const DocumentHistoryEntry({
    this.id,
    required this.documentId,
    this.action,
    this.actorId,
    this.actorName,
    this.fromStep,
    this.toStep,
    this.fromStatus,
    this.toStatus,
    this.remarks,
    this.isOverdueLog = false,
    this.isEscalationLog = false,
    this.escalationLevel,
    this.createdAt,
  });

  final String? id;
  final String documentId;
  /// Action taken: created, assigned, reviewed, approved, rejected, returned, forwarded, escalated, overdue
  final String? action;
  final String? actorId;
  final String? actorName;
  final int? fromStep;
  final int? toStep;
  final DocumentStatus? fromStatus;
  final DocumentStatus? toStatus;
  final String? remarks;
  final bool isOverdueLog;
  final bool isEscalationLog;
  final int? escalationLevel;
  final DateTime? createdAt;

  static const String tableName = 'docutracker_document_history';

  factory DocumentHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DocumentHistoryEntry(
      id: json['id']?.toString(),
      documentId: json['document_id'] as String? ?? '',
      action: json['action']?.toString(),
      actorId: json['actor_id']?.toString(),
      actorName: json['actor_name']?.toString(),
      fromStep: (json['from_step'] as num?)?.toInt(),
      toStep: (json['to_step'] as num?)?.toInt(),
      fromStatus: documentStatusFromString(json['from_status']?.toString()),
      toStatus: documentStatusFromString(json['to_status']?.toString()),
      remarks: json['remarks']?.toString(),
      isOverdueLog: json['is_overdue_log'] == true,
      isEscalationLog: json['is_escalation_log'] == true,
      escalationLevel: (json['escalation_level'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'document_id': documentId,
        if (action != null) 'action': action,
        if (actorId != null) 'actor_id': actorId,
        if (fromStep != null) 'from_step': fromStep,
        if (toStep != null) 'to_step': toStep,
        if (fromStatus != null) 'from_status': fromStatus!.value,
        if (toStatus != null) 'to_status': toStatus!.value,
        if (remarks != null) 'remarks': remarks,
        'is_overdue_log': isOverdueLog,
        'is_escalation_log': isEscalationLog,
        if (escalationLevel != null) 'escalation_level': escalationLevel,
      };
}
