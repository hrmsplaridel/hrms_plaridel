import 'document_status.dart';

/// A single routing step record for a document (Step 5: sent_time, deadline_time, reviewed_time, status).
/// Tracks when a document was sent to a reviewer, when it's due, and when it was reviewed.
class DocumentRoutingRecord {
  const DocumentRoutingRecord({
    this.id,
    required this.documentId,
    required this.stepOrder,
    required this.assigneeId,
    this.assigneeName,
    this.sentTime,
    this.deadlineTime,
    this.reviewedTime,
    this.status = DocumentStatus.pending,
    this.remarks,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String documentId;
  final int stepOrder;
  final String assigneeId;

  /// Joined from profiles
  final String? assigneeName;

  /// Step 5: when document was forwarded to this reviewer
  final DateTime? sentTime;

  /// Step 5: when review must be completed
  final DateTime? deadlineTime;

  /// Step 5: when reviewer completed action
  final DateTime? reviewedTime;

  /// Step 5: Pending, In Review, Approved, Rejected, etc.
  final DocumentStatus status;

  final String? remarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'docutracker_routing_records';

  factory DocumentRoutingRecord.fromJson(Map<String, dynamic> json) {
    return DocumentRoutingRecord(
      id: json['id']?.toString(),
      documentId: json['document_id'] as String? ?? '',
      stepOrder: (json['step_order'] as num?)?.toInt() ?? 1,
      assigneeId: json['assignee_id'] as String? ?? '',
      assigneeName: json['assignee_name']?.toString(),
      sentTime: json['sent_time'] != null
          ? DateTime.tryParse(json['sent_time'] as String)
          : null,
      deadlineTime: json['deadline_time'] != null
          ? DateTime.tryParse(json['deadline_time'] as String)
          : null,
      reviewedTime: json['reviewed_time'] != null
          ? DateTime.tryParse(json['reviewed_time'] as String)
          : null,
      status: documentStatusFromString(json['status']?.toString()),
      remarks: json['remarks']?.toString(),
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
        'document_id': documentId,
        'step_order': stepOrder,
        'assignee_id': assigneeId,
        if (sentTime != null) 'sent_time': sentTime!.toIso8601String(),
        if (deadlineTime != null) 'deadline_time': deadlineTime!.toIso8601String(),
        if (reviewedTime != null) 'reviewed_time': reviewedTime!.toIso8601String(),
        'status': status.value,
        if (remarks != null) 'remarks': remarks,
        'updated_at': DateTime.now().toIso8601String(),
      };
}
