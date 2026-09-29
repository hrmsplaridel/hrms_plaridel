class HrWorkflowMirrorReviewer {
  const HrWorkflowMirrorReviewer({
    required this.id,
    required this.name,
    required this.role,
    this.backupRank,
  });

  final String id;
  final String name;
  final String role;
  final int? backupRank;

  factory HrWorkflowMirrorReviewer.fromJson(Map<String, dynamic> json) {
    return HrWorkflowMirrorReviewer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown reviewer',
      role: json['role']?.toString() ?? 'reviewer',
      backupRank: (json['backup_rank'] as num?)?.toInt(),
    );
  }
}

class HrWorkflowMirrorGroup {
  const HrWorkflowMirrorGroup({
    required this.scopeName,
    required this.backups,
    this.scopeId,
    this.primary,
  });

  final String? scopeId;
  final String scopeName;
  final HrWorkflowMirrorReviewer? primary;
  final List<HrWorkflowMirrorReviewer> backups;

  factory HrWorkflowMirrorGroup.fromJson(Map<String, dynamic> json) {
    final primary = json['primary'];
    final backups = json['backups'];
    return HrWorkflowMirrorGroup(
      scopeId: json['scope_id']?.toString(),
      scopeName: json['scope_name']?.toString() ?? 'Office-wide',
      primary: primary is Map
          ? HrWorkflowMirrorReviewer.fromJson(
              Map<String, dynamic>.from(primary),
            )
          : null,
      backups: backups is List
          ? backups
                .whereType<Map>()
                .map(
                  (item) => HrWorkflowMirrorReviewer.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class HrWorkflowMirrorStep {
  const HrWorkflowMirrorStep({
    required this.stepOrder,
    required this.label,
    required this.assigneeSummary,
    required this.groups,
  });

  final int stepOrder;
  final String label;
  final String assigneeSummary;
  final List<HrWorkflowMirrorGroup> groups;

  factory HrWorkflowMirrorStep.fromJson(Map<String, dynamic> json) {
    final groups = json['groups'];
    return HrWorkflowMirrorStep(
      stepOrder: (json['step_order'] as num?)?.toInt() ?? 1,
      label: json['label']?.toString() ?? 'Review',
      assigneeSummary: json['assignee_summary']?.toString() ?? 'Not configured',
      groups: groups is List
          ? groups
                .whereType<Map>()
                .map(
                  (item) => HrWorkflowMirrorGroup.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class HrWorkflowMirror {
  const HrWorkflowMirror({
    required this.key,
    required this.title,
    required this.sourceLabel,
    required this.effectiveDate,
    required this.systemManaged,
    required this.steps,
  });

  final String key;
  final String title;
  final String sourceLabel;
  final DateTime? effectiveDate;
  final bool systemManaged;
  final List<HrWorkflowMirrorStep> steps;

  factory HrWorkflowMirror.fromJson(Map<String, dynamic> json) {
    final effectiveDate = json['effective_date']?.toString();
    final steps = json['steps'];
    return HrWorkflowMirror(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? 'HR Workflow',
      sourceLabel: json['source_label']?.toString() ?? 'Synced from DTR',
      effectiveDate: effectiveDate == null
          ? null
          : DateTime.tryParse(effectiveDate),
      systemManaged: json['system_managed'] != false,
      steps: steps is List
          ? steps
                .whereType<Map>()
                .map(
                  (item) => HrWorkflowMirrorStep.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}
