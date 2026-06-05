import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// Work Experience Sheet (HRMD) — position, minimum standards, job description.
class WorkExperienceSheetEntry {
  const WorkExperienceSheetEntry({
    this.id,
    this.positionAppliedFor,
    this.department,
    this.minEducation,
    this.minExperience,
    this.minTraining,
    this.minEligibility,
    this.jobDescriptionLastWork,
    this.applicantName,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? positionAppliedFor;
  final String? department;
  final String? minEducation;
  final String? minExperience;
  final String? minTraining;
  final String? minEligibility;
  final String? jobDescriptionLastWork;
  final String? applicantName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'work_experience_sheet_entries';

  factory WorkExperienceSheetEntry.fromJson(Map<String, dynamic> json) {
    return WorkExperienceSheetEntry(
      id: json['id']?.toString(),
      positionAppliedFor: json['position_applied_for']?.toString(),
      department: json['department']?.toString(),
      minEducation: json['min_education']?.toString(),
      minExperience: json['min_experience']?.toString(),
      minTraining: json['min_training']?.toString(),
      minEligibility: json['min_eligibility']?.toString(),
      jobDescriptionLastWork: json['job_description_last_work']?.toString(),
      applicantName: json['applicant_name']?.toString(),
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
      'position_applied_for': positionAppliedFor,
      'department': department,
      'min_education': minEducation,
      'min_experience': minExperience,
      'min_training': minTraining,
      'min_eligibility': minEligibility,
      'job_description_last_work': jobDescriptionLastWork,
      'applicant_name': applicantName,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class WorkExperienceSheetRepo {
  WorkExperienceSheetRepo._();
  static final WorkExperienceSheetRepo instance = WorkExperienceSheetRepo._();

  Future<List<WorkExperienceSheetEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      WorkExperienceSheetEntry.tableName,
    );
    return rows.map(WorkExperienceSheetEntry.fromJson).toList();
  }

  Future<WorkExperienceSheetEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      WorkExperienceSheetEntry.tableName,
      id,
    );
    return row == null ? null : WorkExperienceSheetEntry.fromJson(row);
  }

  Future<void> insert(WorkExperienceSheetEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      WorkExperienceSheetEntry.tableName,
      payload,
    );
  }

  Future<void> update(WorkExperienceSheetEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      WorkExperienceSheetEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      WorkExperienceSheetEntry.tableName,
      id,
    );
  }
}
