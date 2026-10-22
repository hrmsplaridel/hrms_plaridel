import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';

/// How many events the document page shows before "View all activities".
const int docuTrackerActivityPreviewCount = 3;

/// Page size for the full activity history.
const int docuTrackerActivityPageSize = 10;

const String _movedSignaturePrefix = 'Moved signed field:';

/// Newest first. Events with the same time keep a stable id order.
List<DocumentHistoryEntry> docuTrackerHistoryNewestFirst(
  List<DocumentHistoryEntry> raw,
) {
  final copy = [...raw];
  copy.sort((a, b) {
    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
    final byTime = bt.compareTo(at);
    if (byTime != 0) return byTime;
    return (b.id ?? '').compareTo(a.id ?? '');
  });
  return copy;
}

bool docuTrackerHistoryIsSignatureMove(DocumentHistoryEntry entry) {
  return entry.action == 'metadata_updated' &&
      (entry.remarks?.trim().startsWith(_movedSignaturePrefix) ?? false);
}

/// Friendly title. Unknown actions keep their recorded action string.
String docuTrackerHistoryTitle(DocumentHistoryEntry entry) {
  if (docuTrackerHistoryIsSignatureMove(entry)) {
    return 'Signature field moved';
  }
  if (entry.action == 'released') {
    final department = entry.releasedToDepartmentName;
    if (department != null) return 'Released to $department';
    return 'Document released';
  }
  return switch (entry.action) {
    'created' => 'Document created',
    'metadata_updated' => 'Document details updated',
    'signed' => 'Signature added',
    'signature_replaced' => 'Signature replaced',
    'returned' => 'Document returned',
    'assigned' => 'Document assigned',
    'approved' => 'Document approved',
    'rejected' => 'Document rejected',
    'forwarded' => 'Document forwarded',
    'submitted' => 'Document submitted',
    'saved_draft' => 'Draft saved',
    'cancelled' => 'Document cancelled',
    'remark' => 'Internal note added',
    'overdue' => 'Document overdue',
    'escalated' => 'Document escalated',
    'department_head_approved' => 'Approved by department',
    'department_head_rejected' => 'Rejected by department',
    'department_head_returned' => 'Returned by department',
    null || '' => '—',
    _ => entry.action!,
  };
}

/// Recorded actor name only. Missing names are not replaced with a person.
String? docuTrackerHistoryActorName(DocumentHistoryEntry entry) {
  final name = entry.actorName?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}

/// Status line only when the recorded status actually changes.
String? docuTrackerHistoryStatusTransition(DocumentHistoryEntry entry) {
  final from = entry.fromStatus;
  final to = entry.toStatus;
  if (from == null || to == null || from == to) return null;
  return '${from.displayName} → ${to.displayName}';
}

String? docuTrackerHistoryStepLine(DocumentHistoryEntry entry) {
  if (entry.fromStep != null && entry.toStep != null) {
    if (entry.fromStep == entry.toStep) return 'Step ${entry.toStep}';
    return 'Step ${entry.fromStep} → ${entry.toStep}';
  }
  if (entry.toStep != null) return 'Step ${entry.toStep}';
  if (entry.fromStep != null) return 'Step ${entry.fromStep}';
  return null;
}

IconData docuTrackerHistoryIcon(DocumentHistoryEntry entry) {
  if (docuTrackerHistoryIsSignatureMove(entry)) return Icons.open_with_rounded;
  return switch (entry.action) {
    'created' => Icons.note_add_outlined,
    'metadata_updated' => Icons.edit_outlined,
    'signed' || 'signature_replaced' => Icons.draw_outlined,
    'released' => Icons.outbox_outlined,
    'returned' || 'department_head_returned' => Icons.undo_rounded,
    'approved' || 'department_head_approved' => Icons.check_circle_outline,
    'rejected' || 'department_head_rejected' => Icons.cancel_outlined,
    'forwarded' => Icons.arrow_forward_rounded,
    'remark' => Icons.chat_bubble_outline,
    'escalated' => Icons.trending_up_rounded,
    'overdue' => Icons.alarm_outlined,
    'cancelled' => Icons.block_rounded,
    'submitted' => Icons.send_outlined,
    _ => Icons.circle_outlined,
  };
}

String docuTrackerHistoryTimestamp(DateTime dt) {
  final local = dt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String docuTrackerHistoryRowKey(DocumentHistoryEntry entry, int index) {
  final id = entry.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return '$index-${entry.action}-${entry.createdAt?.toIso8601String()}';
}

/// Filters the full history panel can request. `null` is every action.
const List<({String? action, String label})> docuTrackerHistoryFilters =
    <({String? action, String label})>[
      (action: null, label: 'All activities'),
      (action: 'created', label: 'Document created'),
      (action: 'metadata_updated', label: 'Document details updated'),
      (action: 'signed', label: 'Signature added'),
      (action: 'released', label: 'Document released'),
      (action: 'returned', label: 'Document returned'),
      (action: 'remark', label: 'Internal note'),
      (action: 'approved', label: 'Document approved'),
      (action: 'rejected', label: 'Document rejected'),
      (action: 'forwarded', label: 'Document forwarded'),
      (action: 'submitted', label: 'Document submitted'),
      (action: 'assigned', label: 'Document assigned'),
      (action: 'escalated', label: 'Escalated'),
      (action: 'overdue', label: 'Overdue'),
    ];
