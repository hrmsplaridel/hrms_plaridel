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

  /// assigned | deadline_near | overdue | escalated | returned | rejected |
  /// released
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
  static const String typeReleased = 'released';

  /// Workflow event categories inferred from [type] + title/body copy.
  /// Backend stores a small type set; richer wording lives in title/body.
  static const String eventSubmission = 'submission';
  static const String eventApproval = 'approval';
  static const String eventForwarding = 'forwarding';
  static const String eventReturn = 'return';
  static const String eventRejection = 'rejection';
  static const String eventSignature = 'signature';
  static const String eventRelease = 'release';
  static const String eventOverdue = 'overdue';
  static const String eventEscalation = 'escalation';
  static const String eventDeadline = 'deadline';
  static const String eventAssignment = 'assignment';
  static const String eventAdminRecovery = 'admin_recovery';

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
    typeReleased => 'Document released to your department',
    _ => type,
  };

  /// Headline shown in lists — prefers server title, else [displayType].
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return displayType;
  }

  /// Supporting copy for lists.
  String? get displayBody {
    final b = body?.trim();
    if (b == null || b.isEmpty) return null;
    return b;
  }

  /// Inferred workflow event for icons/labels (does not change persisted type).
  String get eventKind {
    final haystack = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    if (type == typeReturned) return eventReturn;
    if (type == typeRejected) return eventRejection;
    if (type == typeReleased) return eventRelease;
    if (type == typeOverdue) return eventOverdue;
    if (type == typeEscalated) return eventEscalation;
    if (type == typeDeadlineNear) return eventDeadline;
    if (haystack.contains('reassign') || haystack.contains('admin recovery')) {
      return eventAdminRecovery;
    }
    if (haystack.contains('sign')) return eventSignature;
    if (haystack.contains('submit')) return eventSubmission;
    if (haystack.contains('forward')) return eventForwarding;
    if (haystack.contains('approv')) return eventApproval;
    if (type == typeAssigned) return eventAssignment;
    return type;
  }

  /// Short chip label for the workflow event.
  String get eventLabel => switch (eventKind) {
    eventSubmission => 'Submission',
    eventApproval => 'Approval',
    eventForwarding => 'Forwarding',
    eventReturn => 'Return',
    eventRejection => 'Rejection',
    eventSignature => 'Signature',
    eventRelease => 'Release',
    eventOverdue => 'Overdue',
    eventEscalation => 'Escalation',
    eventDeadline => 'Deadline',
    eventAdminRecovery => 'Admin Recovery',
    eventAssignment => 'Assignment',
    _ => displayType,
  };

  /// Best-effort document reference from body/title when no lookup is available.
  /// Bodies often start with the document name: `"Memo X was submitted…"`.
  String? get inferredDocumentReference {
    final b = body?.trim();
    if (b != null && b.isNotEmpty) {
      final patterns = <RegExp>[
        RegExp(r'^(.+?)\s+was\s+', caseSensitive: false),
        RegExp(r'^(.+?)\s+requires\s+', caseSensitive: false),
        RegExp(r'^(.+?)\s+is\s+', caseSensitive: false),
        RegExp(r'^Document\s+"([^"]+)"', caseSensitive: false),
      ];
      for (final pattern in patterns) {
        final match = pattern.firstMatch(b);
        final name = match?.group(1)?.trim();
        if (name != null &&
            name.isNotEmpty &&
            name.toLowerCase() != 'this document' &&
            name.toLowerCase() != 'a document') {
          return name;
        }
      }
    }
    if (documentId.isEmpty) return null;
    final short = documentId.replaceAll('-', '');
    if (short.length <= 8) return 'Doc $short';
    return 'Doc ${short.substring(0, 8)}';
  }

  DocumentNotification copyWith({
    String? id,
    String? documentId,
    String? userId,
    String? type,
    String? title,
    String? body,
    bool? read,
    DateTime? createdAt,
  }) {
    return DocumentNotification(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
