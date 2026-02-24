import 'package:supabase_flutter/supabase_flutter.dart';

/// One candidate row in the Comparative Assessment table (no pre-filled values).
class ComparativeAssessmentCandidate {
  const ComparativeAssessmentCandidate({
    this.candidateName,
    this.presentPositionSalary,
    this.education,
    this.trainingHrs,
    this.relatedExperience,
    this.eligibility,
    this.performanceRating,
    this.remarks,
  });

  final String? candidateName;
  final String? presentPositionSalary;
  final String? education;
  final String? trainingHrs;
  final String? relatedExperience;
  final String? eligibility;
  final String? performanceRating;
  final String? remarks;

  factory ComparativeAssessmentCandidate.fromJson(Map<String, dynamic> json) {
    return ComparativeAssessmentCandidate(
      candidateName: json['candidate_name']?.toString(),
      presentPositionSalary: json['present_position_salary']?.toString(),
      education: json['education']?.toString(),
      trainingHrs: json['training_hrs']?.toString(),
      relatedExperience: json['related_experience']?.toString(),
      eligibility: json['eligibility']?.toString(),
      performanceRating: json['performance_rating']?.toString(),
      remarks: json['remarks']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'candidate_name': candidateName,
        'present_position_salary': presentPositionSalary,
        'education': education,
        'training_hrs': trainingHrs,
        'related_experience': relatedExperience,
        'eligibility': eligibility,
        'performance_rating': performanceRating,
        'remarks': remarks,
      };
}

/// One Comparative Assessment of Candidates for Promotion entry (form structure only).
class ComparativeAssessmentEntry {
  const ComparativeAssessmentEntry({
    this.id,
    this.positionToBeFilled,
    this.minReqEducation,
    this.minReqExperience,
    this.minReqEligibility,
    this.minReqTraining,
    this.candidates = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? positionToBeFilled;
  final String? minReqEducation;
  final String? minReqExperience;
  final String? minReqEligibility;
  final String? minReqTraining;
  final List<ComparativeAssessmentCandidate> candidates;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'comparative_assessment_entries';

  factory ComparativeAssessmentEntry.fromJson(Map<String, dynamic> json) {
    List<ComparativeAssessmentCandidate> list = [];
    final raw = json['candidates'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(ComparativeAssessmentCandidate.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ComparativeAssessmentEntry(
      id: json['id']?.toString(),
      positionToBeFilled: json['position_to_be_filled']?.toString(),
      minReqEducation: json['min_req_education']?.toString(),
      minReqExperience: json['min_req_experience']?.toString(),
      minReqEligibility: json['min_req_eligibility']?.toString(),
      minReqTraining: json['min_req_training']?.toString(),
      candidates: list,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'position_to_be_filled': positionToBeFilled,
      'min_req_education': minReqEducation,
      'min_req_experience': minReqExperience,
      'min_req_eligibility': minReqEligibility,
      'min_req_training': minReqTraining,
      'candidates': candidates.map((c) => c.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class ComparativeAssessmentRepo {
  ComparativeAssessmentRepo._();
  static final ComparativeAssessmentRepo instance = ComparativeAssessmentRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<ComparativeAssessmentEntry>> list() async {
    final res = await _client
        .from(ComparativeAssessmentEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => ComparativeAssessmentEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ComparativeAssessmentEntry?> get(String id) async {
    final res = await _client
        .from(ComparativeAssessmentEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : ComparativeAssessmentEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(ComparativeAssessmentEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(ComparativeAssessmentEntry.tableName).insert(payload);
  }

  Future<void> update(ComparativeAssessmentEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(ComparativeAssessmentEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(ComparativeAssessmentEntry.tableName).delete().eq('id', id);
  }
}
