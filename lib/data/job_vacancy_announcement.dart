import 'package:supabase_flutter/supabase_flutter.dart';

/// Single-row config for the Job Vacancies section on the landing page.
/// Managed by the RSP module in the admin dashboard.
class JobVacancyAnnouncement {
  const JobVacancyAnnouncement({
    required this.hasVacancies,
    this.headline,
    this.body,
    this.updatedAt,
  });

  final bool hasVacancies;
  final String? headline;
  final String? body;
  final DateTime? updatedAt;

  static const String tableName = 'job_vacancy_announcement';
  static const String defaultId = 'default';

  factory JobVacancyAnnouncement.fromJson(Map<String, dynamic> json) {
    return JobVacancyAnnouncement(
      hasVacancies: json['has_vacancies'] as bool? ?? true,
      headline: json['headline'] as String?,
      body: json['body'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'has_vacancies': hasVacancies,
      'headline': headline?.trim().isEmpty == true ? null : headline?.trim(),
      'body': body?.trim().isEmpty == true ? null : body?.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  JobVacancyAnnouncement copyWith({
    bool? hasVacancies,
    String? headline,
    String? body,
    DateTime? updatedAt,
  }) {
    return JobVacancyAnnouncement(
      hasVacancies: hasVacancies ?? this.hasVacancies,
      headline: headline ?? this.headline,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Fetches and updates the job vacancy announcement in Supabase.
class JobVacancyAnnouncementRepo {
  JobVacancyAnnouncementRepo._();
  static final JobVacancyAnnouncementRepo instance = JobVacancyAnnouncementRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetches the current announcement. Public (no auth required).
  /// Returns default (hasVacancies: true, null headline/body) if no row or error.
  Future<JobVacancyAnnouncement> fetch() async {
    try {
      final res = await _client
          .from(JobVacancyAnnouncement.tableName)
          .select()
          .eq('id', JobVacancyAnnouncement.defaultId)
          .maybeSingle();
      if (res == null) return const JobVacancyAnnouncement(hasVacancies: true);
      return JobVacancyAnnouncement.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return const JobVacancyAnnouncement(hasVacancies: true);
    }
  }

  /// Updates the announcement. Requires authenticated user (admin).
  Future<void> update(JobVacancyAnnouncement announcement) async {
    await _client
        .from(JobVacancyAnnouncement.tableName)
        .update(announcement.toJson())
        .eq('id', JobVacancyAnnouncement.defaultId);
  }
}
