import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// One row in the Learning Application Plan table.
class LearningApplicationPlanRow {
  const LearningApplicationPlanRow({
    this.learning,
    this.objectives,
    this.competencyGapsAddressed,
    this.reapImplementation,
    this.timeline,
    this.personsInvolved,
    this.evidence,
  });

  final String? learning;
  final String? objectives;
  final String? competencyGapsAddressed;
  final String? reapImplementation;
  final String? timeline;
  final String? personsInvolved;
  final String? evidence;

  factory LearningApplicationPlanRow.fromJson(Map<String, dynamic> json) {
    return LearningApplicationPlanRow(
      learning: json['learning']?.toString(),
      objectives: json['objectives']?.toString(),
      competencyGapsAddressed: json['competency_gaps_addressed']?.toString(),
      reapImplementation: json['reap_implementation']?.toString(),
      timeline: json['timeline']?.toString(),
      personsInvolved: json['persons_involved']?.toString(),
      evidence: json['evidence']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'learning': learning,
    'objectives': objectives,
    'competency_gaps_addressed': competencyGapsAddressed,
    'reap_implementation': reapImplementation,
    'timeline': timeline,
    'persons_involved': personsInvolved,
    'evidence': evidence,
  };

  bool get isBlank => [
    learning,
    objectives,
    competencyGapsAddressed,
    reapImplementation,
    timeline,
    personsInvolved,
    evidence,
  ].every((v) => (v ?? '').trim().isEmpty);
}

/// One Learning Application Plan form entry (L&D).
class LearningApplicationPlanEntry {
  const LearningApplicationPlanEntry({
    this.id,
    this.memoReportTo,
    this.from,
    this.thru,
    this.subject,
    this.title,
    this.date,
    this.venue,
    this.cost,
    this.reapTypes = const [],
    this.otherReapType,
    this.reportedBy,
    this.receivedBy,
    this.entries = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? memoReportTo;
  final String? from;
  final String? thru;
  final String? subject;
  final String? title;
  final String? date;
  final String? venue;
  final String? cost;
  final List<String> reapTypes;
  final String? otherReapType;
  final String? reportedBy;
  final String? receivedBy;
  final List<LearningApplicationPlanRow> entries;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'learning_application_plan_entries';

  static const List<String> reapTypeOptions = [
    'orientation',
    'encoding',
    'coaching',
    'mentoring',
    'other',
  ];

  static const Map<String, String> reapTypeLabels = {
    'orientation': 'Orientation',
    'encoding': 'Encoding',
    'coaching': 'Coaching',
    'mentoring': 'Mentoring',
    'other': 'Other',
  };

  /// Official printed receiver on the Learning Application Plan.
  static const String defaultReceivedByName = 'MARCELO B. CAÑARES';
  static const String defaultReceivedByTitle = 'HRMO III';

  factory LearningApplicationPlanEntry.fromJson(Map<String, dynamic> json) {
    List<LearningApplicationPlanRow> rows = [];
    final raw = json['entries'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          rows.add(
            LearningApplicationPlanRow.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    List<String> types = [];
    final rawTypes = json['reap_types'];
    if (rawTypes is List) {
      types = rawTypes.map((e) => e.toString()).toList();
    }
    return LearningApplicationPlanEntry(
      id: json['id']?.toString(),
      memoReportTo: json['memo_report_to']?.toString(),
      from: json['from_name']?.toString(),
      thru: json['thru']?.toString(),
      subject: json['subject']?.toString(),
      title: json['title']?.toString(),
      date: json['date']?.toString(),
      venue: json['venue']?.toString(),
      cost: json['cost']?.toString(),
      reapTypes: types,
      otherReapType: json['other_reap_type']?.toString(),
      reportedBy: json['reported_by']?.toString(),
      receivedBy: json['received_by']?.toString(),
      entries: rows,
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
      'memo_report_to': memoReportTo,
      'from_name': from,
      'thru': thru,
      'subject': subject,
      'title': title,
      'date': date,
      'venue': venue,
      'cost': cost,
      'reap_types': reapTypes,
      'other_reap_type': otherReapType,
      'reported_by': reportedBy,
      'received_by': receivedBy,
      'entries': entries.map((r) => r.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class LearningApplicationPlanRepo {
  LearningApplicationPlanRepo._();
  static final LearningApplicationPlanRepo instance =
      LearningApplicationPlanRepo._();

  Future<List<LearningApplicationPlanEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      LearningApplicationPlanEntry.tableName,
    );
    return rows.map(LearningApplicationPlanEntry.fromJson).toList();
  }

  Future<LearningApplicationPlanEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      LearningApplicationPlanEntry.tableName,
      id,
    );
    return row == null ? null : LearningApplicationPlanEntry.fromJson(row);
  }

  Future<void> insert(LearningApplicationPlanEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      LearningApplicationPlanEntry.tableName,
      payload,
    );
  }

  Future<void> update(LearningApplicationPlanEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      LearningApplicationPlanEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      LearningApplicationPlanEntry.tableName,
      id,
    );
  }
}
