import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';

/// Section title row for dashboard / lists: clear hierarchy + optional
/// icon, count badge, accent color, and action.
///
/// Usage examples:
/// ```dart
/// // Basic (unchanged back-compat)
/// DocuTrackerSectionHeader(title: 'Overdue', subtitle: '3 documents')
///
/// // With icon + count badge
/// DocuTrackerSectionHeader(
///   title: 'Assigned to me',
///   count: 5,
///   icon: Icons.inbox_rounded,
///   accentColor: Colors.blue,
/// )
/// ```
class DocuTrackerSectionHeader extends StatelessWidget {
  const DocuTrackerSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.count,
    this.accentColor,
    this.showDivider = false,
  });

  final String title;

  /// Short descriptor shown as muted meta text (e.g. "3 documents").
  /// Ignored when [count] is provided.
  final String? subtitle;

  /// Widget pinned to the far right (e.g. a "View all" button).
  final Widget? trailing;

  /// Optional leading icon. Shown inside a tinted circular container.
  final IconData? icon;

  /// When supplied, shows a compact pill badge with the count next to the
  /// title. Takes precedence over [subtitle].
  final int? count;

  /// Tint used for the icon container and count badge.
  /// Defaults to [DocuTrackerTokens.brand].
  final Color? accentColor;

  /// When true, draws a subtle hairline below the header.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? DocuTrackerTokens.terracotta;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Optional icon bubble ──────────────────────────────────
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: accent),
                ),
                const SizedBox(width: 10),
              ],

              // ── Title + count badge ───────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: DocuTrackerTokens.titleStyle(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      _CountBadge(count: count!, color: accent),
                    ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        subtitle!,
                        style: DocuTrackerTokens.metaStyle(context),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Trailing action ───────────────────────────────────────
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),

          // ── Optional hairline divider ─────────────────────────────────
          if (showDivider) ...[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact pill that shows a numeric count.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$count ${count == 1 ? 'ITEM' : 'ITEMS'}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1.3,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
