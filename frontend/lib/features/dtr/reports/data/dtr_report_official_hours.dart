/// Header text when an assignment period includes duty roster days.
const dutyRosterOfficialHours = 'Per duty roster (see daily entries)';

/// Official hours for a DTR assignment period. Rotating duty roster days use
/// different shifts per date, so the header defers to the daily entries.
String? reportOfficialHours({
  required Object? startTime,
  required Object? endTime,
  required Object? scheduleOverrides,
  required String Function(String start, String end) format,
}) {
  if (scheduleOverrides is List &&
      scheduleOverrides.whereType<Map>().any(
        (override) => (override['shift_id']?.toString() ?? '').isNotEmpty,
      )) {
    return dutyRosterOfficialHours;
  }
  if (startTime == null || endTime == null) return null;
  return format(startTime.toString(), endTime.toString());
}
