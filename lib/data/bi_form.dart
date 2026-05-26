import 'rsp_ld_saved_entries_api.dart';

/// One Background Investigation (BI) form entry: applicant, respondent,
/// competencies (page 1), functional areas & performance (page 2),
/// other relevant information (page 3).
class BiFormEntry {
  const BiFormEntry({
    this.id,
    required this.applicantName,
    this.applicantDepartment,
    this.applicantPosition,
    this.positionAppliedFor,
    required this.respondentName,
    this.respondentPosition,
    required this.respondentRelationship,
    this.rating1,
    this.rating2,
    this.rating3,
    this.rating4,
    this.rating5,
    this.rating6,
    this.rating7,
    this.rating8,
    this.rating9,
    this.functionalAreas = const [],
    this.otherFunctionalArea,
    this.performance3Years,
    this.challengesCoping,
    this.complianceAttendance,
    this.otherRelevantInformation,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String applicantName;
  final String? applicantDepartment;
  final String? applicantPosition;
  final String? positionAppliedFor;
  final String respondentName;
  final String? respondentPosition;
  /// supervisor | peer | subordinate
  final String respondentRelationship;
  final int? rating1;
  final int? rating2;
  final int? rating3;
  final int? rating4;
  final int? rating5;
  final int? rating6;
  final int? rating7;
  final int? rating8;
  final int? rating9;
  final List<String> functionalAreas;
  final String? otherFunctionalArea;
  final String? performance3Years;
  final String? challengesCoping;
  final String? complianceAttendance;
  final String? otherRelevantInformation;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'bi_form_entries';

  static const List<String> relationshipOptions = [
    'supervisor',
    'peer',
    'subordinate',
  ];

  /// Functional area checkboxes (BI form page 2).
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

  /// Core competency descriptions (9 areas) for the BI form.
  static const List<String> competencyDescriptions = [
    'Demonstrate compliance policies, rules and other standards set by CSC/ and agency.',
    'Complies with CSC/ agency established standards of delivery of service level agreements and deliveries explicit requirements of clients.',
    'Provides timely solutions to problems and decision dilemmas that have clear-cut options and/or choices wherein solutions are available and can be accessed from a database or gleaned from an existing policy on process.',
    'Responds effectively to guidelines and feedback on one\'s performance. Wellbeing and learning discipline.',
    'Effectively deliveries messages that simply focus on data facts or information and requires minimal preparations or can be supported by available communication materials.',
    'Refers to and/or uses existing communication materials or templates to produce own written work.',
    'Demonstrates an awareness of base principles of innovation.',
    'Designs and implements plans focused on one\'s functional group or area of focus and involves team member from the same group.',
    'Works with data to generate relevant information.',
  ];

  factory BiFormEntry.fromJson(Map<String, dynamic> json) {
    List<String> areas = [];
    final rawAreas = json['functional_areas'];
    if (rawAreas is List) {
      for (final e in rawAreas) {
        if (e != null) areas.add(e.toString());
      }
    }
    return BiFormEntry(
      id: json['id']?.toString(),
      applicantName: json['applicant_name'] as String? ?? '',
      applicantDepartment: json['applicant_department']?.toString(),
      applicantPosition: json['applicant_position']?.toString(),
      positionAppliedFor: json['position_applied_for']?.toString(),
      respondentName: json['respondent_name'] as String? ?? '',
      respondentPosition: json['respondent_position']?.toString(),
      respondentRelationship:
          json['respondent_relationship'] as String? ?? 'supervisor',
      rating1: _parseRating(json['rating_1']),
      rating2: _parseRating(json['rating_2']),
      rating3: _parseRating(json['rating_3']),
      rating4: _parseRating(json['rating_4']),
      rating5: _parseRating(json['rating_5']),
      rating6: _parseRating(json['rating_6']),
      rating7: _parseRating(json['rating_7']),
      rating8: _parseRating(json['rating_8']),
      rating9: _parseRating(json['rating_9']),
      functionalAreas: areas,
      otherFunctionalArea: json['other_functional_area']?.toString(),
      performance3Years: json['performance_3_years']?.toString(),
      challengesCoping: json['challenges_coping']?.toString(),
      complianceAttendance: json['compliance_attendance']?.toString(),
      otherRelevantInformation: json['other_relevant_information']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  static int? _parseRating(dynamic v) {
    if (v == null) return null;
    if (v is int && v >= 1 && v <= 5) return v;
    final n = int.tryParse(v.toString());
    return n != null && n >= 1 && n <= 5 ? n : null;
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'applicant_name': applicantName,
      'applicant_department': applicantDepartment,
      'applicant_position': applicantPosition,
      'position_applied_for': positionAppliedFor,
      'respondent_name': respondentName,
      'respondent_position': respondentPosition,
      'respondent_relationship': respondentRelationship,
      'rating_1': rating1,
      'rating_2': rating2,
      'rating_3': rating3,
      'rating_4': rating4,
      'rating_5': rating5,
      'rating_6': rating6,
      'rating_7': rating7,
      'rating_8': rating8,
      'rating_9': rating9,
      'functional_areas': functionalAreas,
      'other_functional_area': otherFunctionalArea,
      'performance_3_years': performance3Years,
      'challenges_coping': challengesCoping,
      'compliance_attendance': complianceAttendance,
      'other_relevant_information': otherRelevantInformation,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class BiFormRepo {
  BiFormRepo._();
  static final BiFormRepo instance = BiFormRepo._();

  Future<List<BiFormEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(BiFormEntry.tableName);
    return rows.map(BiFormEntry.fromJson).toList();
  }

  Future<BiFormEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(BiFormEntry.tableName, id);
    return row == null ? null : BiFormEntry.fromJson(row);
  }

  Future<void> insert(BiFormEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(BiFormEntry.tableName, payload);
  }

  Future<void> update(BiFormEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      BiFormEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(BiFormEntry.tableName, id);
  }
}
