class OfficialSignatoryPeriod {
  const OfficialSignatoryPeriod({
    required this.id,
    required this.roleKey,
    required this.employeeId,
    required this.name,
    required this.effectiveFrom,
    this.positionTitle,
    this.departmentName,
    this.effectiveTo,
    this.remarks,
    this.isEffective = false,
  });

  final String id;
  final String roleKey;
  final String employeeId;
  final String name;
  final String? positionTitle;
  final String? departmentName;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? remarks;
  final bool isEffective;

  factory OfficialSignatoryPeriod.fromJson(Map<String, dynamic> json) {
    return OfficialSignatoryPeriod(
      id: json['id']?.toString() ?? '',
      roleKey: json['role_key']?.toString() ?? '',
      employeeId: json['employee_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      positionTitle: _optionalText(json['position_title']),
      departmentName: _optionalText(json['department_name']),
      effectiveFrom: DateTime.parse(json['effective_from'].toString()),
      effectiveTo: json['effective_to'] == null
          ? null
          : DateTime.tryParse(json['effective_to'].toString()),
      remarks: _optionalText(json['remarks']),
      isEffective: json['is_effective'] == true,
    );
  }
}

class AutomaticMayorSignatory {
  const AutomaticMayorSignatory({
    required this.employeeId,
    required this.name,
    required this.positionTitle,
    this.departmentName,
  });

  final String employeeId;
  final String name;
  final String positionTitle;
  final String? departmentName;

  factory AutomaticMayorSignatory.fromJson(Map<String, dynamic> json) {
    return AutomaticMayorSignatory(
      employeeId: json['employee_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      positionTitle: _optionalText(json['position_title']) ?? 'Municipal Mayor',
      departmentName: _optionalText(json['department_name']),
    );
  }
}

String? _optionalText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
