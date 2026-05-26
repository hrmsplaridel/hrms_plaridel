import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';
import 'docutracker_press_scale.dart';

/// Pill filter chip used across DocuTracker (dashboard, documents, admin).
class DocuTrackerWarmFilterChip extends StatelessWidget {
  const DocuTrackerWarmFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DocuTrackerPressScale(
      pressedScale: 0.975,
      child: Material(
        color: selected ? DocuTrackerTokens.brandSoft : DocuTrackerTokens.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected
                    ? DocuTrackerTokens.brand.withValues(alpha: 0.45)
                    : DocuTrackerTokens.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? DocuTrackerTokens.brandDark
                        : DocuTrackerTokens.textMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                color: selected
                    ? DocuTrackerTokens.brandDark
                    : DocuTrackerTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact square utility button (filter, sort, refresh).
class DocuTrackerUtilityIconButton extends StatelessWidget {
  const DocuTrackerUtilityIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DocuTrackerPressScale(
        pressedScale: 0.96,
        child: Material(
          color: DocuTrackerTokens.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DocuTrackerTokens.borderSubtle),
              ),
              child: Icon(
                icon,
                size: 18,
                color: onPressed == null
                    ? DocuTrackerTokens.textMuted.withValues(alpha: 0.4)
                    : DocuTrackerTokens.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard warm surface card for admin/documents panels.
class DocuTrackerWarmSurfaceCard extends StatelessWidget {
  const DocuTrackerWarmSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: padding,
      decoration: DocuTrackerTokens.cardDecoration(),
      child: child,
    );
  }
}

/// Terracotta FAB used for create actions.
class DocuTrackerCreateFab extends StatelessWidget {
  const DocuTrackerCreateFab({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DocuTrackerPressScale(
      pressedScale: 0.94,
      child: FloatingActionButton(
        onPressed: enabled ? onPressed : null,
        backgroundColor: DocuTrackerTokens.brand,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}
