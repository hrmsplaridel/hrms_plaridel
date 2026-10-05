import 'package:flutter/material.dart';

/// Explains queue access without hiding the surrounding management tools.
class ReviewerAccessNotice extends StatelessWidget {
  const ReviewerAccessNotice({
    super.key,
    required this.requestType,
    required this.checking,
    required this.failed,
    required this.onRetry,
  });

  final String requestType;
  final bool checking;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(checking ? Icons.hourglass_empty : Icons.lock_outline),
          const SizedBox(height: 12),
          Text(
            checking
                ? 'Checking reviewer access…'
                : failed
                ? 'Unable to check reviewer access. Please retry.'
                : 'Assigned $requestType reviewer access required.',
            textAlign: TextAlign.center,
          ),
          if (!checking && !failed) ...[
            const SizedBox(height: 8),
            const Text(
              'An active final-reviewer or backup assignment is required to view this queue.',
              textAlign: TextAlign.center,
            ),
          ],
          if (!checking)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Check reviewer access'),
            ),
        ],
      ),
    ),
  );
}
