import 'dart:convert';

/// One row from GET /api/leave/ledger (balance movement audit).
class LeaveBalanceLedgerEntry {
  const LeaveBalanceLedgerEntry({
    required this.id,
    required this.userId,
    this.employeeName,
    required this.leaveType,
    required this.action,
    required this.affectedBucket,
    required this.daysChanged,
    this.oldValue,
    this.newValue,
    this.relatedLeaveRequestId,
    this.actorUserId,
    this.actorName,
    required this.actorKind,
    this.remarks,
    this.metadataJson,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? employeeName;
  final String leaveType;
  final String action;
  final String affectedBucket;
  final double daysChanged;
  final double? oldValue;
  final double? newValue;
  final String? relatedLeaveRequestId;
  final String? actorUserId;
  final String? actorName;
  final String actorKind;
  final String? remarks;
  final Map<String, dynamic>? metadataJson;
  final DateTime createdAt;

  factory LeaveBalanceLedgerEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDt(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    Map<String, dynamic>? meta;
    final m = json['metadata_json'];
    if (m is Map<String, dynamic>) {
      meta = m;
    } else if (m is String && m.isNotEmpty) {
      try {
        meta = Map<String, dynamic>.from(jsonDecode(m) as Map);
      } catch (_) {}
    }

    return LeaveBalanceLedgerEntry(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      employeeName: json['employee_name']?.toString(),
      leaveType: json['leave_type']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      affectedBucket: json['affected_bucket']?.toString() ?? '',
      daysChanged: _parseDouble(json['days_changed']) ?? 0,
      oldValue: _parseDouble(json['old_value']),
      newValue: _parseDouble(json['new_value']),
      relatedLeaveRequestId: json['related_leave_request_id']?.toString(),
      actorUserId: json['actor_user_id']?.toString(),
      actorName: json['actor_name']?.toString(),
      actorKind: json['actor_kind']?.toString() ?? 'user',
      remarks: json['remarks']?.toString(),
      metadataJson: meta,
      createdAt: parseDt(json['created_at']),
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Paged response from GET /api/leave/ledger.
class LeaveLedgerResult {
  const LeaveLedgerResult({
    required this.total,
    required this.limit,
    required this.offset,
    required this.rows,
  });

  final int total;
  final int limit;
  final int offset;
  final List<LeaveBalanceLedgerEntry> rows;

  factory LeaveLedgerResult.fromJson(Map<String, dynamic> json) {
    final list = json['rows'];
    final rows = <LeaveBalanceLedgerEntry>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          rows.add(LeaveBalanceLedgerEntry.fromJson(e));
        }
      }
    }
    return LeaveLedgerResult(
      total: (json['total'] is num)
          ? (json['total'] as num).toInt()
          : int.tryParse('${json['total']}') ?? 0,
      limit: (json['limit'] is num) ? (json['limit'] as num).toInt() : 50,
      offset: (json['offset'] is num) ? (json['offset'] as num).toInt() : 0,
      rows: rows,
    );
  }
}

/// Query for GET /api/leave/ledger.
class LeaveLedgerQuery {
  const LeaveLedgerQuery({
    this.userId,
    this.leaveType,
    this.action,
    this.from,
    this.to,
    this.limit = 50,
    this.offset = 0,
  });

  /// Admin/HR only: filter to one employee. Omit for employees (JWT scopes rows).
  final String? userId;
  final String? leaveType;
  final String? action;
  final String? from;
  final String? to;
  final int limit;
  final int offset;

  Map<String, dynamic> toQueryParams() => {
    if (userId != null && userId!.trim().isNotEmpty) 'user_id': userId!.trim(),
    if (leaveType != null && leaveType!.trim().isNotEmpty)
      'leave_type': leaveType!.trim(),
    if (action != null && action!.trim().isNotEmpty) 'action': action!.trim(),
    if (from != null && from!.trim().isNotEmpty) 'from': from!.trim(),
    if (to != null && to!.trim().isNotEmpty) 'to': to!.trim(),
    'limit': limit,
    'offset': offset,
  };
}
