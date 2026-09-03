import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Export format choice from the generate-report sheet.
enum RspReportExportChoice { preview, csv, pdf, print }

/// Which HR report flow opened the picker.
enum RspReportKind { applications, finalInterview }

/// Compact export picker for RSP reports (applications or final interview).
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
      ? 'Export schedule, results, and hiring status for the current list.'
      : 'Export applicant IDs, profiles, and exam scores from the current view.';

  String get _stat2Label => _isFinalInterview ? 'scheduled' : 'with exam';

  String get _stat3Label => _isFinalInterview ? 'hired' : 'passed';

  String get _compactSummary {
    final parts = <String>[
      '$applicantCount applicant${applicantCount == 1 ? '' : 's'}',
    ];
    if (stat2Count != null) parts.add('$stat2Count $_stat2Label');
    if (stat3Count != null) parts.add('$stat3Count $_stat3Label');
    return parts.join(' · ');
  }

  bool get _hasActiveFilter {
    final s = filterSummary.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.contains('none') || s.contains('all application')) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final maxH = MediaQuery.sizeOf(context).height * 0.86;

    return Dialog(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: hairline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: primary,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            style: TextStyle(
                              color: primary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.35,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: muted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _compactSummary,
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          if (_hasActiveFilter) ...[
                            const SizedBox(height: 4),
                            Text(
                              filterSummary,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Export as',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.visibility_outlined,
                      iconColor: accent,
                      iconBg: accent.withValues(alpha: dark ? 0.2 : 0.1),
                      title: 'Preview',
                      subtitle: 'Review before download or print',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.preview),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.table_chart_outlined,
                      iconColor: const Color(0xFF2E7D32),
                      iconBg: dark
                          ? const Color(0xFF1E3A24)
                          : const Color(0xFFE8F5E9),
                      title: 'CSV',
                      subtitle: 'Spreadsheet for Excel',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.csv),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.picture_as_pdf_outlined,
                      iconColor: const Color(0xFFC62828),
                      iconBg: dark
                          ? const Color(0xFF3A2020)
                          : const Color(0xFFFFEBEE),
                      title: 'PDF',
                      subtitle: 'Download summary table',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.pdf),
                    ),
                    const SizedBox(height: 8),
                    _ExportOptionTile(
                      icon: Icons.print_outlined,
                      iconColor: accent,
                      iconBg: accent.withValues(alpha: dark ? 0.2 : 0.1),
                      title: 'Print',
                      subtitle: 'Open print preview',
                      onTap: () =>
                          Navigator.pop(context, RspReportExportChoice.print),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: secondary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
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
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? accent.withValues(alpha: 0.35)
                    : hairline,
              ),
              color: _hovered
                  ? accent.withValues(alpha: dark ? 0.08 : 0.04)
                  : panel,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: secondary.withValues(alpha: _hovered ? 1 : 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
