import 'document_status.dart';

/// A tracked document in the DocuTracker system.
/// Step 5: sent_time, deadline_time, reviewed_time, status.
class DocuTrackerDocument {
  const DocuTrackerDocument({
    this.id,
    this.documentNumber,
    required this.documentType,
    required this.title,
    this.description,
    this.filePath,
    this.fileName,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.currentStep,
    this.status = DocumentStatus.pending,
    this.sentTime,
    this.deadlineTime,
    this.reviewedTime,
    this.creatorName,
    this.assigneeName,
    this.currentHolderId,
    this.escalationLevel = 0,
    this.needsAdminIntervention = false,
  });

  final String? id;
  /// Step 9: Unique document number (e.g. DOC-2025-0001)
  final String? documentNumber;
  final String documentType;
  final String title;
  final String? description;
  final String? filePath;
  final String? fileName;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Current workflow step (1-based).
  final int? currentStep;

  /// Step 5: status
  final DocumentStatus status;

  /// Step 5: when document was sent to current reviewer
  final DateTime? sentTime;

  /// Step 5: when review must be completed
  final DateTime? deadlineTime;

  /// Step 5: when current reviewer completed action
  final DateTime? reviewedTime;

  /// Joined from profiles when listing
  final String? creatorName;

  /// Current assignee name (joined)
  final String? assigneeName;

  /// Step 9: Current holder user ID
  final String? currentHolderId;

  /// Step 6: Current escalation level (0 = none)
  final int escalationLevel;

  /// Step 6: Flag for admin when max escalation reached
  final bool needsAdminIntervention;

  static const String tableName = 'docutracker_documents';

  factory DocuTrackerDocument.fromJson(Map<String, dynamic> json) {
    return DocuTrackerDocument(
      id: json['id']?.toString(),
      documentNumber: json['document_number']?.toString(),
      documentType: json['document_type'] as String? ?? 'memo',
      title: json['title'] as String? ?? '',
      description: json['description']?.toString(),
      filePath: json['file_path']?.toString(),
      fileName: json['file_name']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      currentStep: (json['current_step'] as num?)?.toInt(),
      status: documentStatusFromString(json['status']?.toString()),
      sentTime: json['sent_time'] != null
          ? DateTime.tryParse(json['sent_time'] as String)
          : null,
      deadlineTime: json['deadline_time'] != null
          ? DateTime.tryParse(json['deadline_time'] as String)
          : null,
      reviewedTime: json['reviewed_time'] != null
          ? DateTime.tryParse(json['reviewed_time'] as String)
          : null,
      creatorName: json['creator_name']?.toString(),
      assigneeName: json['assignee_name']?.toString(),
      currentHolderId: json['current_holder_id']?.toString(),
      escalationLevel: (json['escalation_level'] as num?)?.toInt() ?? 0,
      needsAdminIntervention: json['needs_admin_intervention'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (documentNumber != null) 'document_number': documentNumber,
        'document_type': documentType,
        'title': title,
        if (description != null) 'description': description,
        if (filePath != null) 'file_path': filePath,
        if (fileName != null) 'file_name': fileName,
        if (createdBy != null) 'created_by': createdBy,
        if (currentStep != null) 'current_step': currentStep,
        'status': status.value,
        if (sentTime != null) 'sent_time': sentTime!.toIso8601String(),
        if (deadlineTime != null) 'deadline_time': deadlineTime!.toIso8601String(),
        if (reviewedTime != null) 'reviewed_time': reviewedTime!.toIso8601String(),
        if (currentHolderId != null) 'current_holder_id': currentHolderId,
        'escalation_level': escalationLevel,
        'needs_admin_intervention': needsAdminIntervention,
        'updated_at': DateTime.now().toIso8601String(),
      };

  DocuTrackerDocument copyWith({
    String? id,
    String? documentNumber,
    String? documentType,
    String? title,
    String? description,
    String? filePath,
    String? fileName,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? currentStep,
    DocumentStatus? status,
    DateTime? sentTime,
    DateTime? deadlineTime,
    DateTime? reviewedTime,
    String? creatorName,
    String? assigneeName,
    String? currentHolderId,
    int? escalationLevel,
    bool? needsAdminIntervention,
  }) {
    return DocuTrackerDocument(
      id: id ?? this.id,
      documentNumber: documentNumber ?? this.documentNumber,
      documentType: documentType ?? this.documentType,
      title: title ?? this.title,
      description: description ?? this.description,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currentStep: currentStep ?? this.currentStep,
      status: status ?? this.status,
      sentTime: sentTime ?? this.sentTime,
      deadlineTime: deadlineTime ?? this.deadlineTime,
      reviewedTime: reviewedTime ?? this.reviewedTime,
      creatorName: creatorName ?? this.creatorName,
      assigneeName: assigneeName ?? this.assigneeName,
      currentHolderId: currentHolderId ?? this.currentHolderId,
      escalationLevel: escalationLevel ?? this.escalationLevel,
      needsAdminIntervention:
          needsAdminIntervention ?? this.needsAdminIntervention,
    );
  }
}
