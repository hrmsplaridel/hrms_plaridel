/// Document workflow statuses (Step 5: Review Time Limit).
enum DocumentStatus {
  pending,
  inReview,
  approved,
  rejected,
  returned,
  overdue,
  escalated,
}

extension DocumentStatusExtension on DocumentStatus {
  String get value => name;

  String get displayName => switch (this) {
        DocumentStatus.pending => 'Pending',
        DocumentStatus.inReview => 'In Review',
        DocumentStatus.approved => 'Approved',
        DocumentStatus.rejected => 'Rejected',
        DocumentStatus.returned => 'Returned',
        DocumentStatus.overdue => 'Overdue',
        DocumentStatus.escalated => 'Escalated',
      };
}

DocumentStatus documentStatusFromString(String? s) {
  if (s == null || s.isEmpty) return DocumentStatus.pending;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  if (normalized == 'forwarded') return DocumentStatus.inReview;
  for (final e in DocumentStatus.values) {
    if (e.name.toLowerCase().replaceAll('_', '') == normalized) return e;
  }
  return DocumentStatus.pending;
}
