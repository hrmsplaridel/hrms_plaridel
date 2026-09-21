String reportEmployeeStatusForPeriod({
  required int year,
  required int month,
  required DateTime today,
  String? manualStatus,
}) {
  if (manualStatus != null) return manualStatus;
  final isHistorical =
      year < today.year || (year == today.year && month < today.month);
  return isHistorical ? 'All' : 'Active';
}

bool hasUndatedInactiveEmployment({String? employmentStatus}) =>
    employmentStatus?.trim().toLowerCase() == 'inactive';

bool isSyntheticAbsentRow({required String? id, required String? status}) =>
    id == null && status == 'absent';
