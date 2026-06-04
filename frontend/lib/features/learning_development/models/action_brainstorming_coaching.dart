import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';

/// One row in the Action Brainstorming and Coaching Worksheet table.
class ActionBrainstormingRow {
  const ActionBrainstormingRow({
    this.name,
    this.stopDoing,
    this.doLessOf,
    this.keepDoing,
    this.doMoreOf,
    this.startDoing,
    this.goal,
  });

  final String? name;
  final String? stopDoing;
  final String? doLessOf;
  final String? keepDoing;
  final String? doMoreOf;
  final String? startDoing;
  final String? goal;

  factory ActionBrainstormingRow.fromJson(Map<String, dynamic> json) {
    return ActionBrainstormingRow(
      name: json['name']?.toString(),
      stopDoing: json['stop_doing']?.toString(),
      doLessOf: json['do_less_of']?.toString(),
      keepDoing: json['keep_doing']?.toString(),
      doMoreOf: json['do_more_of']?.toString(),
      startDoing: json['start_doing']?.toString(),
      goal: json['goal']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'stop_doing': stopDoing,
    'do_less_of': doLessOf,
    'keep_doing': keepDoing,
    'do_more_of': doMoreOf,
    'start_doing': startDoing,
    'goal': goal,
  };
}

/// Action Brainstorming and Coaching Worksheet entry (L&D).
class ActionBrainstormingEntry {
  const ActionBrainstormingEntry({
    this.id,
    this.department,
    this.date,
    this.rows = const [],
    this.certifiedBy,
    this.certificationDate,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? department;
  final String? date;
  final List<ActionBrainstormingRow> rows;
  final String? certifiedBy;
  final String? certificationDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'action_brainstorming_coaching_entries';

  factory ActionBrainstormingEntry.fromJson(Map<String, dynamic> json) {
    List<ActionBrainstormingRow> list = [];
    final raw = json['rows'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(
            ActionBrainstormingRow.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return ActionBrainstormingEntry(
      id: json['id']?.toString(),
      department: json['department']?.toString(),
      date: json['date']?.toString(),
      rows: list,
      certifiedBy: json['certified_by']?.toString(),
      certificationDate: json['certification_date']?.toString(),
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
      'department': department,
      'date': date,
      'rows': rows.map((r) => r.toJson()).toList(),
      'certified_by': certifiedBy,
      'certification_date': certificationDate,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class ActionBrainstormingRepo {
  ActionBrainstormingRepo._();
  static final ActionBrainstormingRepo instance = ActionBrainstormingRepo._();

  Future<List<ActionBrainstormingEntry>> list() async {
    final rows = await RspLdSavedEntriesApi.listRows(
      ActionBrainstormingEntry.tableName,
    );
    return rows.map(ActionBrainstormingEntry.fromJson).toList();
  }

  Future<ActionBrainstormingEntry?> get(String id) async {
    final row = await RspLdSavedEntriesApi.getRow(
      ActionBrainstormingEntry.tableName,
      id,
    );
    return row == null ? null : ActionBrainstormingEntry.fromJson(row);
  }

  Future<void> insert(ActionBrainstormingEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await RspLdSavedEntriesApi.insertRow(
      ActionBrainstormingEntry.tableName,
      payload,
    );
  }

  Future<void> update(ActionBrainstormingEntry entry) async {
    if (entry.id == null) return;
    await RspLdSavedEntriesApi.updateRow(
      ActionBrainstormingEntry.tableName,
      entry.id!,
      entry.toJson(),
    );
  }

  Future<void> delete(String id) async {
    await RspLdSavedEntriesApi.deleteRow(
      ActionBrainstormingEntry.tableName,
      id,
    );
  }
}
