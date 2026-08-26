const Duration _philippineUtcOffset = Duration(hours: 8);

/// Returns the official Philippine wall-clock value used by HRMS reports.
///
/// API timestamps with `Z` or an explicit offset are parsed by Dart as UTC and
/// must be shifted to UTC+8. Offset-less values are already wall-clock values,
/// so their fields are preserved instead of being tied to the viewing device.
DateTime toOfficialPhilippineTime(DateTime value) {
  if (!value.isUtc) return value;
  return value.add(_philippineUtcOffset);
}

String formatOfficialPhilippineTime(
  DateTime? value, {
  String emptyValue = '—',
  bool lowercasePeriod = false,
  bool padHour = false,
}) {
  if (value == null) return emptyValue;

  final official = toOfficialPhilippineTime(value);
  final hour = official.hour;
  final minute = official.minute;
  final period = hour >= 12
      ? (lowercasePeriod ? 'pm' : 'PM')
      : (lowercasePeriod ? 'am' : 'AM');
  final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  final hourLabel = padHour ? hour12.toString().padLeft(2, '0') : '$hour12';

  return '$hourLabel:${minute.toString().padLeft(2, '0')}${lowercasePeriod ? '' : ' '}$period';
}
