import 'document_status.dart';

/// Step 6 & 9: Audit trail entry - logs actions, overdue, escalation. - logs actions, overdue, escalation.
/// Every document has complete tracking history.
class DocumentHistoryEntry {
  const DocumentHistoryEntry({
    this.id,
    required this.documentId,
    this.action,
    this.actorId,
    this.actorName,
    this.fromStep,
    this.toStep,
    this.fromStatus,
    this.toStatus,
    this.remarks,
    this.isOverdueLog = false,
    this.isEscalationLog = false,
    this.escalationLevel,
    this.createdAt,
    this.metadata = const {},
  });

  final String? id;
  final String documentId;

  /// Action taken: created, assigned, reviewed, approved, rejected, returned, forwarded, escalated, overdue
  final String? action;
  final String? actorId;
  final String? actorName;
  final int? fromStep;
  final int? toStep;
  final DocumentStatus? fromStatus;
  final DocumentStatus? toStatus;
  final String? remarks;
  final bool isOverdueLog;
  final bool isEscalationLog;
  final int? escalationLevel;
  final DateTime? createdAt;

  /// Structured event details, e.g. the receiving department of a release.
  final Map<String, dynamic> metadata;

  /// Department name recorded on a `released` event.
  String? get releasedToDepartmentName {
    final name = metadata['released_to_department_name']?.toString().trim();
    return name == null || name.isEmpty ? null : name;
  }

  static const String tableName = 'docutracker_document_history';

  factory DocumentHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DocumentHistoryEntry(
      id: json['id']?.toString(),
      documentId: json['document_id'] as String? ?? '',
      action: json['action']?.toString(),
      actorId: json['actor_id']?.toString(),
      actorName: json['actor_name']?.toString(),
      fromStep: (json['from_step'] as num?)?.toInt(),
      toStep: (json['to_step'] as num?)?.toInt(),
      fromStatus: documentStatusFromString(json['from_status']?.toString()),
      toStatus: documentStatusFromString(json['to_status']?.toString()),
      remarks: json['remarks']?.toString(),
      isOverdueLog: json['is_overdue_log'] == true,
      isEscalationLog: json['is_escalation_log'] == true,
      escalationLevel: (json['escalation_level'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'document_id': documentId,
    if (action != null) 'action': action,
    if (actorId != null) 'actor_id': actorId,
    if (fromStep != null) 'from_step': fromStep,
    if (toStep != null) 'to_step': toStep,
    if (fromStatus != null) 'from_status': fromStatus!.value,
    if (toStatus != null) 'to_status': toStatus!.value,
    if (remarks != null) 'remarks': remarks,
    'is_overdue_log': isOverdueLog,
    'is_escalation_log': isEscalationLog,
    if (escalationLevel != null) 'escalation_level': escalationLevel,
  };
}

/// One page of the audit history endpoint.
class DocumentHistoryPage {
  const DocumentHistoryPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<DocumentHistoryEntry> items;
  final int total;
  final int limit;
  final int offset;

  factory DocumentHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List || json['total'] is! num) {
      throw const FormatException('Activity history could not be loaded.');
    }
    return DocumentHistoryPage(
      items: _historyEntriesFromList(rawItems),
      total: (json['total'] as num).toInt(),
      limit: (json['limit'] as num?)?.toInt() ?? rawItems.length,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

List<DocumentHistoryEntry> _historyEntriesFromList(List<dynamic> raw) {
  if (raw.any((item) => item is! Map)) {
    throw const FormatException('Activity history could not be loaded.');
  }
  return raw
      .map(
        (item) => DocumentHistoryEntry.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      )
      .toList(growable: false);
}

int _historyTime(DocumentHistoryEntry entry) =>
    entry.createdAt?.millisecondsSinceEpoch ?? 0;

/// Reads either history response the API documents:
/// a JSON array of every event, or `{ items, total, limit, offset }`.
///
/// A full array is filtered and paged here because that response includes
/// every event. A page object is already paged by the server.
DocumentHistoryPage documentHistoryPageFromResponse(
  Object? data, {
  required int limit,
  required int offset,
  String? action,
}) {
  if (data is Map) {
    final map = Map<String, dynamic>.from(data);
    final serverError = map['error'];
    if (map['items'] is List && map['total'] is num) {
      return DocumentHistoryPage.fromJson(map);
    }
    if (serverError is String && serverError.trim().isNotEmpty) {
      throw FormatException(serverError.trim());
    }
    throw const FormatException('Activity history could not be loaded.');
  }
  if (data is List) {
    final selected = _historyEntriesFromList(data).where((entry) {
      final filter = action?.trim();
      return filter == null || filter.isEmpty || entry.action == filter;
    }).toList();
    selected.sort((a, b) {
      final byTime = _historyTime(b).compareTo(_historyTime(a));
      if (byTime != 0) return byTime;
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    final start = offset < 0 ? 0 : offset;
    return DocumentHistoryPage(
      items: selected.skip(start).take(limit).toList(growable: false),
      total: selected.length,
      limit: limit,
      offset: start,
    );
  }
  throw const FormatException('Activity history could not be loaded.');
}
