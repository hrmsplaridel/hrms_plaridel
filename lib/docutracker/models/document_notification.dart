/// Step 7: Notifications and Alerts.
/// Notify users when: new document assigned, deadline near, overdue, escalated, returned/rejected.
class DocumentNotification {
  const DocumentNotification({
    this.id,
    required this.documentId,
    required this.userId,
    required this.type,
    this.title,
    this.body,
    this.read = false,
    this.createdAt,
  });

  final String? id;
  final String documentId;
  final String userId;
  /// assigned | deadline_near | overdue | escalated | returned | rejected
  final String type;
  final String? title;
  final String? body;
  final bool read;
  final DateTime? createdAt;

  static const String tableName = 'docutracker_notifications';

  static const String typeAssigned = 'assigned';
  static const String typeDeadlineNear = 'deadline_near';
  static const String typeOverdue = 'overdue';
  static const String typeEscalated = 'escalated';
  static const String typeReturned = 'returned';
  static const String typeRejected = 'rejected';

  factory DocumentNotification.fromJson(Map<String, dynamic> json) {
    return DocumentNotification(
      id: json['id']?.toString(),
      documentId: json['document_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: json['type'] as String? ?? 'assigned',
      title: json['title']?.toString(),
      body: json['body']?.toString(),
      read: json['read'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'document_id': documentId,
        'user_id': userId,
        'type': type,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        'read': read,
      };

  String get displayType => switch (type) {
        typeAssigned => 'New document assigned',
        typeDeadlineNear => 'Deadline approaching',
        typeOverdue => 'Document overdue',
        typeEscalated => 'Document escalated',
        typeReturned => 'Document returned',
        typeRejected => 'Document rejected',
        _ => type,
      };
}
