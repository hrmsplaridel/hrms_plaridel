import 'package:supabase_flutter/supabase_flutter.dart';

/// One row in the IDP development plan table (objectives, L&D program, requirements, time frame).
class IdpPlanRow {
  const IdpPlanRow({
    this.objectives,
    this.ldProgram,
    this.requirements,
    this.timeFrame,
  });

  final String? objectives;
  final String? ldProgram;
  final String? requirements;
  final String? timeFrame;

  factory IdpPlanRow.fromJson(Map<String, dynamic> json) {
    return IdpPlanRow(
      objectives: json['objectives']?.toString(),
      ldProgram: json['ld_program']?.toString(),
      requirements: json['requirements']?.toString(),
      timeFrame: json['time_frame']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'objectives': objectives,
        'ld_program': ldProgram,
        'requirements': requirements,
        'time_frame': timeFrame,
      };
}

/// One Individual Development Plan (IDP) form entry.
class IdpEntry {
  const IdpEntry({
    this.id,
    this.name,
    this.position,
    this.category,
    this.division,
    this.department,
    this.education,
    this.experience,
    this.training,
    this.eligibility,
    this.targetPosition1,
    this.targetPosition2,
    this.avgRating,
    this.opcr,
    this.ipcr,
    this.performanceRating,
    this.competencyDescription,
    this.competenceRating,
    this.successionPriorityScore,
    this.successionPriorityRating,
    this.developmentPlanRows = const [],
    this.preparedBy,
    this.reviewedBy,
    this.notedBy,
    this.approvedBy,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? name;
  final String? position;
  final String? category;
  final String? division;
  final String? department;
  final String? education;
  final String? experience;
  final String? training;
  final String? eligibility;
  final String? targetPosition1;
  final String? targetPosition2;
  final String? avgRating;
  final String? opcr;
  final String? ipcr;
  final String? performanceRating;
  final String? competencyDescription;
  final String? competenceRating;
  final String? successionPriorityScore;
  final String? successionPriorityRating;
  final List<IdpPlanRow> developmentPlanRows;
  final String? preparedBy;
  final String? reviewedBy;
  final String? notedBy;
  final String? approvedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'idp_entries';

  static const List<String> performanceRatingOptions = [
    'poor',
    'unsatisfactory',
    'very_satisfactory',
    'outstanding',
  ];

  static const List<String> competenceRatingOptions = [
    'basic',
    'intermediate',
    'advanced',
    'superior',
  ];

  static const List<String> successionPriorityOptions = [
    'priority',
    'priority_2',
    'priority_3',
  ];

  factory IdpEntry.fromJson(Map<String, dynamic> json) {
    List<IdpPlanRow> rows = [];
    final raw = json['development_plan_rows'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          rows.add(IdpPlanRow.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return IdpEntry(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      position: json['position']?.toString(),
      category: json['category']?.toString(),
      division: json['division']?.toString(),
      department: json['department']?.toString(),
      education: json['education']?.toString(),
      experience: json['experience']?.toString(),
      training: json['training']?.toString(),
      eligibility: json['eligibility']?.toString(),
      targetPosition1: json['target_position_1']?.toString(),
      targetPosition2: json['target_position_2']?.toString(),
      avgRating: json['avg_rating']?.toString(),
      opcr: json['opcr']?.toString(),
      ipcr: json['ipcr']?.toString(),
      performanceRating: json['performance_rating']?.toString(),
      competencyDescription: json['competency_description']?.toString(),
      competenceRating: json['competence_rating']?.toString(),
      successionPriorityScore: json['succession_priority_score']?.toString(),
      successionPriorityRating: json['succession_priority_rating']?.toString(),
      developmentPlanRows: rows,
      preparedBy: json['prepared_by']?.toString(),
      reviewedBy: json['reviewed_by']?.toString(),
      notedBy: json['noted_by']?.toString(),
      approvedBy: json['approved_by']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'position': position,
      'category': category,
      'division': division,
      'department': department,
      'education': education,
      'experience': experience,
      'training': training,
      'eligibility': eligibility,
      'target_position_1': targetPosition1,
      'target_position_2': targetPosition2,
      'avg_rating': avgRating,
      'opcr': opcr,
      'ipcr': ipcr,
      'performance_rating': performanceRating,
      'competency_description': competencyDescription,
      'competence_rating': competenceRating,
      'succession_priority_score': successionPriorityScore,
      'succession_priority_rating': successionPriorityRating,
      'development_plan_rows': developmentPlanRows.map((r) => r.toJson()).toList(),
      'prepared_by': preparedBy,
      'reviewed_by': reviewedBy,
      'noted_by': notedBy,
      'approved_by': approvedBy,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class IdpRepo {
  IdpRepo._();
  static final IdpRepo instance = IdpRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<IdpEntry>> list() async {
    final res = await _client
        .from(IdpEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => IdpEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<IdpEntry?> get(String id) async {
    final res = await _client
        .from(IdpEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : IdpEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(IdpEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(IdpEntry.tableName).insert(payload);
  }

  Future<void> update(IdpEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(IdpEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(IdpEntry.tableName).delete().eq('id', id);
  }
}
