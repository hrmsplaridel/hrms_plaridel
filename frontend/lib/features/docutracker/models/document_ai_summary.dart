class DocumentAiSummary {
  const DocumentAiSummary({
    this.id,
    required this.documentId,
    required this.purpose,
    required this.statusSummary,
    required this.requiredAction,
    this.importantDates = const [],
    this.risksOrMissingInfo = const [],
    this.generatedBy,
    this.generatedByName,
    this.provider,
    this.model,
    this.generatedAt,
  });

  final String? id;
  final String documentId;
  final String purpose;
  final String statusSummary;
  final String requiredAction;
  final List<String> importantDates;
  final List<String> risksOrMissingInfo;
  final String? generatedBy;
  final String? generatedByName;
  final String? provider;
  final String? model;
  final DateTime? generatedAt;

  factory DocumentAiSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : json;
    return DocumentAiSummary(
      id: json['id']?.toString(),
      documentId: json['document_id']?.toString() ?? '',
      purpose: summary['purpose']?.toString() ?? '',
      statusSummary: summary['status_summary']?.toString() ?? '',
      requiredAction: summary['required_action']?.toString() ?? '',
      importantDates: _stringList(summary['important_dates']),
      risksOrMissingInfo: _stringList(summary['risks_or_missing_info']),
      generatedBy: json['generated_by']?.toString(),
      generatedByName: json['generated_by_name']?.toString(),
      provider: json['provider']?.toString(),
      model: json['model']?.toString(),
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'].toString())
          : null,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}
