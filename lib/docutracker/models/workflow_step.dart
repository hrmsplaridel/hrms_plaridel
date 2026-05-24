/// A single step in a document type's workflow (Step 3: Document Routing Logic).
/// Example: Memo → HR Staff → Department Head → Selected Employees
class WorkflowStep {
  const WorkflowStep({
    required this.stepOrder,
    required this.assigneeType,
    this.roleId,
    this.departmentId,
    this.officeId,
    this.userIds,
    this.label,
    this.enabled = true,
    this.deadlineHours,
  });

  /// 1-based step order in the workflow.
  final int stepOrder;

  /// Who receives at this step: role | department | office | user
  final String assigneeType;

  /// Role ID when assigneeType is 'role'
  final String? roleId;

  /// Department ID when assigneeType is 'department'
  final String? departmentId;

  /// Office ID when assigneeType is 'office'
  final String? officeId;

  /// Specific user IDs when assigneeType is 'user'
  final List<String>? userIds;

  /// Human-readable label (e.g. "HR Staff", "Procurement")
  final String? label;

  /// Whether this step is active in the workflow.
  final bool enabled;

  /// Optional per-step deadline in hours. If null, workflow default applies.
  final int? deadlineHours;

  factory WorkflowStep.fromJson(Map<String, dynamic> json) {
    final userIdsRaw = json['user_ids'];
    return WorkflowStep(
      stepOrder: (json['step_order'] as num?)?.toInt() ?? 1,
      assigneeType: json['assignee_type'] as String? ?? 'user',
      roleId: json['role_id']?.toString(),
      departmentId: json['department_id']?.toString(),
      officeId: json['office_id']?.toString(),
      userIds: userIdsRaw is List
          ? (userIdsRaw).map((e) => e.toString()).toList()
          : null,
      label: json['label']?.toString(),
      enabled: json['enabled'] != false,
      deadlineHours: (json['deadline_hours'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'step_order': stepOrder,
        'assignee_type': assigneeType,
        if (roleId != null) 'role_id': roleId,
        if (departmentId != null) 'department_id': departmentId,
        if (officeId != null) 'office_id': officeId,
        if (userIds != null) 'user_ids': userIds,
        if (label != null) 'label': label,
        'enabled': enabled,
        if (deadlineHours != null) 'deadline_hours': deadlineHours,
      };
}
