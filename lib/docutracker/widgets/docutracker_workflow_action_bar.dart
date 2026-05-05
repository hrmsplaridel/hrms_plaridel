import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../theme/docutracker_tokens.dart';

/// Card strip for workflow actions (approve / forward / return / reject).
/// Order buttons from positive → neutral → destructive when building [actions].
class DocuTrackerWorkflowActionBar extends StatelessWidget {
  const DocuTrackerWorkflowActionBar({
    super.key,
    required this.actions,
    this.title = 'Workflow actions',
    this.description,
  });

  final List<Widget> actions;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: DocuTrackerTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
                  ),
                  child: const Icon(
                    Icons.touch_app_rounded,
                    size: 17,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (description != null && description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description!,
                          style: DocuTrackerTokens.metaStyle(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: DocuTrackerTokens.borderSubtle.withValues(alpha: 0.85)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final w in actions)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: w,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
