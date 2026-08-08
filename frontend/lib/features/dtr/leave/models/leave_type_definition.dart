enum LeaveCustomFieldType { text, longText, date, number, boolean, select }

extension LeaveCustomFieldTypeValue on LeaveCustomFieldType {
  String get value => switch (this) {
    LeaveCustomFieldType.text => 'text',
    LeaveCustomFieldType.longText => 'long_text',
    LeaveCustomFieldType.date => 'date',
    LeaveCustomFieldType.number => 'number',
    LeaveCustomFieldType.boolean => 'boolean',
    LeaveCustomFieldType.select => 'select',
  };

  String get displayName => switch (this) {
    LeaveCustomFieldType.text => 'Text',
    LeaveCustomFieldType.longText => 'Long text',
    LeaveCustomFieldType.date => 'Date',
    LeaveCustomFieldType.number => 'Number',
    LeaveCustomFieldType.boolean => 'Yes / No',
    LeaveCustomFieldType.select => 'Select',
  };
}

LeaveCustomFieldType leaveCustomFieldTypeFromString(String? value) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'long_text' || 'longtext' => LeaveCustomFieldType.longText,
    'date' => LeaveCustomFieldType.date,
    'number' => LeaveCustomFieldType.number,
    'boolean' || 'bool' => LeaveCustomFieldType.boolean,
    'select' => LeaveCustomFieldType.select,
    _ => LeaveCustomFieldType.text,
  };
}

class LeaveCustomFieldDefinition {
  const LeaveCustomFieldDefinition({
    required this.key,
    required this.label,
    this.type = LeaveCustomFieldType.text,
    this.required = false,
    this.maxLength,
    this.options = const [],
  });

  final String key;
  final String label;
  final LeaveCustomFieldType type;
  final bool required;
  final int? maxLength;
  final List<String> options;

  factory LeaveCustomFieldDefinition.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return LeaveCustomFieldDefinition(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: leaveCustomFieldTypeFromString(json['type']?.toString()),
      required: json['required'] == true,
      maxLength: LeaveTypeDefinition._parseInt(
        json['max_length'] ?? json['maxLength'],
      ),
      options: rawOptions is List
          ? rawOptions
                .map((option) => option.toString().trim())
                .where((option) => option.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key.trim(),
    'label': label.trim(),
    'type': type.value,
    'required': required,
    if (type == LeaveCustomFieldType.text ||
        type == LeaveCustomFieldType.longText)
      'max_length':
          maxLength ?? (type == LeaveCustomFieldType.longText ? 2000 : 255),
    if (type == LeaveCustomFieldType.select) 'options': options,
  };
}

List<LeaveCustomFieldDefinition> leaveCustomFieldDefinitionsFromJson(
  dynamic value,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => LeaveCustomFieldDefinition.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .where((field) => field.key.isNotEmpty && field.label.isNotEmpty)
      .toList(growable: false);
}

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
    this.minimumAdvanceDays,
    this.affectsDtrNormally = true,
    this.balanceLedgerType = 'none',
    this.sexEligibility = 'any',
    this.employeeDetailSchema = const [],
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
  final int? minimumAdvanceDays;
  final bool affectsDtrNormally;
  final String balanceLedgerType;
  final String sexEligibility;
  final List<LeaveCustomFieldDefinition> employeeDetailSchema;

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
      minimumAdvanceDays: _parseInt(
        json['minimum_advance_days'] ?? json['minimumAdvanceDays'],
      ),
      affectsDtrNormally:
          json['affects_dtr_normally'] != false &&
          json['affectsDtrNormally'] != false,
      balanceLedgerType:
          json['balance_ledger_type']?.toString() ??
          json['balanceLedgerType']?.toString() ??
          'none',
      sexEligibility: normalizeLeaveTypeSexEligibility(
        json['sex_eligibility']?.toString() ??
            json['sexEligibility']?.toString(),
      ),
      employeeDetailSchema: _parseCustomFields(
        json['employee_detail_schema'] ?? json['employeeDetailSchema'],
      ),
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
      'minimum_advance_days': minimumAdvanceDays,
      'affects_dtr_normally': affectsDtrNormally,
      'balance_ledger_type': balanceLedgerType,
      'sex_eligibility': sexEligibility,
      'employee_detail_schema': employeeDetailSchema
          .map((field) => field.toJson())
          .toList(growable: false),
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
    int? minimumAdvanceDays,
    bool? affectsDtrNormally,
    String? balanceLedgerType,
    String? sexEligibility,
    List<LeaveCustomFieldDefinition>? employeeDetailSchema,
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
      minimumAdvanceDays: minimumAdvanceDays ?? this.minimumAdvanceDays,
      affectsDtrNormally: affectsDtrNormally ?? this.affectsDtrNormally,
      balanceLedgerType: balanceLedgerType ?? this.balanceLedgerType,
      sexEligibility: sexEligibility ?? this.sexEligibility,
      employeeDetailSchema: employeeDetailSchema ?? this.employeeDetailSchema,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static List<LeaveCustomFieldDefinition> _parseCustomFields(dynamic value) {
    return leaveCustomFieldDefinitionsFromJson(value);
  }
}

String normalizeLeaveTypeSexEligibility(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'female':
    case 'female_only':
    case 'femaleonly':
      return 'female';
    case 'male':
    case 'male_only':
    case 'maleonly':
      return 'male';
    case 'both':
    case 'all':
    case 'bothsexes':
      return 'any';
    default:
      return 'any';
  }
}

String leaveTypeSexEligibilityLabel(String value) {
  switch (normalizeLeaveTypeSexEligibility(value)) {
    case 'female':
      return 'Female only';
    case 'male':
      return 'Male only';
    default:
      return 'Both sexes';
  }
}

extension LeaveTypeDefinitionCreditPolicy on LeaveTypeDefinition {
  bool get usesLeaveCredits => balanceLedgerType != 'none';

  bool get usesOwnBalance => balanceLedgerType == 'ownBalance';

  String get effectiveBalanceBucket {
    if (usesOwnBalance) return name;
    return balanceLedgerType;
  }

  String get creditPolicyLabel {
    switch (balanceLedgerType) {
      case 'vacationLeave':
        return 'Deducts from Vacation Leave credits';
      case 'sickLeave':
        return 'Deducts from Sick Leave credits';
      case 'ownBalance':
        return 'Uses its own separate balance';
      default:
        return 'No leave credits required';
    }
  }
}
