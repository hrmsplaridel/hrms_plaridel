class DocuTrackerPermissionPolicyDecision {
  const DocuTrackerPermissionPolicyDecision({
    required this.granted,
    required this.source,
  });

  final bool granted;
  final String source;

  factory DocuTrackerPermissionPolicyDecision.fromJson(
    Map<String, dynamic> json,
  ) => DocuTrackerPermissionPolicyDecision(
    granted: json['granted'] == true,
    source: json['source']?.toString() ?? 'not_configured',
  );
}

class DocuTrackerRolePermissionPolicy {
  const DocuTrackerRolePermissionPolicy({
    required this.roleId,
    required this.permissions,
  });

  final String roleId;
  final Map<String, DocuTrackerPermissionPolicyDecision> permissions;

  factory DocuTrackerRolePermissionPolicy.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permissions'];
    return DocuTrackerRolePermissionPolicy(
      roleId: json['role_id']?.toString() ?? '',
      permissions: rawPermissions is Map
          ? rawPermissions.map(
              (key, value) => MapEntry(
                key.toString(),
                DocuTrackerPermissionPolicyDecision.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              ),
            )
          : const {},
    );
  }
}

class DocuTrackerPermissionPolicyUser {
  const DocuTrackerPermissionPolicyUser({
    required this.id,
    required this.fullName,
    required this.roleId,
  });

  final String id;
  final String fullName;
  final String roleId;

  factory DocuTrackerPermissionPolicyUser.fromJson(Map<String, dynamic> json) =>
      DocuTrackerPermissionPolicyUser(
        id: json['id']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? 'Unknown employee',
        roleId: json['role']?.toString() ?? 'employee',
      );
}

class DocuTrackerPermissionPolicy {
  const DocuTrackerPermissionPolicy({
    required this.documentType,
    required this.actions,
    required this.roleDefaults,
    required this.userOverrides,
    required this.inheritedUserOverrides,
    required this.effective,
    this.selectedUser,
    this.updatedAt,
  });

  final String documentType;
  final List<String> actions;
  final List<DocuTrackerRolePermissionPolicy> roleDefaults;
  final DocuTrackerPermissionPolicyUser? selectedUser;
  final Map<String, bool?> userOverrides;
  final Map<String, bool?> inheritedUserOverrides;
  final Map<String, DocuTrackerPermissionPolicyDecision> effective;
  final DateTime? updatedAt;

  factory DocuTrackerPermissionPolicy.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['role_defaults'];
    final rawOverrides = json['user_overrides'];
    final rawEffective = json['effective'];
    final rawInheritedOverrides = json['inherited_user_overrides'];
    final rawUser = json['selected_user'];
    return DocuTrackerPermissionPolicy(
      documentType: json['document_type']?.toString() ?? '*',
      actions: (json['actions'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      roleDefaults: (rawRoles as List<dynamic>? ?? const [])
          .map(
            (value) => DocuTrackerRolePermissionPolicy.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      selectedUser: rawUser is Map
          ? DocuTrackerPermissionPolicyUser.fromJson(
              Map<String, dynamic>.from(rawUser),
            )
          : null,
      userOverrides: rawOverrides is Map
          ? rawOverrides.map<String, bool?>(
              (key, value) => MapEntry(key.toString(), value as bool?),
            )
          : const {},
      inheritedUserOverrides: rawInheritedOverrides is Map
          ? rawInheritedOverrides.map<String, bool?>(
              (key, value) => MapEntry(key.toString(), value as bool?),
            )
          : const {},
      effective: rawEffective is Map
          ? rawEffective.map(
              (key, value) => MapEntry(
                key.toString(),
                DocuTrackerPermissionPolicyDecision.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              ),
            )
          : const {},
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}

class DocuTrackerPermissionPolicyChange {
  const DocuTrackerPermissionPolicyChange.role({
    required this.roleId,
    required this.action,
    required this.granted,
  }) : userId = null;

  const DocuTrackerPermissionPolicyChange.user({
    required this.userId,
    required this.action,
    required this.granted,
  }) : roleId = null;

  final String? roleId;
  final String? userId;
  final String action;
  final bool? granted;

  Map<String, dynamic> toJson() => {
    if (roleId != null) 'role_id': roleId,
    if (userId != null) 'user_id': userId,
    'action': action,
    'granted': granted,
  };
}
