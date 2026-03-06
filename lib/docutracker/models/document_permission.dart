import 'document_action.dart';

/// Per-role or per-user permission for document actions (Step 4: Admin Privilege Management).
class DocumentPermission {
  const DocumentPermission({
    this.id,
    this.roleId,
    this.userId,
    required this.documentType,
    required this.action,
    this.granted = true,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;

  /// When set, applies to all users with this role.
  final String? roleId;

  /// When set, applies to this specific user (overrides role).
  final String? userId;

  /// Document type this permission applies to (or '*' for all).
  final String documentType;

  /// Action: view, edit, download, delete, return, forward, approve, reject
  final DocumentAction action;

  final bool granted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'docutracker_permissions';

  factory DocumentPermission.fromJson(Map<String, dynamic> json) {
    final actionStr = json['action']?.toString() ?? 'view';
    final normalized = actionStr.toLowerCase().replaceAll(' ', '');
    DocumentAction action = DocumentAction.view;
    for (final e in DocumentAction.values) {
      if (e.name == normalized || (e == DocumentAction.returnDoc && normalized == 'return')) {
        action = e;
        break;
      }
    }
    return DocumentPermission(
      id: json['id']?.toString(),
      roleId: json['role_id']?.toString(),
      userId: json['user_id']?.toString(),
      documentType: json['document_type'] as String? ?? '*',
      action: action,
      granted: json['granted'] != false,
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
        if (roleId != null) 'role_id': roleId,
        if (userId != null) 'user_id': userId,
        'document_type': documentType,
        'action': action.value,
        'granted': granted,
        'updated_at': DateTime.now().toIso8601String(),
      };
}
