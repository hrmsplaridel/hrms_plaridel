import 'package:supabase_flutter/supabase_flutter.dart';

/// One candidate row in the Promotion Certification table (name + 5 columns; no pre-filled values).
class PromotionCertificationCandidate {
  const PromotionCertificationCandidate({
    this.name,
    this.col1,
    this.col2,
    this.col3,
    this.col4,
    this.col5,
  });

  final String? name;
  final String? col1;
  final String? col2;
  final String? col3;
  final String? col4;
  final String? col5;

  factory PromotionCertificationCandidate.fromJson(Map<String, dynamic> json) {
    return PromotionCertificationCandidate(
      name: json['name']?.toString(),
      col1: json['col1']?.toString(),
      col2: json['col2']?.toString(),
      col3: json['col3']?.toString(),
      col4: json['col4']?.toString(),
      col5: json['col5']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'col1': col1,
        'col2': col2,
        'col3': col3,
        'col4': col4,
        'col5': col5,
      };
}

/// One Promotion Certification / Screening form entry (form structure only).
class PromotionCertificationEntry {
  const PromotionCertificationEntry({
    this.id,
    this.positionForPromotion,
    this.candidates = const [],
    this.dateDay,
    this.dateMonth,
    this.dateYear,
    this.signatoryName,
    this.signatoryTitle,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? positionForPromotion;
  final List<PromotionCertificationCandidate> candidates;
  final String? dateDay;
  final String? dateMonth;
  final String? dateYear;
  final String? signatoryName;
  final String? signatoryTitle;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'promotion_certification_entries';

  factory PromotionCertificationEntry.fromJson(Map<String, dynamic> json) {
    List<PromotionCertificationCandidate> list = [];
    final raw = json['candidates'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(PromotionCertificationCandidate.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return PromotionCertificationEntry(
      id: json['id']?.toString(),
      positionForPromotion: json['position_for_promotion']?.toString(),
      candidates: list,
      dateDay: json['date_day']?.toString(),
      dateMonth: json['date_month']?.toString(),
      dateYear: json['date_year']?.toString(),
      signatoryName: json['signatory_name']?.toString(),
      signatoryTitle: json['signatory_title']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'position_for_promotion': positionForPromotion,
      'candidates': candidates.map((c) => c.toJson()).toList(),
      'date_day': dateDay,
      'date_month': dateMonth,
      'date_year': dateYear,
      'signatory_name': signatoryName,
      'signatory_title': signatoryTitle,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class PromotionCertificationRepo {
  PromotionCertificationRepo._();
  static final PromotionCertificationRepo instance = PromotionCertificationRepo._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<PromotionCertificationEntry>> list() async {
    final res = await _client
        .from(PromotionCertificationEntry.tableName)
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => PromotionCertificationEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PromotionCertificationEntry?> get(String id) async {
    final res = await _client
        .from(PromotionCertificationEntry.tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : PromotionCertificationEntry.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> insert(PromotionCertificationEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
    await _client.from(PromotionCertificationEntry.tableName).insert(payload);
  }

  Future<void> update(PromotionCertificationEntry entry) async {
    if (entry.id == null) return;
    await _client
        .from(PromotionCertificationEntry.tableName)
        .update(entry.toJson())
        .eq('id', entry.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(PromotionCertificationEntry.tableName).delete().eq('id', id);
  }
}
