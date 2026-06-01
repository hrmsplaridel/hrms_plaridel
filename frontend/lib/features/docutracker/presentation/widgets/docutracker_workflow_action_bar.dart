import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/docutracker_styles.dart';
import 'docutracker_press_scale.dart';

/// Distinct workflow transition buttons (Approve / Forward / Return / Reject).
class DocuTrackerWorkflowActionBar extends StatelessWidget {
  const DocuTrackerWorkflowActionBar({
    super.key,
    required this.canApprove,
    required this.canForward,
    required this.canReturn,
    required this.canReject,
    required this.onApprove,
    required this.onForward,
    required this.onReturn,
    required this.onReject,
    this.busy = false,
  });

  final bool canApprove;
  final bool canForward;
  final bool canReturn;
  final bool canReject;
  final VoidCallback? onApprove;
  final VoidCallback? onForward;
  final VoidCallback? onReturn;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionSpec>[
      if (canApprove)
        _ActionSpec(
          label: 'Approve',
          icon: Icons.check_circle_rounded,
          style: DocuTrackerStyles.approveButtonStyle(),
          onPressed: busy ? null : onApprove,
        ),
      if (canForward)
        _ActionSpec(
          label: 'Forward',
          icon: Icons.arrow_forward_rounded,
          style: DocuTrackerStyles.secondaryButtonStyle(),
          onPressed: busy ? null : onForward,
        ),
      if (canReturn)
        _ActionSpec(
          label: 'Return',
          icon: Icons.undo_rounded,
          style: DocuTrackerStyles.warningButtonStyle(),
          onPressed: busy ? null : onReturn,
        ),
      if (canReject)
        _ActionSpec(
          label: 'Reject',
          icon: Icons.cancel_rounded,
          style: DocuTrackerStyles.destructiveButtonStyle(),
          onPressed: busy ? null : onReject,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in actions) ...[
                DocuTrackerPressScale(child: _ActionButton(spec: a)),
                const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final a in actions)
              SizedBox(
                width: (constraints.maxWidth - 30) / 2,
                child: DocuTrackerPressScale(child: _ActionButton(spec: a)),
              ),
          ],
        );
      },
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.label,
    required this.icon,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final ButtonStyle style;
  final VoidCallback? onPressed;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.spec});

  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: spec.onPressed,
      icon: Icon(spec.icon, size: 18),
      label: Text(spec.label),
      style: spec.style.copyWith(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
      ),
    );
  }
}
