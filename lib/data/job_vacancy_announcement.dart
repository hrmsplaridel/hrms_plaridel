import 'package:supabase_flutter/supabase_flutter.dart';

/// One job vacancy entry (headline + description). Used when multiple hirings are listed.
class JobVacancyItem {
  const JobVacancyItem({this.headline, this.body});
  final String? headline;
  final String? body;
}

/// Single-row config for the Job Vacancies section on the landing page.
/// Managed by the RSP module in the admin dashboard. Supports multiple vacancy entries via [vacancies].
class JobVacancyAnnouncement {
  const JobVacancyAnnouncement({
    required this.hasVacancies,
    this.headline,
    this.body,
    this.vacancies = const [],
    this.updatedAt,
  });

  final bool hasVacancies;
  final String? headline;
  final String? body;
  /// Multiple job vacancy entries (headline + body). When non-empty, landing page shows each; else uses single [headline]/[body].
  final List<JobVacancyItem> vacancies;
  final DateTime? updatedAt;

  static const String tableName = 'job_vacancy_announcement';
  static const String defaultId = 'default';

  factory JobVacancyAnnouncement.fromJson(Map<String, dynamic> json) {
    List<JobVacancyItem> vacancies = [];
    final raw = json['vacancies'];
    if (raw is List && raw.isNotEmpty) {
      for (final e in raw) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          vacancies.add(JobVacancyItem(
            headline: m['headline']?.toString(),
            body: m['body']?.toString(),
          ));
        }
      }
    }
    if (vacancies.isEmpty && (json['headline'] != null || json['body'] != null)) {
      vacancies = [JobVacancyItem(headline: json['headline']?.toString(), body: json['body']?.toString())];
    }
    return JobVacancyAnnouncement(
      hasVacancies: json['has_vacancies'] as bool? ?? true,
      headline: json['headline'] as String?,
      body: json['body'] as String?,
      vacancies: vacancies,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  static String? _opt(String? s) => s == null || s.isEmpty ? null : s;

  Map<String, dynamic> toJson() {
    final list = vacancies.map((v) => {'headline': _opt(v.headline?.trim()), 'body': _opt(v.body?.trim())}).toList();
    final first = vacancies.isNotEmpty ? vacancies.first : null;
    return {
      'has_vacancies': hasVacancies,
      'headline': _opt(first?.headline?.trim()) ?? _opt(headline?.trim()),
      'body': _opt(first?.body?.trim()) ?? _opt(body?.trim()),
      'vacancies': list,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  JobVacancyAnnouncement copyWith({
    bool? hasVacancies,
    String? headline,
    String? body,
    List<JobVacancyItem>? vacancies,
    DateTime? updatedAt,
  }) {
    return JobVacancyAnnouncement(
      hasVacancies: hasVacancies ?? this.hasVacancies,
      headline: headline ?? this.headline,
      body: body ?? this.body,
      vacancies: vacancies ?? this.vacancies,
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

  /// Saves the announcement (upsert). Creates the default row if missing; otherwise updates. Requires authenticated user (admin).
  Future<void> update(JobVacancyAnnouncement announcement) async {
    final payload = Map<String, dynamic>.from(announcement.toJson())
      ..['id'] = JobVacancyAnnouncement.defaultId;
    await _client
        .from(JobVacancyAnnouncement.tableName)
        .upsert(payload, onConflict: 'id');
  }
}
