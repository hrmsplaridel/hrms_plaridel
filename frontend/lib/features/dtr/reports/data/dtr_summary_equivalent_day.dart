double? summaryEquivalentDay({
  required String? employeeId,
  required bool hasRecords,
  required bool hasUnverifiedInactiveAttendance,
  required double Function() calculate,
}) {
  if (hasUnverifiedInactiveAttendance) return null;
  if (employeeId == null || !hasRecords) return 0;
  return calculate();
}
