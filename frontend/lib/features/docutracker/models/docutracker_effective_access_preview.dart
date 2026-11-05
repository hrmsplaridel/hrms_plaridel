/// Read-only effective access returned by the System Access preview.
///
/// [outcome] is `allowed`, `blocked`, or `conditional`. A conditional result
/// is not a yes for any particular document.
class DocuTrackerEffectiveAccessAction {
  const DocuTrackerEffectiveAccessAction({
    required this.action,
    required this.outcome,
    required this.typeRule,
    required this.sourceKind,
    required this.precedence,
    required this.summary,
    this.matchedDocumentType,
    this.matchedRoleId,
    this.conditions = const [],
  });

  final String action;
  final String outcome;
  final String typeRule;
  final String sourceKind;
  final String? matchedDocumentType;
  final String? matchedRoleId;
  final String precedence;
  final String summary;
  final List<String> conditions;

  bool get isConditional => outcome == 'conditional';

  factory DocuTrackerEffectiveAccessAction.fromJson(Map<String, dynamic> json) {
    final conditions = json['conditions'];
    return DocuTrackerEffectiveAccessAction(
      action: json['action']?.toString() ?? '',
      outcome: json['outcome']?.toString() ?? 'conditional',
      typeRule: json['type_rule']?.toString() ?? 'none',
      sourceKind: json['source_kind']?.toString() ?? 'none',
      matchedDocumentType: json['matched_document_type']?.toString(),
      matchedRoleId: json['matched_role_id']?.toString(),
      precedence: json['precedence']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      conditions: conditions is List
          ? conditions.map((item) => item.toString()).toList(growable: false)
          : const [],
    );
  }
}

class DocuTrackerEffectiveAccessPreview {
  const DocuTrackerEffectiveAccessPreview({
    required this.basis,
    required this.documentType,
    required this.userName,
    required this.actions,
    this.userRole,
  });

  /// `saved_policy` means the last saved rules, never unsaved screen edits.
  final String basis;
  final String documentType;
  final String userName;

  /// Backend role from the preview payload when present.
  final String? userRole;
  final List<DocuTrackerEffectiveAccessAction> actions;

  factory DocuTrackerEffectiveAccessPreview.fromJson(
    Map<String, dynamic> json,
  ) {
    final user = json['user'];
    final actions = json['actions'];
    return DocuTrackerEffectiveAccessPreview(
      basis: json['basis']?.toString() ?? 'saved_policy',
      documentType: json['document_type']?.toString() ?? '',
      userName: user is Map
          ? user['full_name']?.toString() ?? 'Employee'
          : 'Employee',
      userRole: user is Map ? user['role']?.toString() : null,
      actions: actions is List
          ? actions
                .whereType<Map>()
                .map(
                  (item) => DocuTrackerEffectiveAccessAction.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.action.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}
