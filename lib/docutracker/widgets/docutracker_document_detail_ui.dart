import 'package:flutter/material.dart';
import '../theme/docutracker_tokens.dart';

/// Pill tag for document type / reference on the detail header.
class DocuTrackerDetailTag extends StatelessWidget {
  const DocuTrackerDetailTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeach,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DocuTrackerTokens.highlightPeachBorder),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: DocuTrackerTokens.textSecondary,
        ),
      ),
    );
  }
}

/// Full-width peach banner for “your turn” / workflow guidance.
class DocuTrackerDetailActionBanner extends StatelessWidget {
  const DocuTrackerDetailActionBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.info_outline_rounded,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeach,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: DocuTrackerTokens.brand.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: DocuTrackerTokens.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: DocuTrackerTokens.subtitleStyle().copyWith(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White card section used on the document detail page.
class DocuTrackerDetailSectionCard extends StatelessWidget {
  const DocuTrackerDetailSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DocuTrackerTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.brandSoft,
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusSm,
                    ),
                  ),
                  child: Icon(icon, color: DocuTrackerTokens.brand, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: DocuTrackerTokens.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: DocuTrackerTokens.subtitleStyle(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(
            height: 1,
            color: DocuTrackerTokens.borderSubtle.withValues(alpha: 0.85),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Dashed peach box for empty assignees / upload zones.
class DocuTrackerPeachDashedBox extends StatelessWidget {
  const DocuTrackerPeachDashedBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeach,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorder,
          style: BorderStyle.solid,
        ),
      ),
      child: child,
    );
  }
}

String docuTrackerFormatRelativeSaved(DateTime? updatedAt) {
  if (updatedAt == null) return '';
  final diff = DateTime.now().difference(updatedAt.toLocal());
  if (diff.inMinutes < 1) return 'Last saved just now';
  if (diff.inMinutes < 60) {
    return 'Last saved ${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return 'Last saved ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays < 7) {
    return 'Last saved ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  final local = updatedAt.toLocal();
  return 'Last saved ${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
