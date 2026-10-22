/// Time-of-day greetings for dashboard welcome lines.
///
/// - Good Morning: 12:00 AM – 11:59 AM
/// - Good Noon: 12:00 NN – 12:59 NN
/// - Good Afternoon: 1:00 PM – 5:59 PM
/// - Good Evening: 6:00 PM – 11:59 PM
String timeOfDayGreeting([DateTime? when]) {
  final hour = (when ?? DateTime.now()).hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 13) return 'Good Noon';
  if (hour < 18) return 'Good Afternoon';
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

/// Executive greeting for the Mayor portal (time of day + "Mayor").
String mayorPortalGreeting([DateTime? when]) =>
    '${timeOfDayGreeting(when)}, Mayor';
