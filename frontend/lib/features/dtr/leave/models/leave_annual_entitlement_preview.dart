class LeaveAnnualEntitlementYearPreview {
  const LeaveAnnualEntitlementYearPreview({
    required this.year,
    required this.limitDays,
    required this.approvedDays,
    required this.pendingDays,
    required this.requestedDays,
    required this.remainingBeforeRequest,
    required this.remainingAfterRequest,
    required this.allowed,
    required this.requestedCountedDates,
    this.errorMessage,
  });

  final int year;
  final double limitDays;
  final double approvedDays;
  final double pendingDays;
  final double requestedDays;
  final double remainingBeforeRequest;
  final double remainingAfterRequest;
  final bool allowed;
  final List<String> requestedCountedDates;
  final String? errorMessage;

  factory LeaveAnnualEntitlementYearPreview.fromJson(
    Map<String, dynamic> json,
  ) {
    return LeaveAnnualEntitlementYearPreview(
      year: _asInt(json['year']),
      limitDays: _asDouble(json['limit_days']),
      approvedDays: _asDouble(json['approved_days']),
      pendingDays: _asDouble(json['pending_days']),
      requestedDays: _asDouble(json['requested_days']),
      remainingBeforeRequest: _asDouble(json['remaining_before_request']),
      remainingAfterRequest: _asDouble(json['remaining_after_request']),
      allowed: json['allowed'] == true,
      requestedCountedDates:
          (json['requested_counted_dates'] as List? ?? const [])
              .map((value) => value.toString())
              .toList(growable: false),
      errorMessage: _nullableString(json['error_message']),
    );
  }
}

class LeaveAnnualEntitlementPreview {
  const LeaveAnnualEntitlementPreview({
    required this.leaveType,
    required this.displayName,
    required this.limitDays,
    required this.allowed,
    required this.years,
  });

  final String leaveType;
  final String displayName;
  final double limitDays;
  final bool allowed;
  final List<LeaveAnnualEntitlementYearPreview> years;

  LeaveAnnualEntitlementYearPreview? get firstRejectedYear {
    for (final year in years) {
      if (!year.allowed) return year;
    }
    return null;
  }

  factory LeaveAnnualEntitlementPreview.fromJson(Map<String, dynamic> json) {
    final rawYears = json['years'];
    return LeaveAnnualEntitlementPreview(
      leaveType: (json['leave_type'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      limitDays: _asDouble(json['limit_days']),
      allowed: json['allowed'] == true,
      years: rawYears is List
          ? rawYears
                .whereType<Map>()
                .map(
                  (value) => LeaveAnnualEntitlementYearPreview.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
