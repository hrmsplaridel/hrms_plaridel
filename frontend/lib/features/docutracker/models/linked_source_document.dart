class DocuTrackerLinkedSourceField {
  const DocuTrackerLinkedSourceField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  factory DocuTrackerLinkedSourceField.fromJson(Map<String, dynamic> json) {
    return DocuTrackerLinkedSourceField(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}

class DocuTrackerLinkedSourceAttachment {
  const DocuTrackerLinkedSourceAttachment({
    required this.label,
    required this.name,
    required this.url,
  });

  final String label;
  final String name;
  final String url;

  factory DocuTrackerLinkedSourceAttachment.fromJson(
    Map<String, dynamic> json,
  ) {
    return DocuTrackerLinkedSourceAttachment(
      label: json['label']?.toString() ?? 'Attachment',
      name: json['name']?.toString() ?? 'Attachment',
      url: json['url']?.toString() ?? '',
    );
  }
}

class DocuTrackerLinkedSourceDocument {
  const DocuTrackerLinkedSourceDocument({
    required this.sourceModule,
    required this.sourceTable,
    required this.sourceRecordId,
    required this.title,
    required this.status,
    required this.fields,
    required this.attachments,
    required this.printData,
    this.createdAt,
    this.updatedAt,
  });

  final String sourceModule;
  final String sourceTable;
  final String sourceRecordId;
  final String title;
  final String status;
  final List<DocuTrackerLinkedSourceField> fields;
  final List<DocuTrackerLinkedSourceAttachment> attachments;
  final Map<String, dynamic> printData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DocuTrackerLinkedSourceDocument.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as List<dynamic>? ?? const [];
    final rawAttachments = json['attachments'] as List<dynamic>? ?? const [];
    return DocuTrackerLinkedSourceDocument(
      sourceModule: json['source_module']?.toString() ?? '',
      sourceTable: json['source_table']?.toString() ?? '',
      sourceRecordId: json['source_record_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Source document',
      status: json['status']?.toString() ?? '',
      fields: rawFields
          .whereType<Map>()
          .map(
            (value) => DocuTrackerLinkedSourceField.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .where((value) => value.label.isNotEmpty && value.value.isNotEmpty)
          .toList(growable: false),
      attachments: rawAttachments
          .whereType<Map>()
          .map(
            (value) => DocuTrackerLinkedSourceAttachment.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .where((value) => value.url.isNotEmpty)
          .toList(growable: false),
      printData: json['print_data'] is Map
          ? Map<String, dynamic>.from(json['print_data'] as Map)
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
