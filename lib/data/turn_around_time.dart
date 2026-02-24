import 'package:supabase_flutter/supabase_flutter.dart';

/// One applicant row in the Turn-Around Time table (no pre-filled values).
class TurnAroundTimeApplicant {
  const TurnAroundTimeApplicant({
    this.name,
    this.dateInitialAssessment,
    this.dateContractExam,
    this.skillsTradeExamResult,
    this.dateDeliberation,
    this.dateJobOffer,
    this.acceptanceDate,
    this.dateAssumptionToDuty,
    this.noOfDaysToFillUp,
    this.overallCostPerHire,
  });

  final String? name;
  final String? dateInitialAssessment;
  final String? dateContractExam;
  final String? skillsTradeExamResult;
  final String? dateDeliberation;
  final String? dateJobOffer;
  final String? acceptanceDate;
  final String? dateAssumptionToDuty;
  final String? noOfDaysToFillUp;
  final String? overallCostPerHire;

  factory TurnAroundTimeApplicant.fromJson(Map<String, dynamic> json) {
    return TurnAroundTimeApplicant(
      name: json['name']?.toString(),
      dateInitialAssessment: json['date_initial_assessment']?.toString(),
      dateContractExam: json['date_contract_exam']?.toString(),
      skillsTradeExamResult: json['skills_trade_exam_result']?.toString(),
      dateDeliberation: json['date_deliberation']?.toString(),
      dateJobOffer: json['date_job_offer']?.toString(),
      acceptanceDate: json['acceptance_date']?.toString(),
      dateAssumptionToDuty: json['date_assumption_to_duty']?.toString(),
      noOfDaysToFillUp: json['no_of_days_to_fill_up']?.toString(),
      overallCostPerHire: json['overall_cost_per_hire']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'date_initial_assessment': dateInitialAssessment,
        'date_contract_exam': dateContractExam,
        'skills_trade_exam_result': skillsTradeExamResult,
        'date_deliberation': dateDeliberation,
        'date_job_offer': dateJobOffer,
        'acceptance_date': acceptanceDate,
        'date_assumption_to_duty': dateAssumptionToDuty,
        'no_of_days_to_fill_up': noOfDaysToFillUp,
        'overall_cost_per_hire': overallCostPerHire,
      };
}

/// One Turn-Around Time form entry (form structure only).
class TurnAroundTimeEntry {
  const TurnAroundTimeEntry({
    this.id,
    this.position,
    this.office,
    this.noOfVacantPosition,
    this.dateOfPublication,
    this.endSearch,
    this.qs,
    this.applicants = const [],
    this.preparedByName,
    this.preparedByTitle,
    this.notedByName,
    this.notedByTitle,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? position;
  final String? office;
  final String? noOfVacantPosition;
  final String? dateOfPublication;
  final String? endSearch;
  final String? qs;
  final List<TurnAroundTimeApplicant> applicants;
  final String? preparedByName;
  final String? preparedByTitle;
  final String? notedByName;
  final String? notedByTitle;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'turn_around_time_entries';

  factory TurnAroundTimeEntry.fromJson(Map<String, dynamic> json) {
    List<TurnAroundTimeApplicant> list = [];
    final raw = json['applicants'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(TurnAroundTimeApplicant.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return TurnAroundTimeEntry(
      id: json['id']?.toString(),
      position: json['position']?.toString(),
      office: json['office']?.toString(),
      noOfVacantPosition: json['no_of_vacant_position']?.toString(),
      dateOfPublication: json['date_of_publication']?.toString(),
      endSearch: json['end_search']?.toString(),
      qs: json['qs']?.toString(),
      applicants: list,
      preparedByName: json['prepared_by_name']?.toString(),
      preparedByTitle: json['prepared_by_title']?.toString(),
      notedByName: json['noted_by_name']?.toString(),
      notedByTitle: json['noted_by_title']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'position': position,
      'office': office,
      'no_of_vacant_position': noOfVacantPosition,
      'date_of_publication': dateOfPublication,
      'end_search': endSearch,
      'qs': qs,
      'applicants': applicants.map((a) => a.toJson()).toList(),
      'prepared_by_name': preparedByName,
      'prepared_by_title': preparedByTitle,
      'noted_by_name': notedByName,
      'noted_by_title': notedByTitle,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class TurnAroundTimeRepo {
  TurnAroundTimeRepo._();
  static final TurnAroundTimeRepo instance = TurnAroundTimeRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<TurnAroundTimeEntry>> list() async {
    final res = await _client
        .from(TurnAroundTimeEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => TurnAroundTimeEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<TurnAroundTimeEntry?> get(String id) async {
    final res = await _client
        .from(TurnAroundTimeEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : TurnAroundTimeEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(TurnAroundTimeEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(TurnAroundTimeEntry.tableName).insert(payload);
  }

  Future<void> update(TurnAroundTimeEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(TurnAroundTimeEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(TurnAroundTimeEntry.tableName).delete().eq('id', id);
  }
}
