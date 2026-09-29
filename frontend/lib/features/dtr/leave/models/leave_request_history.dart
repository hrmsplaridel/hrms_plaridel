class LeaveRequestHistoryEntry {
  const LeaveRequestHistoryEntry({
    required this.id,
    required this.requestId,
    required this.action,
    this.fromStatus,
    required this.toStatus,
    this.actorId,
    this.actorName,
    this.actorRole,
    required this.actedAt,
    this.remarks,
    this.metadata,
  });

  final String id;
  final String requestId;
  final String action;
  final String? fromStatus;
  final String toStatus;
  final String? actorId;
  final String? actorName;
  final String? actorRole;
  final DateTime actedAt;
  final String? remarks;
  final Map<String, dynamic>? metadata;

  String get actionLabel => switch (action) {
    'saved_draft' => 'Draft saved',
    'submitted' => 'Submitted',
    'updated' => 'Request updated',
    'resubmitted' => 'Resubmitted',
    'department_head_approved' => 'Approved by Department Reviewer',
    'department_head_rejected' => 'Rejected by Department Reviewer',
    'department_head_returned' => 'Returned by Department Reviewer',
    'approved' => 'Approved by HR',
    'rejected' => 'Rejected by HR',
    'returned' => 'Returned by HR',
    'cancelled' => 'Cancelled',
    _ => _humanize(action),
  };

  String get actorLabel {
    final name = actorName?.trim();
    return name == null || name.isEmpty ? 'System' : name;
  }

  factory LeaveRequestHistoryEntry.fromJson(Map<String, dynamic> json) {
    final actedAt = DateTime.tryParse(json['acted_at']?.toString() ?? '');
    if (actedAt == null) {
      throw const FormatException('Invalid leave history timestamp');
    }
    final rawMetadata = json['metadata_json'];
    return LeaveRequestHistoryEntry(
      id: json['id']?.toString() ?? '',
      requestId: json['leave_request_id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      fromStatus: json['from_status']?.toString(),
      toStatus: json['to_status']?.toString() ?? '',
      actorId: json['acted_by']?.toString(),
      actorName: json['actor_name']?.toString(),
      actorRole: json['actor_role']?.toString(),
      actedAt: actedAt.toLocal(),
      remarks: json['remarks']?.toString(),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : null,
    );
  }

  static String _humanize(String value) {
    final words = value
        .split('_')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}');
    return words.isEmpty ? 'Status updated' : words.join(' ');
  }
}
