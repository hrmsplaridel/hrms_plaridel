import 'package:supabase_flutter/supabase_flutter.dart';

/// One Performance / Functional Evaluation form entry.
class PerformanceEvaluationEntry {
  const PerformanceEvaluationEntry({
    this.id,
    this.applicantName,
    this.functionalAreas = const [],
    this.otherFunctionalArea,
    this.performance3Years,
    this.challengesCoping,
    this.complianceAttendance,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? applicantName;
  final List<String> functionalAreas;
  final String? otherFunctionalArea;
  final String? performance3Years;
  final String? challengesCoping;
  final String? complianceAttendance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'performance_evaluation_entries';

  /// Functional area options (checkboxes) from the form.
  static const List<String> functionalAreaOptions = [
    'Accounting',
    'Audit',
    'Corporate Communications',
    'Information Technology',
    'Strategic and Corporate Planning',
    'Policy Interpretation and Implementation',
    'Program Management',
    'Records Management',
    'Supplies and Property Management',
  ];

  factory PerformanceEvaluationEntry.fromJson(Map<String, dynamic> json) {
    List<String> areas = [];
    final raw = json['functional_areas'];
    if (raw is List) {
      for (final e in raw) {
        if (e != null) areas.add(e.toString());
      }
    }
    return PerformanceEvaluationEntry(
      id: json['id']?.toString(),
      applicantName: json['applicant_name']?.toString(),
      functionalAreas: areas,
      otherFunctionalArea: json['other_functional_area']?.toString(),
      performance3Years: json['performance_3_years']?.toString(),
      challengesCoping: json['challenges_coping']?.toString(),
      complianceAttendance: json['compliance_attendance']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'applicant_name': applicantName,
      'functional_areas': functionalAreas,
      'other_functional_area': otherFunctionalArea,
      'performance_3_years': performance3Years,
      'challenges_coping': challengesCoping,
      'compliance_attendance': complianceAttendance,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class PerformanceEvaluationRepo {
  PerformanceEvaluationRepo._();
  static final PerformanceEvaluationRepo instance = PerformanceEvaluationRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<PerformanceEvaluationEntry>> list() async {
    final res = await _client
        .from(PerformanceEvaluationEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => PerformanceEvaluationEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PerformanceEvaluationEntry?> get(String id) async {
    final res = await _client
        .from(PerformanceEvaluationEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : PerformanceEvaluationEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(PerformanceEvaluationEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(PerformanceEvaluationEntry.tableName).insert(payload);
  }

  Future<void> update(PerformanceEvaluationEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(PerformanceEvaluationEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(PerformanceEvaluationEntry.tableName).delete().eq('id', id);
  }
}
