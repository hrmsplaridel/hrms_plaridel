import 'package:supabase_flutter/supabase_flutter.dart';

/// One applicant row in the Selection Line-up table (no pre-filled values).
class SelectionLineupApplicant {
  const SelectionLineupApplicant({
    this.name,
    this.education,
    this.experience,
    this.training,
    this.eligibility,
  });

  final String? name;
  final String? education;
  final String? experience;
  final String? training;
  final String? eligibility;

  factory SelectionLineupApplicant.fromJson(Map<String, dynamic> json) {
    return SelectionLineupApplicant(
      name: json['name']?.toString(),
      education: json['education']?.toString(),
      experience: json['experience']?.toString(),
      training: json['training']?.toString(),
      eligibility: json['eligibility']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'education': education,
        'experience': experience,
        'training': training,
        'eligibility': eligibility,
      };
}

/// One Selection Line-up form entry (form structure only).
class SelectionLineupEntry {
  const SelectionLineupEntry({
    this.id,
    this.date,
    this.nameOfAgencyOffice,
    this.vacantPosition,
    this.itemNo,
    this.applicants = const [],
    this.preparedByName,
    this.preparedByTitle,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? date;
  final String? nameOfAgencyOffice;
  final String? vacantPosition;
  final String? itemNo;
  final List<SelectionLineupApplicant> applicants;
  final String? preparedByName;
  final String? preparedByTitle;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'selection_lineup_entries';

  factory SelectionLineupEntry.fromJson(Map<String, dynamic> json) {
    List<SelectionLineupApplicant> list = [];
    final raw = json['applicants'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(SelectionLineupApplicant.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return SelectionLineupEntry(
      id: json['id']?.toString(),
      date: json['date']?.toString(),
      nameOfAgencyOffice: json['name_of_agency_office']?.toString(),
      vacantPosition: json['vacant_position']?.toString(),
      itemNo: json['item_no']?.toString(),
      applicants: list,
      preparedByName: json['prepared_by_name']?.toString(),
      preparedByTitle: json['prepared_by_title']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'date': date,
      'name_of_agency_office': nameOfAgencyOffice,
      'vacant_position': vacantPosition,
      'item_no': itemNo,
      'applicants': applicants.map((a) => a.toJson()).toList(),
      'prepared_by_name': preparedByName,
      'prepared_by_title': preparedByTitle,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class SelectionLineupRepo {
  SelectionLineupRepo._();
  static final SelectionLineupRepo instance = SelectionLineupRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<SelectionLineupEntry>> list() async {
    final res = await _client
        .from(SelectionLineupEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => SelectionLineupEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<SelectionLineupEntry?> get(String id) async {
    final res = await _client
        .from(SelectionLineupEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : SelectionLineupEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(SelectionLineupEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(SelectionLineupEntry.tableName).insert(payload);
  }

  Future<void> update(SelectionLineupEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(SelectionLineupEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(SelectionLineupEntry.tableName).delete().eq('id', id);
  }
}
