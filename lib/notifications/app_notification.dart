/// In-app notification row from `GET /api/notifications`.
class AppNotification {
  AppNotification({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    this.body,
    this.readAt,
    this.referenceType,
    this.referenceId,
    this.metadata,
    required this.createdAt,
  });

  final String id;
  final String category;
  final String type;
  final String title;
  final String? body;
  final DateTime? readAt;
  final String? referenceType;
  final String? referenceId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    Map<String, dynamic>? meta;
    final m = json['metadata'];
    if (m is Map<String, dynamic>) {
      meta = m;
    } else if (m is Map) {
      meta = Map<String, dynamic>.from(m);
    }

    return AppNotification(
      id: json['id'] as String,
      category: (json['category'] ?? 'general').toString(),
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: json['body'] as String?,
      readAt: parseTs(json['read_at']),
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      metadata: meta,
      createdAt: parseTs(json['created_at']) ?? DateTime.now(),
    );
  }
}
