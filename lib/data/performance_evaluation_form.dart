import 'rsp_ld_saved_entries_api.dart';

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

  Future<List<PerformanceEvaluationEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(PerformanceEvaluationEntry.tableName);
    return rows.map(PerformanceEvaluationEntry.fromJson).toList();
  }

  Future<PerformanceEvaluationEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(PerformanceEvaluationEntry.tableName, id);
    return row == null ? null : PerformanceEvaluationEntry.fromJson(row);
  }

  Future<void> insert(PerformanceEvaluationEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(PerformanceEvaluationEntry.tableName, payload);
  }

  Future<void> update(PerformanceEvaluationEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      PerformanceEvaluationEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(PerformanceEvaluationEntry.tableName, id);
  }
}
