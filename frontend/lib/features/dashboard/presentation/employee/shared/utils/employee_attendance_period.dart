List<int> selectableEmployeeAttendanceMonths(int year, DateTime officialDate) {
  if (year > officialDate.year) return const [];
  final monthCount = year == officialDate.year ? officialDate.month : 12;
  return List.generate(monthCount, (index) => index + 1);
}

bool isValidEmployeeAttendanceRange({
  required DateTime start,
  required DateTime end,
  required DateTime officialDate,
}) {
  final officialDay = DateTime(
    officialDate.year,
    officialDate.month,
    officialDate.day,
  );
  return !end.isBefore(start) && !start.isAfter(officialDay);
}
