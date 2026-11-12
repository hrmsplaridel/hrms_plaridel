import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';

/// Clean document-style preview for a submitted training daily report.
class TrainingDailyReportReadOnlyView extends StatelessWidget {
  const TrainingDailyReportReadOnlyView({super.key, required this.report});

  final TrainingDailyReport report;

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _formatSubmittedAt(DateTime at) {
    final local = at.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h24 = local.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final min = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $h12:$min $ampm';
  }

  static String _prettyStatus(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Submitted';
    return t
        .split(RegExp(r'[_\s]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  static Color _statusColor(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'approved':
      case 'accepted':
      case 'seen':
        return const Color(0xFF2E7D32);
      case 'rejected':
      case 'not_approved':
      case 'needs_revision':
        return const Color(0xFFC62828);
      default:
        return AppTheme.primaryNavy;
    }
  }

  static IconData _fileIcon(String? name, String? type) {
    final n = (name ?? '').toLowerCase();
    final t = (type ?? '').toLowerCase();
    if (t.contains('pdf') || n.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (t.contains('image') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    return Icons.attach_file_rounded;
  }

  Future<void> _openAttachment() async {
    final url = report.attachmentUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final employee = (r.employeeName ?? '').trim().isEmpty
        ? 'Employee'
        : r.employeeName!.trim();
    final title = r.title.trim().isEmpty ? 'Untitled report' : r.title.trim();
    final description = (r.description ?? '').trim();
    final hasFile =
        r.attachmentName != null && r.attachmentName!.trim().isNotEmpty;
    final statusLabel = _prettyStatus(r.status);
    final statusColor = _statusColor(r.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      const Color(0xFF252D3D),
                      const Color(0xFF1E2430),
                    ]
                  : [
                      const Color(0xFFFFF7F0),
                      Colors.white,
                      const Color(0xFFF4F7FC),
                    ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: dark ? 0.18 : 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    child: Text(
                      _initials(employee),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: primary,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Training daily report',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.25,
                  color: primary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Submitted ${_formatSubmittedAt(r.submittedAt)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(
                icon: Icons.notes_rounded,
                label: 'Description',
                accent: accent,
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: dark ? 0.55 : 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hairline),
                ),
                child: Text(
                  description.isEmpty
                      ? 'No description provided.'
                      : description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    fontStyle:
                        description.isEmpty ? FontStyle.italic : FontStyle.normal,
                    color: description.isEmpty ? secondary : primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionLabel(
                icon: Icons.attach_file_rounded,
                label: 'Attachment',
                accent: accent,
              ),
              const SizedBox(height: 10),
              if (hasFile)
                Material(
                  color: muted.withValues(alpha: dark ? 0.55 : 0.75),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: r.attachmentUrl != null ? _openAttachment : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hairline),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _fileIcon(r.attachmentName, r.attachmentType),
                              color: accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.attachmentName!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r.attachmentUrl != null
                                      ? 'Tap to open attachment'
                                      : 'Attachment on file',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (r.attachmentUrl != null)
                            FilledButton.tonalIcon(
                              onPressed: _openAttachment,
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: const Text('Open'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: dark ? 0.55 : 0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_off_outlined, size: 18, color: secondary),
                      const SizedBox(width: 8),
                      Text(
                        'No attachment uploaded',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
            color: accent.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
