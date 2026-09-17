DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Returns whether a leave request touches the selected inclusive date range.
///
/// A legacy request with only one endpoint is treated as a single-day request.
/// When both endpoints are missing, it remains visible because its date cannot
/// be proven to fall outside the filter.
bool leaveRequestOverlapsDateFilter({
  required DateTime? requestStart,
  required DateTime? requestEnd,
  required DateTime? filterStart,
  required DateTime? filterEnd,
}) {
  if (filterStart == null && filterEnd == null) return true;

  final resolvedStart = requestStart ?? requestEnd;
  final resolvedEnd = requestEnd ?? requestStart;
  if (resolvedStart == null || resolvedEnd == null) return true;

  final start = _dateOnly(resolvedStart);
  final end = _dateOnly(resolvedEnd);
  final from = filterStart == null ? null : _dateOnly(filterStart);
  final to = filterEnd == null ? null : _dateOnly(filterEnd);

  if (from != null && end.isBefore(from)) return false;
  if (to != null && start.isAfter(to)) return false;
  return true;
}
