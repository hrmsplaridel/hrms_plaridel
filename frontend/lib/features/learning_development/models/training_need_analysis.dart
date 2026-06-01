import 'rsp_ld_saved_entries_api.dart';

/// One row in the Training Need Analysis table.
class TrainingNeedAnalysisRow {
  const TrainingNeedAnalysisRow({
    this.namePosition,
    this.goal,
    this.behavior,
    this.skillsKnowledge,
    this.needForTraining,
    this.trainingRecommendations,
  });

  final String? namePosition;
  final String? goal;
  final String? behavior;
  final String? skillsKnowledge;
  final String? needForTraining;
  final String? trainingRecommendations;

  factory TrainingNeedAnalysisRow.fromJson(Map<String, dynamic> json) {
    return TrainingNeedAnalysisRow(
      namePosition: json['name_position']?.toString(),
      goal: json['goal']?.toString(),
      behavior: json['behavior']?.toString(),
      skillsKnowledge: json['skills_knowledge']?.toString(),
      needForTraining: json['need_for_training']?.toString(),
      trainingRecommendations: json['training_recommendations']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name_position': namePosition,
    'goal': goal,
    'behavior': behavior,
    'skills_knowledge': skillsKnowledge,
    'need_for_training': needForTraining,
    'training_recommendations': trainingRecommendations,
  };
}

/// Training Need Analysis and Consolidated Report entry (L&D).
class TrainingNeedAnalysisEntry {
  const TrainingNeedAnalysisEntry({
    this.id,
    this.cyYear,
    this.department,
    this.rows = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? cyYear;
  final String? department;
  final List<TrainingNeedAnalysisRow> rows;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'training_need_analysis_entries';

  factory TrainingNeedAnalysisEntry.fromJson(Map<String, dynamic> json) {
    List<TrainingNeedAnalysisRow> list = [];
    final raw = json['rows'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(
            TrainingNeedAnalysisRow.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return TrainingNeedAnalysisEntry(
      id: json['id']?.toString(),
      cyYear: json['cy_year']?.toString(),
      department: json['department']?.toString(),
      rows: list,
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
      'cy_year': cyYear,
      'department': department,
      'rows': rows.map((r) => r.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class TrainingNeedAnalysisRepo {
  TrainingNeedAnalysisRepo._();
  static final TrainingNeedAnalysisRepo instance = TrainingNeedAnalysisRepo._();

  Future<List<TrainingNeedAnalysisEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      TrainingNeedAnalysisEntry.tableName,
    );
    return rows.map(TrainingNeedAnalysisEntry.fromJson).toList();
  }

  Future<TrainingNeedAnalysisEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      TrainingNeedAnalysisEntry.tableName,
      id,
    );
    return row == null ? null : TrainingNeedAnalysisEntry.fromJson(row);
  }

  Future<void> insert(TrainingNeedAnalysisEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      TrainingNeedAnalysisEntry.tableName,
      payload,
    );
  }

  Future<void> update(TrainingNeedAnalysisEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      TrainingNeedAnalysisEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      TrainingNeedAnalysisEntry.tableName,
      id,
    );
  }
}
