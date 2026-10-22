import 'package:flutter/material.dart';
import 'approval_workflow_picker.dart';

class ApprovalWorkflowSummary extends StatelessWidget {
  const ApprovalWorkflowSummary({super.key, required this.snapshot});
  final Map<String, dynamic>? snapshot;
  @override
  Widget build(BuildContext context) {
    if (snapshot == null) return const SizedBox.shrink();
    final steps = snapshot!['steps'] as List? ?? const [];
    final current = snapshot!['current_step'] as int? ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${snapshot!['name']} · v${snapshot!['version']}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(approvalStepsLabel(snapshot!['steps'])),
          if (snapshot!['outcome'] == null &&
              current < steps.length &&
              steps[current] is Map)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Awaiting: ${(steps[current] as Map)['label']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (snapshot!['manual_signing_required'] == true)
            const Text('The Mayor signs the printed form manually.'),
        ],
      ),
    );
  }
}
