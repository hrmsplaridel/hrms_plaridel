part of '../pages/manage_assignment.dart';

/// Employee summary for assignment list.
class _EmployeeSummary {
  const _EmployeeSummary({
    required this.id,
    required this.fullName,
    this.employeeNumber,
  });
  final String id;
  final String fullName;
  final int? employeeNumber;

  String get displayEmployeeNo => employeeNumber != null
      ? 'EMP-${employeeNumber!.toString().padLeft(3, '0')}'
      : '—';

  String get compactEmployeeNo =>
      employeeNumber != null ? employeeNumber!.toString().padLeft(3, '0') : '—';
}

/// Assignment record for display/CRUD (Schema v2: effective_from/to, override times).
class _AssignmentRecord {
  const _AssignmentRecord({
    required this.id,
    required this.departmentId,
    required this.positionId,
    required this.shiftId,
    required this.departmentName,
    required this.positionName,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.effectiveFrom,
    this.effectiveTo,
    this.policyId,
    this.policyName,
    required this.isActive,
    this.remarks,
  });
  final String id;
  final String? departmentId;
  final String? positionId;
  final String? shiftId;
  final String departmentName;
  final String positionName;
  final String shiftName;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? policyId;
  final String? policyName;
  final bool isActive;
  final String? remarks;
}

/// Extra role/designation record that can coexist with the primary assignment.
class _DesignationRecord {
  const _DesignationRecord({
    required this.id,
    required this.employeeId,
    this.departmentId,
    this.positionId,
    required this.effectiveFrom,
    this.effectiveTo,
    required this.isActive,
    this.remarks,
    this.departmentName,
    this.positionName,
  });

  final String id;
  final String employeeId;
  final String? departmentId;
  final String? positionId;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final bool isActive;
  final String? remarks;
  final String? departmentName;
  final String? positionName;
}
