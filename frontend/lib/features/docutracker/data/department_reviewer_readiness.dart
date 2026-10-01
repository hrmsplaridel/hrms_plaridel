import 'package:hrms_plaridel/core/api/client.dart';

/// Whether documents routed to "the submitter's Department Head" can reach
/// someone for a department. Mirrors `GET /api/departments/reviewer-readiness`.
enum DepartmentReviewerStatus { ready, headOnly, noReviewer, noStaff }

class DepartmentReviewerReadiness {
  const DepartmentReviewerReadiness({
    required this.departmentId,
    required this.departmentName,
    required this.staffCount,
    required this.primaryName,
    required this.backupCount,
    required this.status,
  });

  factory DepartmentReviewerReadiness.fromJson(Map<String, dynamic> json) {
    final primary = json['primary'];
    return DepartmentReviewerReadiness(
      departmentId: json['department_id']?.toString() ?? '',
      departmentName: json['department_name']?.toString() ?? '',
      staffCount: (json['staff_count'] as num?)?.toInt() ?? 0,
      primaryName: primary is Map ? primary['reviewerName']?.toString() : null,
      backupCount: (json['backup_count'] as num?)?.toInt() ?? 0,
      status: switch (json['status']?.toString()) {
        'no_reviewer' => DepartmentReviewerStatus.noReviewer,
        'head_only' => DepartmentReviewerStatus.headOnly,
        'no_staff' => DepartmentReviewerStatus.noStaff,
        _ => DepartmentReviewerStatus.ready,
      },
    );
  }

  final String departmentId;
  final String departmentName;
  final int staffCount;
  final String? primaryName;
  final int backupCount;
  final DepartmentReviewerStatus status;

  bool get needsAttention =>
      status == DepartmentReviewerStatus.noReviewer ||
      status == DepartmentReviewerStatus.headOnly;

  /// Plain-language explanation for admins, or null when nothing is blocked.
  String? get problem => switch (status) {
    DepartmentReviewerStatus.noReviewer =>
      'No Department Head or backup reviewer. Staff cannot submit documents '
          'that route to their Department Head.',
    DepartmentReviewerStatus.headOnly =>
      '${primaryName ?? 'The Department Head'} has no backup reviewer, so '
          'documents they submit themselves cannot be routed.',
    _ => null,
  };

  static Future<List<DepartmentReviewerReadiness>> fetch() async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/departments/reviewer-readiness',
    );
    final raw = res.data?['departments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (e) => DepartmentReviewerReadiness.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }
}
