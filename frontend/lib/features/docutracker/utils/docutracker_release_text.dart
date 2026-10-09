import 'package:hrms_plaridel/features/docutracker/models/document.dart';

/// Status badge text for the release stage, or null when release does not
/// apply. The document status itself stays `approved` in both cases.
String? docuTrackerReleaseBadgeLabel(
  DocuTrackerDocument document, {
  bool short = false,
}) {
  if (document.isAwaitingRelease) {
    return short ? 'Awaiting release' : 'Approved · Awaiting release';
  }
  if (document.isReleased) return 'Released';
  return null;
}

const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// e.g. "October 9, 2026, 3:42 PM" in local time.
String docuTrackerReleaseTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${_months[local.month - 1]} ${local.day}, ${local.year}, '
      '$hour12:$minute $period';
}

/// e.g. "Released by Maria Santos · October 9, 2026, 3:42 PM".
String? docuTrackerReleasedByLine(DocuTrackerDocument document) {
  final releasedAt = document.releasedAt;
  if (releasedAt == null) return null;
  final name = document.releasedByName?.trim();
  final by = name == null || name.isEmpty ? 'Released' : 'Released by $name';
  return '$by · ${docuTrackerReleaseTimestamp(releasedAt)}';
}
