import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// One applicant row in an Applicants Profile (name, course, address, sex, age, civil status, remark).
class ApplicantsProfileApplicant {
  const ApplicantsProfileApplicant({
    this.name,
    this.course,
    this.address,
    this.sex,
    this.age,
    this.civilStatus,
    this.remarkDisability,
  });

  final String? name;
  final String? course;
  final String? address;
  final String? sex;
  final String? age;
  final String? civilStatus;
  final String? remarkDisability;

  factory ApplicantsProfileApplicant.fromJson(Map<String, dynamic> json) {
    return ApplicantsProfileApplicant(
      name: json['name']?.toString(),
      course: json['course']?.toString(),
      address: json['address']?.toString(),
      sex: json['sex']?.toString(),
      age: json['age']?.toString(),
      civilStatus: json['civil_status']?.toString(),
      remarkDisability: json['remark_disability']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'course': course,
    'address': address,
    'sex': sex,
    'age': age,
    'civil_status': civilStatus,
    'remark_disability': remarkDisability,
  };
}

/// One Applicants Profile entry: job vacancy details + list of applicants.
class ApplicantsProfileEntry {
  const ApplicantsProfileEntry({
    this.id,
    this.positionAppliedFor,
    this.minimumRequirements,
    this.dateOfPosting,
    this.closingDate,
    this.applicants = const [],
    this.preparedBy,
    this.checkedBy,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? positionAppliedFor;
  final String? minimumRequirements;
  final String? dateOfPosting;
  final String? closingDate;
  final List<ApplicantsProfileApplicant> applicants;
  final String? preparedBy;
  final String? checkedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'applicants_profile_entries';

  /// Max applicant rows per printed/UI form page before continuation.
  static const int applicantsPerFormPage = 10;

  factory ApplicantsProfileEntry.fromJson(Map<String, dynamic> json) {
    List<ApplicantsProfileApplicant> list = [];
    final raw = json['applicants'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(
            ApplicantsProfileApplicant.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return ApplicantsProfileEntry(
      id: json['id']?.toString(),
      positionAppliedFor: json['position_applied_for']?.toString(),
      minimumRequirements: json['minimum_requirements']?.toString(),
      dateOfPosting: json['date_of_posting']?.toString(),
      closingDate: json['closing_date']?.toString(),
      applicants: list,
      preparedBy: json['prepared_by']?.toString(),
      checkedBy: json['checked_by']?.toString(),
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
      'minimum_requirements': minimumRequirements,
      'date_of_posting': dateOfPosting,
      'closing_date': closingDate,
      'applicants': applicants.map((a) => a.toJson()).toList(),
      'prepared_by': preparedBy,
      'checked_by': checkedBy,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class ApplicantsProfileRepo {
  ApplicantsProfileRepo._();
  static final ApplicantsProfileRepo instance = ApplicantsProfileRepo._();

  Future<List<ApplicantsProfileEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      ApplicantsProfileEntry.tableName,
    );
    return rows.map(ApplicantsProfileEntry.fromJson).toList();
  }

  Future<ApplicantsProfileEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      ApplicantsProfileEntry.tableName,
      id,
    );
    return row == null ? null : ApplicantsProfileEntry.fromJson(row);
  }

  Future<void> insert(ApplicantsProfileEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      ApplicantsProfileEntry.tableName,
      payload,
    );
  }

  Future<void> update(ApplicantsProfileEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      ApplicantsProfileEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(ApplicantsProfileEntry.tableName, id);
  }
}
