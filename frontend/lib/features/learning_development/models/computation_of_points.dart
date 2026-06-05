import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// One candidate row on the Computation of Points (PSB) form.
class ComputationOfPointsCandidate {
  const ComputationOfPointsCandidate({
    this.name,
    this.position,
    this.salaryGrade,
    this.rate,
    this.education,
    this.eligibility,
    this.experience,
    this.training,
    this.performance,
    this.potential,
    this.workAttitude,
    this.total,
    this.rank,
  });

  final String? name;
  final String? position;
  final String? salaryGrade;
  final String? rate;
  final String? education;
  final String? eligibility;
  final String? experience;
  final String? training;
  final String? performance;
  final String? potential;
  final String? workAttitude;
  final String? total;
  final String? rank;

  factory ComputationOfPointsCandidate.fromJson(Map<String, dynamic> json) {
    return ComputationOfPointsCandidate(
      name: json['name']?.toString(),
      position: json['position']?.toString(),
      salaryGrade: json['salary_grade']?.toString(),
      rate: json['rate']?.toString(),
      education: json['education']?.toString(),
      eligibility: json['eligibility']?.toString(),
      experience: json['experience']?.toString(),
      training: json['training']?.toString(),
      performance: json['performance']?.toString(),
      potential: json['potential']?.toString(),
      workAttitude: json['work_attitude']?.toString(),
      total: json['total']?.toString(),
      rank: json['rank']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'position': position,
    'salary_grade': salaryGrade,
    'rate': rate,
    'education': education,
    'eligibility': eligibility,
    'experience': experience,
    'training': training,
    'performance': performance,
    'potential': potential,
    'work_attitude': workAttitude,
    'total': total,
    'rank': rank,
  };
}

/// Personnel Selection Board — Computation of Points form entry.
class ComputationOfPointsEntry {
  const ComputationOfPointsEntry({
    this.id,
    this.date,
    this.positionLevel,
    this.position,
    this.salaryGrade,
    this.rate,
    this.office,
    this.minEducation,
    this.minTraining,
    this.minExperience,
    this.minEligibility,
    this.candidates = const [],
    this.preparedByName,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? date;
  final String? positionLevel;
  final String? position;
  final String? salaryGrade;
  final String? rate;
  final String? office;
  final String? minEducation;
  final String? minTraining;
  final String? minExperience;
  final String? minEligibility;
  final List<ComputationOfPointsCandidate> candidates;
  final String? preparedByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'computation_of_points_entries';

  factory ComputationOfPointsEntry.fromJson(Map<String, dynamic> json) {
    final list = <ComputationOfPointsCandidate>[];
    final raw = json['candidates'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(
            ComputationOfPointsCandidate.fromJson(
              Map<String, dynamic>.from(e),
            ),
          );
        }
      }
    }
    return ComputationOfPointsEntry(
      id: json['id']?.toString(),
      date: json['date']?.toString(),
      positionLevel: json['position_level']?.toString(),
      position: json['position']?.toString(),
      salaryGrade: json['salary_grade']?.toString(),
      rate: json['rate']?.toString(),
      office: json['office']?.toString(),
      minEducation: json['min_education']?.toString(),
      minTraining: json['min_training']?.toString(),
      minExperience: json['min_experience']?.toString(),
      minEligibility: json['min_eligibility']?.toString(),
      candidates: list,
      preparedByName: json['prepared_by_name']?.toString(),
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
      'date': date,
      'position_level': positionLevel,
      'position': position,
      'salary_grade': salaryGrade,
      'rate': rate,
      'office': office,
      'min_education': minEducation,
      'min_training': minTraining,
      'min_experience': minExperience,
      'min_eligibility': minEligibility,
      'candidates': candidates.map((c) => c.toJson()).toList(),
      'prepared_by_name': preparedByName,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class ComputationOfPointsRepo {
  ComputationOfPointsRepo._();
  static final ComputationOfPointsRepo instance = ComputationOfPointsRepo._();

  Future<List<ComputationOfPointsEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      ComputationOfPointsEntry.tableName,
    );
    return rows.map(ComputationOfPointsEntry.fromJson).toList();
  }

  Future<ComputationOfPointsEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      ComputationOfPointsEntry.tableName,
      id,
    );
    return row == null ? null : ComputationOfPointsEntry.fromJson(row);
  }

  Future<void> insert(ComputationOfPointsEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      ComputationOfPointsEntry.tableName,
      payload,
    );
  }

  Future<void> update(ComputationOfPointsEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      ComputationOfPointsEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      ComputationOfPointsEntry.tableName,
      id,
    );
  }
}
