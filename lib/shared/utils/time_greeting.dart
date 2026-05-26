/// Time-of-day greetings for dashboard welcome lines.
///
/// - Good Morning: 5:00 AM – 11:59 AM
/// - Good Afternoon: 12:00 PM – 4:59 PM
/// - Good Evening: 5:00 PM – 4:59 AM
String timeOfDayGreeting([DateTime? when]) {
  final hour = (when ?? DateTime.now()).hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// First token of [displayName] for a friendly greeting (e.g. "Johnley Santos" → "Johnley").
String greetingFirstName(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

/// e.g. "Good Evening, Johnley!" based on local time.
String personalizedTimeGreeting(String displayName, [DateTime? when]) {
  final name = greetingFirstName(displayName);
  return '${timeOfDayGreeting(when)}, $name!';
}
