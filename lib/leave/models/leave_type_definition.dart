class LeaveTypeDefinition {
  const LeaveTypeDefinition({
    this.id,
    required this.name,
    required this.displayName,
    this.description,
    this.isActive = true,
    this.isSystem = false,
    this.employeeCanFile = true,
    this.adminOnly = false,
    this.allowsPastDates = true,
    this.requiresAttachment = false,
    this.requiresAttachmentWhenOverDays,
    this.maxDays,
    this.affectsDtrNormally = true,
    this.balanceLedgerType = 'others',
  });

  final String? id;
  final String name;
  final String displayName;
  final String? description;
  final bool isActive;
  final bool isSystem;
  final bool employeeCanFile;
  final bool adminOnly;
  final bool allowsPastDates;
  final bool requiresAttachment;
  final double? requiresAttachmentWhenOverDays;
  final double? maxDays;
  final bool affectsDtrNormally;
  final String balanceLedgerType;

  factory LeaveTypeDefinition.fromJson(Map<String, dynamic> json) {
    return LeaveTypeDefinition(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ??
          json['displayName']?.toString() ??
          json['description']?.toString() ??
          json['name']?.toString() ??
          'Leave type',
      description: json['description']?.toString(),
      isActive: json['is_active'] != false && json['isActive'] != false,
      isSystem: json['is_system'] == true || json['isSystem'] == true,
      employeeCanFile:
          json['employee_can_file'] != false &&
          json['employeeCanFile'] != false,
      adminOnly: json['admin_only'] == true || json['adminOnly'] == true,
      allowsPastDates:
          json['allows_past_dates'] != false &&
          json['allowsPastDates'] != false,
      requiresAttachment:
          json['requires_attachment'] == true ||
          json['requiresAttachment'] == true,
      requiresAttachmentWhenOverDays: _parseDouble(
        json['requires_attachment_when_over_days'] ??
            json['requiresAttachmentWhenOverDays'],
      ),
      maxDays: _parseDouble(json['max_days'] ?? json['maxDays']),
      affectsDtrNormally:
          json['affects_dtr_normally'] != false &&
          json['affectsDtrNormally'] != false,
      balanceLedgerType:
          json['balance_ledger_type']?.toString() ??
          json['balanceLedgerType']?.toString() ??
          'others',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'display_name': displayName,
      'description': description,
      'is_active': isActive,
      'employee_can_file': employeeCanFile,
      'admin_only': adminOnly,
      'allows_past_dates': allowsPastDates,
      'requires_attachment': requiresAttachment,
      'requires_attachment_when_over_days': requiresAttachmentWhenOverDays,
      'max_days': maxDays,
      'affects_dtr_normally': affectsDtrNormally,
      'balance_ledger_type': balanceLedgerType,
    };
  }

  LeaveTypeDefinition copyWith({
    String? id,
    String? name,
    String? displayName,
    String? description,
    bool? isActive,
    bool? isSystem,
    bool? employeeCanFile,
    bool? adminOnly,
    bool? allowsPastDates,
    bool? requiresAttachment,
    double? requiresAttachmentWhenOverDays,
    double? maxDays,
    bool? affectsDtrNormally,
    String? balanceLedgerType,
  }) {
    return LeaveTypeDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem ?? this.isSystem,
      employeeCanFile: employeeCanFile ?? this.employeeCanFile,
      adminOnly: adminOnly ?? this.adminOnly,
      allowsPastDates: allowsPastDates ?? this.allowsPastDates,
      requiresAttachment: requiresAttachment ?? this.requiresAttachment,
      requiresAttachmentWhenOverDays:
          requiresAttachmentWhenOverDays ?? this.requiresAttachmentWhenOverDays,
      maxDays: maxDays ?? this.maxDays,
      affectsDtrNormally: affectsDtrNormally ?? this.affectsDtrNormally,
      balanceLedgerType: balanceLedgerType ?? this.balanceLedgerType,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
