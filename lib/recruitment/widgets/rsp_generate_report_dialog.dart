import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Export format choice from the generate-report sheet.
enum RspReportExportChoice { preview, csv, pdf, print }

/// Which HR report flow opened the picker.
enum RspReportKind { applications, finalInterview }

/// Export picker for RSP reports (applications or final interview).
class RspGenerateReportDialog extends StatelessWidget {
  const RspGenerateReportDialog({
    super.key,
    required this.kind,
    required this.applicantCount,
    required this.filterSummary,
    this.stat2Count,
    this.stat3Count,
  });

  final RspReportKind kind;
  final int applicantCount;
  final String filterSummary;

  /// Second summary stat (e.g. with exam / interview scheduled).
  final int? stat2Count;

  /// Third summary stat (e.g. passed exam / hired).
  final int? stat3Count;

  static Future<RspReportExportChoice?> showApplications(
    BuildContext context, {
    required int applicantCount,
    required String filterSummary,
    int? withExamCount,
    int? passedCount,
  }) {
    return showDialog<RspReportExportChoice>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => RspGenerateReportDialog(
        kind: RspReportKind.applications,
        applicantCount: applicantCount,
        filterSummary: filterSummary,
        stat2Count: withExamCount,
        stat3Count: passedCount,
      ),
    );
  }

  static Future<RspReportExportChoice?> showFinalInterview(
    BuildContext context, {
    required int applicantCount,
    required String filterSummary,
    int? scheduledCount,
    int? hiredCount,
  }) {
    return showDialog<RspReportExportChoice>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => RspGenerateReportDialog(
        kind: RspReportKind.finalInterview,
        applicantCount: applicantCount,
        filterSummary: filterSummary,
        stat2Count: scheduledCount,
        stat3Count: hiredCount,
      ),
    );
  }

  bool get _isFinalInterview => kind == RspReportKind.finalInterview;

  String get _title =>
      _isFinalInterview ? 'Final interview report' : 'Generate report';

  String get _subtitle => _isFinalInterview
      ? 'Export applicants who passed the screening exam: schedule, results, and hiring status.'
      : 'Export applicant profiles and exam scores from the current table view.';

  String get _stat2Label => _isFinalInterview ? 'Scheduled' : 'With exam';

  String get _stat3Label => _isFinalInterview ? 'Hired' : 'Passed';

  String get _previewSubtitle => _isFinalInterview
      ? 'Review pipeline status and interview details before exporting.'
      : 'Review cards or PDF layout before downloading or printing.';

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: hairline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              title: _title,
              subtitle: _subtitle,
              icon: _isFinalInterview
                  ? Icons.event_available_rounded
                  : Icons.summarize_rounded,
              primary: primary,
              secondary: secondary,
              accent: accent,
              dark: dark,
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryCard(
                      applicantCount: applicantCount,
                      stat2Count: stat2Count,
                      stat3Count: stat3Count,
                      stat2Label: _stat2Label,
                      stat3Label: _stat3Label,
                      filterSummary: filterSummary,
                      accent: accent,
                      primary: primary,
                      secondary: secondary,
                      hairline: hairline,
                      muted: muted,
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel(
                      text: 'INCLUDED IN REPORT',
                      color: secondary,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _isFinalInterview
                          ? const [
                              _IncludeChip(
                                label: 'Applicant info',
                                icon: Icons.person_outline_rounded,
                              ),
                              _IncludeChip(
                                label: 'Exam score',
                                icon: Icons.quiz_outlined,
                              ),
                              _IncludeChip(
                                label: 'Interview status',
                                icon: Icons.event_note_outlined,
                              ),
                              _IncludeChip(
                                label: 'Hiring progress',
                                icon: Icons.verified_user_outlined,
                              ),
                            ]
                          : const [
                              _IncludeChip(
                                label: 'Applicant info',
                                icon: Icons.person_outline_rounded,
                              ),
                              _IncludeChip(
                                label: 'Exam scores',
                                icon: Icons.quiz_outlined,
                              ),
                              _IncludeChip(
                                label: 'Section %',
                                icon: Icons.percent_rounded,
                              ),
                              _IncludeChip(
                                label: 'Documents',
                                icon: Icons.folder_open_outlined,
                              ),
                            ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(
                      text: 'REVIEW FIRST',
                      color: secondary,
                    ),
                    const SizedBox(height: 10),
                    _ExportOptionTile(
                      icon: Icons.visibility_rounded,
                      iconColor: accent,
                      iconBg: accent.withValues(alpha: dark ? 0.22 : 0.12),
                      title: 'Preview report',
                      subtitle: _previewSubtitle,
                      badge: 'Recommended',
                      emphasized: true,
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.preview),
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(
                      text: 'EXPORT DIRECTLY',
                      color: secondary,
                    ),
                    const SizedBox(height: 10),
                    _ExportOptionTile(
                      icon: Icons.table_chart_rounded,
                      iconColor: const Color(0xFF2E7D32),
                      iconBg: dark
                          ? const Color(0xFF1E3A24)
                          : const Color(0xFFE8F5E9),
                      title: 'Download CSV',
                      subtitle:
                          'Spreadsheet for Excel - all columns, best for analysis.',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.csv),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.picture_as_pdf_rounded,
                      iconColor: const Color(0xFFC62828),
                      iconBg: dark
                          ? const Color(0xFF3A2020)
                          : const Color(0xFFFFEBEE),
                      title: 'Download PDF',
                      subtitle: 'Landscape summary table - share or archive.',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.pdf),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.print_rounded,
                      iconColor: accent,
                      iconBg: accent.withValues(alpha: dark ? 0.22 : 0.1),
                      title: 'Print PDF',
                      subtitle: 'Open print preview with the same PDF layout.',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.print),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, RspReportExportChoice.preview),
                    icon: const Icon(Icons.visibility_rounded, size: 20),
                    label: const Text('Preview report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: hairline),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.dark,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color primary;
  final Color secondary;
  final Color accent;
  final bool dark;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final headerBg = dark
        ? accent.withValues(alpha: 0.12)
        : accent.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: primary,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: dark ? 0.15 : 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.applicantCount,
    required this.stat2Count,
    required this.stat3Count,
    required this.stat2Label,
    required this.stat3Label,
    required this.filterSummary,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.hairline,
    required this.muted,
  });

  final int applicantCount;
  final int? stat2Count;
  final int? stat3Count;
  final String stat2Label;
  final String stat3Label;
  final String filterSummary;
  final Color accent;
  final Color primary;
  final Color secondary;
  final Color hairline;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final showStats = stat2Count != null || stat3Count != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStats) ...[
            Row(
              children: [
                _MiniStat(
                  label: 'Applicants',
                  value: '$applicantCount',
                  icon: Icons.people_outline_rounded,
                  color: accent,
                ),
                if (stat2Count != null) ...[
                  const SizedBox(width: 8),
                  _MiniStat(
                    label: stat2Label,
                    value: '$stat2Count',
                    icon: Icons.event_outlined,
                    color: const Color(0xFF6A1B9A),
                  ),
                ],
                if (stat3Count != null) ...[
                  const SizedBox(width: 8),
                  _MiniStat(
                    label: stat3Label,
                    value: '$stat3Count',
                    icon: Icons.emoji_events_outlined,
                    color: const Color(0xFF2E7D32),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ] else
            Row(
              children: [
                _StatBadge(count: applicantCount, accent: accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Ready to export',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.filter_list_rounded, size: 17, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filterSummary,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.55,
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            count == 1 ? 'applicant' : 'applicants',
            style: TextStyle(
              color: accent.withValues(alpha: 0.85),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncludeChip extends StatelessWidget {
  const _IncludeChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final fg = AppTheme.dashTextPrimaryOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: accent),
          const SizedBox(width: 5),
          Icon(icon, size: 13, color: fg.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportOptionTile extends StatefulWidget {
  const _ExportOptionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.emphasized = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final bool emphasized;

  @override
  State<_ExportOptionTile> createState() => _ExportOptionTileState();
}

class _ExportOptionTileState extends State<_ExportOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;

    final borderColor = widget.emphasized
        ? widget.iconColor.withValues(alpha: 0.45)
        : _hovered
            ? accent.withValues(alpha: 0.4)
            : hairline;

    final bg = widget.emphasized
        ? widget.iconBg.withValues(alpha: dark ? 0.5 : 0.35)
        : _hovered
            ? accent.withValues(alpha: dark ? 0.08 : 0.04)
            : panel;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: widget.emphasized ? 1.5 : 1),
              color: bg,
              boxShadow: widget.emphasized && !_hovered
                  ? [
                      BoxShadow(
                        color: widget.iconColor.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : _hovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (widget.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.iconColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.badge!,
                                style: TextStyle(
                                  color: widget.iconColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: secondary.withValues(alpha: _hovered ? 1 : 0.65),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
