import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_styles.dart';

/// Groups workflow actions with a clear label and comfortable tap targets.
class DocuTrackerWorkflowActionBar extends StatelessWidget {
  const DocuTrackerWorkflowActionBar({
    super.key,
    required this.actions,
    this.title = 'Workflow actions',
    this.description =
        'Approve, reject, return, or forward when you are the current holder and your role allows it. Remarks are logged to the history.',
  });

  final List<Widget> actions;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final w in actions)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: w,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
