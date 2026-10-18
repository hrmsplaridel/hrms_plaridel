import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/history_timeline.dart';

/// Recorded workflow decisions are authoritative in both review and history views.
List<LeaveHistoryEvent> leaveWorkflowHistory(
  LeaveRequest request, {
  List<dynamic>? decisions,
}) {
  final snapshot = request.workflowSnapshot;
  final steps = snapshot?['steps'] as List? ?? const [];
  final recorded = decisions ?? snapshot?['decisions'] as List? ?? const [];
  return [
    LeaveHistoryEvent(
      label: 'Submitted',
      dateTime: request.createdAt ?? request.dateFiled,
      actor: request.employeeName ?? 'Applicant',
      remarks: request.reason,
    ),
    for (final decision in recorded.whereType<Map>())
      LeaveHistoryEvent(
        label:
            '${_stepLabel(decision, steps)} · ${switch (decision['action']) {
              'approve' || null => 'Approved',
              'return' => 'Returned',
              'reject' => 'Rejected',
              _ => decision['action'].toString(),
            }}',
        dateTime: DateTime.tryParse(
          decision['acted_at']?.toString() ?? '',
        )?.toLocal(),
        actor:
            decision['reviewer_name']?.toString() ??
            (decision['signature'] as Map?)?['signer_name_snapshot']
                ?.toString() ??
            (decision['reviewer'] as Map?)?['name']?.toString() ??
            'Reviewer',
        remarks: decision['remarks']?.toString(),
      ),
  ];
}

String _stepLabel(Map decision, List steps) {
  final label = decision['step_label']?.toString();
  if (label != null && label.isNotEmpty) return label;
  final index = decision['step'];
  if (index is num && index >= 0 && index < steps.length) {
    final step = steps[index.toInt()];
    if (step is Map) return step['label']?.toString() ?? 'Review';
    return switch (step) {
      'department' => 'Department Review',
      'hr' => 'Final HR',
      'mayor' => 'Mayor',
      _ => step.toString(),
    };
  }
  return 'Review';
}
