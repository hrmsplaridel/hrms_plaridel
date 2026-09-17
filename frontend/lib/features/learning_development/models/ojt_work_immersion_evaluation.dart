import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// One OJT / Work Immersion Evaluation (RSP).
class OjtWorkImmersionEvaluation {
  const OjtWorkImmersionEvaluation({
    this.id,
    this.ojtImmersion,
    this.school,
    this.interviewDate,
    this.problemSolvingScore,
    this.problemSolvingNotes,
    this.communicationScore,
    this.communicationNotes,
    this.teamworkScore,
    this.teamworkNotes,
    this.adaptabilityScore,
    this.adaptabilityNotes,
    this.overallRecommendation,
    this.keyStrengths,
    this.keyConcerns,
    this.interviewer,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? ojtImmersion;
  final String? school;
  final String? interviewDate;
  final int? problemSolvingScore;
  final String? problemSolvingNotes;
  final int? communicationScore;
  final String? communicationNotes;
  final int? teamworkScore;
  final String? teamworkNotes;
  final int? adaptabilityScore;
  final String? adaptabilityNotes;
  final String? overallRecommendation;
  final String? keyStrengths;
  final String? keyConcerns;
  final String? interviewer;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'ojt_work_immersion_evaluation_entries';

  static const List<String> recommendationOptions = [
    'Recommended',
    'For Further Review',
    'Not Recommended',
  ];

  static bool isValidScore(int? score) =>
      score != null && score >= 1 && score <= 5;

  /// Sum of the four criterion scores. Null until every criterion is scored.
  int? get totalScore {
    final scores = [
      problemSolvingScore,
      communicationScore,
      teamworkScore,
      adaptabilityScore,
    ];
    if (scores.any((s) => !isValidScore(s))) return null;
    return scores.fold<int>(0, (sum, s) => sum + s!);
  }

  static int? _parseScore(dynamic v) {
    if (v == null) return null;
    final n = int.tryParse(v.toString().trim());
    if (n == null || n < 1 || n > 5) return null;
    return n;
  }

  factory OjtWorkImmersionEvaluation.fromJson(Map<String, dynamic> json) {
    return OjtWorkImmersionEvaluation(
      id: json['id']?.toString(),
      ojtImmersion: json['ojt_immersion']?.toString(),
      school: json['school']?.toString(),
      interviewDate: json['interview_date']?.toString(),
      problemSolvingScore: _parseScore(json['problem_solving_score']),
      problemSolvingNotes: json['problem_solving_notes']?.toString(),
      communicationScore: _parseScore(json['communication_score']),
      communicationNotes: json['communication_notes']?.toString(),
      teamworkScore: _parseScore(json['teamwork_score']),
      teamworkNotes: json['teamwork_notes']?.toString(),
      adaptabilityScore: _parseScore(json['adaptability_score']),
      adaptabilityNotes: json['adaptability_notes']?.toString(),
      overallRecommendation: json['overall_recommendation']?.toString(),
      keyStrengths: json['key_strengths']?.toString(),
      keyConcerns: json['key_concerns']?.toString(),
      interviewer: json['interviewer']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'ojt_immersion': ojtImmersion,
      'school': school,
      'interview_date': interviewDate,
      'problem_solving_score': problemSolvingScore,
      'problem_solving_notes': problemSolvingNotes,
      'communication_score': communicationScore,
      'communication_notes': communicationNotes,
      'teamwork_score': teamworkScore,
      'teamwork_notes': teamworkNotes,
      'adaptability_score': adaptabilityScore,
      'adaptability_notes': adaptabilityNotes,
      'total_score': totalScore,
      'overall_recommendation': overallRecommendation,
      'key_strengths': keyStrengths,
      'key_concerns': keyConcerns,
      'interviewer': interviewer,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class OjtWorkImmersionEvaluationRepo {
  OjtWorkImmersionEvaluationRepo._();
  static final OjtWorkImmersionEvaluationRepo instance =
      OjtWorkImmersionEvaluationRepo._();

  Future<List<OjtWorkImmersionEvaluation>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      OjtWorkImmersionEvaluation.tableName,
    );
    return rows.map(OjtWorkImmersionEvaluation.fromJson).toList();
  }

  Future<void> insert(OjtWorkImmersionEvaluation entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      OjtWorkImmersionEvaluation.tableName,
      payload,
    );
  }

  Future<void> update(OjtWorkImmersionEvaluation entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      OjtWorkImmersionEvaluation.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      OjtWorkImmersionEvaluation.tableName,
      id,
    );
  }
}
