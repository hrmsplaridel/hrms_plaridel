class LocatorWorkflowEvent {
  const LocatorWorkflowEvent({
    required this.id,
    required this.action,
    required this.title,
    this.fromStatus,
    this.toStatus,
    this.actorId,
    this.actorName,
    this.actorRole,
    this.remarks,
    this.createdAt,
  });

  final String id;
  final String action;
  final String title;
  final String? fromStatus;
  final String? toStatus;
  final String? actorId;
  final String? actorName;
  final String? actorRole;
  final String? remarks;
  final DateTime? createdAt;

  factory LocatorWorkflowEvent.fromJson(Map<String, dynamic> json) {
    String? optionalText(dynamic value) {
      final text = (value ?? '').toString().trim();
      return text.isEmpty ? null : text;
    }

    return LocatorWorkflowEvent(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      title: (json['title'] ?? json['action'] ?? 'Workflow action').toString(),
      fromStatus: optionalText(json['from_status']),
      toStatus: optionalText(json['to_status']),
      actorId: optionalText(json['actor_id']),
      actorName: optionalText(json['actor_name']),
      actorRole: optionalText(json['actor_role']),
      remarks: optionalText(json['remarks']),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }
}
