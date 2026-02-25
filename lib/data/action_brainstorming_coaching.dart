import 'package:supabase_flutter/supabase_flutter.dart';

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
          list.add(ActionBrainstormingRow.fromJson(Map<String, dynamic>.from(e)));
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
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
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

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<ActionBrainstormingEntry>> list() async {
    final res = await _client
        .from(ActionBrainstormingEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => ActionBrainstormingEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ActionBrainstormingEntry?> get(String id) async {
    final res = await _client
        .from(ActionBrainstormingEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : ActionBrainstormingEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(ActionBrainstormingEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(ActionBrainstormingEntry.tableName).insert(payload);
  }

  Future<void> update(ActionBrainstormingEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(ActionBrainstormingEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(ActionBrainstormingEntry.tableName).delete().eq('id', id);
  }
}
