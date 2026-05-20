import '../api/client.dart';

/// One job vacancy entry (headline + optional details). Used when multiple hirings are listed.
class JobVacancyItem {
  const JobVacancyItem({
    this.headline,
    this.body,
    this.education,
    this.experience,
    this.training,
    this.closingDate,
    this.isClosed,
    this.maxApplicants,
    this.applicationCount,
  });

  final String? headline;
  /// Legacy single description; still read for older rows. Prefer [education], [experience], [training].
  final String? body;
  final String? education;
  final String? experience;
  final String? training;
  /// Due date / closing date for applications (YYYY-MM-DD). When past, backend stops accepting.
  final DateTime? closingDate;
  /// Computed by backend (`is_closed`) based on [closingDate] and current time.
  final bool? isClosed;

  /// When set (≥ 1), only this many applications with matching [position_applied_for] are allowed.
  final int? maxApplicants;

  /// Current application count for this vacancy key (from GET only; not sent on save).
  final int? applicationCount;

  /// Headline if non-empty, else body — matches how [position_applied_for] is stored when applying.
  String? get positionKey {
    final h = headline?.trim();
    if (h != null && h.isNotEmpty) return h;
    final b = body?.trim();
    if (b != null && b.isNotEmpty) return b;
    for (final s in [education, experience, training]) {
      final t = s?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  bool get hasStructuredDetails {
    for (final s in [education, experience, training]) {
      if (s != null && s.trim().isNotEmpty) return true;
    }
    return false;
  }

  bool get isApplicationQuotaFull {
    final max = maxApplicants;
    if (max == null || max < 1) return false;
    final c = applicationCount ?? 0;
    return c >= max;
  }

  static int? _parsePositiveInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v >= 1 ? v : null;
    final n = int.tryParse(v.toString().trim());
    if (n == null || n < 1) return null;
    return n;
  }

  static DateTime? _parseDateOnly(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // Accept both "YYYY-MM-DD" and ISO timestamps.
    final dt = DateTime.tryParse(s);
    return dt;
  }
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
          vacancies.add(
            JobVacancyItem(
              headline: m['headline']?.toString(),
              body: m['body']?.toString(),
              education: m['education']?.toString(),
              experience: m['experience']?.toString(),
              training: m['training']?.toString(),
              closingDate: JobVacancyItem._parseDateOnly(m['closing_date']),
              isClosed: m['is_closed'] == true,
              maxApplicants: JobVacancyItem._parsePositiveInt(
                m['max_applicants'],
              ),
              applicationCount: m['application_count'] is int
                  ? m['application_count'] as int
                  : int.tryParse(m['application_count']?.toString() ?? ''),
            ),
          );
        }
      }
    }
    if (vacancies.isEmpty &&
        (json['headline'] != null || json['body'] != null)) {
      vacancies = [
        JobVacancyItem(
          headline: json['headline']?.toString(),
          body: json['body']?.toString(),
          education: json['education']?.toString(),
          experience: json['experience']?.toString(),
          training: json['training']?.toString(),
          closingDate: JobVacancyItem._parseDateOnly(json['closing_date']),
          isClosed: json['is_closed'] == true,
          maxApplicants: JobVacancyItem._parsePositiveInt(
            json['max_applicants'],
          ),
          applicationCount: json['application_count'] is int
              ? json['application_count'] as int
              : int.tryParse(json['application_count']?.toString() ?? ''),
        ),
      ];
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
    final list = vacancies
        .map((v) {
          final ed = _opt(v.education?.trim());
          final ex = _opt(v.experience?.trim());
          final tr = _opt(v.training?.trim());
          final cd = v.closingDate;
          final closingDate = cd != null
              ? '${cd.year.toString().padLeft(4, '0')}-${cd.month.toString().padLeft(2, '0')}-${cd.day.toString().padLeft(2, '0')}'
              : null;
          return <String, dynamic>{
            'headline': _opt(v.headline?.trim()),
            'body': _opt(v.body?.trim()),
            if (ed != null) 'education': ed,
            if (ex != null) 'experience': ex,
            if (tr != null) 'training': tr,
            if (closingDate != null) 'closing_date': closingDate,
            if (v.maxApplicants != null && v.maxApplicants! >= 1)
              'max_applicants': v.maxApplicants,
          };
        })
        .toList();
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

/// Fetches and updates the job vacancy announcement (PostgreSQL via `/api/rsp/job-vacancies`).
class JobVacancyAnnouncementRepo {
  JobVacancyAnnouncementRepo._();
  static final JobVacancyAnnouncementRepo instance =
      JobVacancyAnnouncementRepo._();

  /// Fetches the current announcement. Public (no auth required).
  /// Returns default (hasVacancies: true, null headline/body) if no row or error.
  Future<JobVacancyAnnouncement> fetch() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/rsp/job-vacancies',
      );
      final data = res.data;
      if (data == null) return const JobVacancyAnnouncement(hasVacancies: true);
      return JobVacancyAnnouncement.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return const JobVacancyAnnouncement(hasVacancies: true);
    }
  }

  /// Saves the announcement (upsert). Creates the default row if missing; otherwise updates. Requires authenticated user (admin).
  Future<void> update(JobVacancyAnnouncement announcement) async {
    await ApiClient.instance.put(
      '/api/rsp/job-vacancies',
      data: announcement.toJson(),
    );
  }
}
