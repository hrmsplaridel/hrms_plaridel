/// Document workflow statuses matching the DB check constraint (prod_v2).
/// Note: 'draft' is intentionally excluded — the DB does not allow it.
enum DocumentStatus {
  pending,
  inReview,
  approved,
  rejected,
  returned,
  overdue,
  escalated,
  cancelled,
}

extension DocumentStatusExtension on DocumentStatus {
  /// Returns the snake_case string sent to / received from the backend.
  String get value => switch (this) {
    DocumentStatus.inReview => 'in_review',
    _ => name,
  };

  String get displayName => switch (this) {
    DocumentStatus.pending => 'Pending',
    DocumentStatus.inReview => 'In Review',
    DocumentStatus.approved => 'Approved',
    DocumentStatus.rejected => 'Rejected',
    DocumentStatus.returned => 'Returned',
    DocumentStatus.overdue => 'Overdue',
    DocumentStatus.escalated => 'Escalated',
    DocumentStatus.cancelled => 'Cancelled',
  };
}

DocumentStatus documentStatusFromString(String? s) {
  if (s == null || s.isEmpty) return DocumentStatus.pending;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  // Legacy / alias mappings
  if (normalized == 'forwarded' || normalized == 'inreview') {
    return DocumentStatus.inReview;
  }
  if (normalized == 'draft') {
    return DocumentStatus.pending; // DB doesn't allow draft
  }
  if (normalized == 'cancelled') return DocumentStatus.cancelled;
  for (final e in DocumentStatus.values) {
    if (e.value.replaceAll('_', '') == normalized) return e;
  }
  return DocumentStatus.pending;
}
