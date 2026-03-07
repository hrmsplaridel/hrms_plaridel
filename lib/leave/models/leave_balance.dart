import 'leave_type.dart';

/// Running leave credits for one employee and one leave type.
///
/// This supports:
/// - employee balance display
/// - validation before approval
/// - section 7.A "Certification of Leave Credits" in the paper form
class LeaveBalance {
  const LeaveBalance({
    this.id,
    required this.userId,
    required this.leaveType,
    this.employeeName,
    this.earnedDays = 0,
    this.usedDays = 0,
    this.pendingDays = 0,
    this.adjustedDays = 0,
    this.asOfDate,
    this.lastAccrualDate,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String userId;
  final LeaveType leaveType;

  /// Optional display snapshot for admin tables/cards.
  final String? employeeName;

  /// Total earned credits for this leave type.
  final double earnedDays;

  /// Approved/consumed leave days already deducted.
  final double usedDays;

  /// Requested days not yet finalized. Helpful for warnings in UI.
  final double pendingDays;

  /// Manual adjustment by HR, positive or negative.
  final double adjustedDays;

  /// Date the balance snapshot is based on.
  final DateTime? asOfDate;

  /// Last time credits were accrued/updated from policy.
  final DateTime? lastAccrualDate;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'leave_balances';

  /// Remaining usable credits after approved usage and adjustments.
  double get remainingDays => earnedDays - usedDays + adjustedDays;

  /// Optional stricter view that also considers pending requests.
  double get availableDays => remainingDays - pendingDays;

  bool get hasInsufficientBalance => availableDays < 0;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    return LeaveBalance(
      id: json['id']?.toString(),
      userId: json['user_id'] as String? ?? '',
      leaveType: leaveTypeFromString(json['leave_type']?.toString()),
      employeeName: json['employee_name']?.toString(),
      earnedDays: _parseDouble(json['earned_days']) ?? 0,
      usedDays: _parseDouble(json['used_days']) ?? 0,
      pendingDays: _parseDouble(json['pending_days']) ?? 0,
      adjustedDays: _parseDouble(json['adjusted_days']) ?? 0,
      asOfDate: _parseDate(json['as_of_date']),
      lastAccrualDate: _parseDate(json['last_accrual_date']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'leave_type': leaveType.value,
      'employee_name': _trimOrNull(employeeName),
      'earned_days': earnedDays,
      'used_days': usedDays,
      'pending_days': pendingDays,
      'adjusted_days': adjustedDays,
      'as_of_date': _dateOnly(asOfDate),
      'last_accrual_date': _dateOnly(lastAccrualDate),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  LeaveBalance copyWith({
    String? id,
    String? userId,
    LeaveType? leaveType,
    String? employeeName,
    double? earnedDays,
    double? usedDays,
    double? pendingDays,
    double? adjustedDays,
    DateTime? asOfDate,
    DateTime? lastAccrualDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LeaveBalance(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      leaveType: leaveType ?? this.leaveType,
      employeeName: employeeName ?? this.employeeName,
      earnedDays: earnedDays ?? this.earnedDays,
      usedDays: usedDays ?? this.usedDays,
      pendingDays: pendingDays ?? this.pendingDays,
      adjustedDays: adjustedDays ?? this.adjustedDays,
      asOfDate: asOfDate ?? this.asOfDate,
      lastAccrualDate: lastAccrualDate ?? this.lastAccrualDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _dateOnly(DateTime? value) {
    return value?.toIso8601String().split('T').first;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
