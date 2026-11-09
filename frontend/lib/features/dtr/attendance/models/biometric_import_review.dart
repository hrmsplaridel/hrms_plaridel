/// Server review for a batch; it does not save attendance.
class BiometricImportReview {
  const BiometricImportReview({
    required this.rowsReady,
    required this.rowsExcluded,
    required this.warningCount,
    required this.exclusions,
    required this.warnings,
  });

  final int rowsReady;
  final int rowsExcluded;
  final int warningCount;
  final List<BiometricImportReviewIssue> exclusions;
  final List<BiometricImportReviewIssue> warnings;

  factory BiometricImportReview.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw const FormatException(
          'The server did not return a valid import review.',
        );
      }
      return value;
    }

    final ready = count('rows_ready');
    final excluded = count('rows_excluded');
    if (ready + excluded != count('rows_total')) {
      throw const FormatException('The import review counts do not match.');
    }
    List<BiometricImportReviewIssue> issues(String key) => (json[key] as List)
        .map(
          (item) => BiometricImportReviewIssue.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    return BiometricImportReview(
      rowsReady: ready,
      rowsExcluded: excluded,
      warningCount: count('warning_count'),
      exclusions: issues('row_errors'),
      warnings: issues('review_warnings'),
    );
  }
}

class BiometricImportReviewIssue {
  const BiometricImportReviewIssue({
    required this.row,
    required this.message,
    this.biometricUserId = '',
    this.date = '',
  });
  final int row;
  final String message;
  final String biometricUserId;
  final String date;

  factory BiometricImportReviewIssue.fromJson(Map<String, dynamic> json) =>
      BiometricImportReviewIssue(
        row: (json['row'] as num?)?.toInt() ?? 0,
        message: (json['error'] ?? json['message'] ?? '').toString(),
        biometricUserId: (json['biometric_user_id'] ?? '').toString(),
        date: (json['attendance_date'] ?? '').toString(),
      );
}
