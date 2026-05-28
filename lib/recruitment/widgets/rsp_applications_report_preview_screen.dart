import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../api/user_facing_api_error.dart';
import '../../landingpage/constants/app_theme.dart';
import '../utils/rsp_applications_report_export.dart';

/// Full-screen preview of the applications & exam results report before export.
class RspApplicationsReportPreviewScreen extends StatefulWidget {
  const RspApplicationsReportPreviewScreen({
    super.key,
    required this.rows,
    required this.filterSummary,
  });

  final List<RspApplicationsReportRow> rows;
  final String filterSummary;

  static Future<void> open(
    BuildContext context, {
    required List<RspApplicationsReportRow> rows,
    required String filterSummary,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RspApplicationsReportPreviewScreen(
          rows: rows,
          filterSummary: filterSummary,
        ),
      ),
    );
  }

  @override
  State<RspApplicationsReportPreviewScreen> createState() =>
      _RspApplicationsReportPreviewScreenState();
}

class _RspApplicationsReportPreviewScreenState
    extends State<RspApplicationsReportPreviewScreen> {
  int _viewIndex = 0;
  bool _exporting = false;
  bool _showAllColumns = false;

  int get _passedCount =>
      widget.rows.where((r) => r.examOutcome == 'Passed').length;

  int get _withExamCount =>
      widget.rows.where((r) => r.examOutcome != 'No exam').length;

  Future<void> _runExport(Future<void> Function() action, String success) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    final canvas = AppTheme.dashCanvasOf(context);

    return Scaffold(
      backgroundColor: canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: panel,
            elevation: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                          color: primary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Report preview',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Applications & exam results',
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: dark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            '${widget.rows.length}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _ViewToggle(
                      index: _viewIndex,
                      enabled: !_exporting,
                      onChanged: (i) => setState(() => _viewIndex = i),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        _MiniStat(
                          label: 'Applicants',
                          value: '${widget.rows.length}',
                          icon: Icons.people_outline_rounded,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          label: 'With exam',
                          value: '$_withExamCount',
                          icon: Icons.quiz_outlined,
                          color: const Color(0xFF6A1B9A),
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          label: 'Passed',
                          value: '$_passedCount',
                          icon: Icons.emoji_events_outlined,
                          color: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: muted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: hairline),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.filter_list_rounded, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.filterSummary,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_viewIndex == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FilterChip(
                          label: Text(
                            _showAllColumns
                                ? 'Showing all columns'
                                : 'Show document columns',
                          ),
                          selected: _showAllColumns,
                          onSelected: _exporting
                              ? null
                              : (v) => setState(() => _showAllColumns = v),
                          showCheckmark: true,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  Divider(height: 1, color: hairline),
                ],
              ),
            ),
          ),
          Expanded(
            child: _viewIndex == 0
                ? _TablePreview(
                    rows: widget.rows,
                    showAllColumns: _showAllColumns,
                  )
                : _PdfPreviewPane(
                    rows: widget.rows,
                    filterSummary: widget.filterSummary,
                  ),
          ),
          _ExportBottomBar(
            exporting: _exporting,
            onCsv: () => _runExport(
              () => RspApplicationsReportExport.shareCsv(
                rows: widget.rows,
                filterSummary: widget.filterSummary,
              ),
              'CSV downloaded.',
            ),
            onPdf: () => _runExport(
              () => RspApplicationsReportExport.sharePdf(
                rows: widget.rows,
                filterSummary: widget.filterSummary,
              ),
              'PDF downloaded.',
            ),
            onPrint: () => _runExport(
              () => RspApplicationsReportExport.printPdf(
                context: context,
                rows: widget.rows,
                filterSummary: widget.filterSummary,
              ),
              'Print dialog opened.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.index,
    required this.enabled,
    required this.onChanged,
  });

  final int index;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleChip(
              label: 'Table',
              icon: Icons.table_rows_rounded,
              selected: index == 0,
              enabled: enabled,
              accent: accent,
              primary: primary,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _ToggleChip(
              label: 'PDF',
              icon: Icons.picture_as_pdf_rounded,
              selected: index == 1,
              enabled: enabled,
              accent: accent,
              primary: primary,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.accent,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color accent;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final dark = AppTheme.dashIsDark(context);

    return Material(
      color: selected ? panel : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? accent : primary.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? accent : primary.withValues(alpha: 0.65),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
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
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10.5,
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

class _ExportBottomBar extends StatelessWidget {
  const _ExportBottomBar({
    required this.exporting,
    required this.onCsv,
    required this.onPdf,
    required this.onPrint,
  });

  final bool exporting;
  final VoidCallback onCsv;
  final VoidCallback onPdf;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;

    return Material(
      color: panel,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: hairline)),
          ),
          child: exporting
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: _ExportButton(
                        icon: Icons.table_chart_rounded,
                        label: 'CSV',
                        color: const Color(0xFF2E7D32),
                        onTap: onCsv,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ExportButton(
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'PDF',
                        color: const Color(0xFFC62828),
                        onTap: onPdf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onPrint,
                        icon: const Icon(Icons.print_rounded, size: 20),
                        label: const Text('Print'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final hairline = AppTheme.dashHairlineOf(context);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: hairline),
        backgroundColor: color.withValues(alpha: dark ? 0.12 : 0.06),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  const _TablePreview({
    required this.rows,
    required this.showAllColumns,
  });

  final List<RspApplicationsReportRow> rows;
  final bool showAllColumns;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 48,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 12),
              Text(
                'No applicants match the current filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _ApplicantReportCard(
          index: index + 1,
          row: rows[index],
          showDocuments: showAllColumns,
        );
      },
    );
  }
}

class _ApplicantReportCard extends StatelessWidget {
  const _ApplicantReportCard({
    required this.index,
    required this.row,
    required this.showDocuments,
  });

  final int index;
  final RspApplicationsReportRow row;
  final bool showDocuments;

  String get _fullName {
    final parts = [
      row.firstName,
      if (row.middleName.isNotEmpty) row.middleName,
      row.lastName,
      if (row.suffix.isNotEmpty) row.suffix,
    ];
    return parts.join(' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: muted,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryNavy.withValues(
                    alpha: AppTheme.dashIsDark(context) ? 0.35 : 0.12,
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.dashIsDark(context)
                          ? AppTheme.primaryNavyLight
                          : AppTheme.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullName.isEmpty ? '(No name)' : _fullName,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (row.gender.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.gender,
                          style: TextStyle(color: secondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                _StatusChip(label: row.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(
                  icon: Icons.work_outline_rounded,
                  label: 'Position',
                  value: row.positionApplied.isEmpty ? '-' : row.positionApplied,
                ),
                if (row.email.isNotEmpty)
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: row.email,
                  ),
                if (row.phone.isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: row.phone,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ExamChip(outcome: row.examOutcome),
                    if (row.examScorePercent.isNotEmpty)
                      _ScoreChip(label: 'Overall', value: row.examScorePercent),
                    if (row.generalPercent.isNotEmpty)
                      _ScoreChip(label: 'Gen', value: row.generalPercent),
                    if (row.mathPercent.isNotEmpty)
                      _ScoreChip(label: 'Math', value: row.mathPercent),
                    if (row.generalInfoPercent.isNotEmpty)
                      _ScoreChip(label: 'Info', value: row.generalInfoPercent),
                    if (row.beiPercent.isNotEmpty)
                      _ScoreChip(label: 'BEI', value: row.beiPercent),
                  ],
                ),
                if (row.appliedAt.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Applied ${row.appliedAt}',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (showDocuments) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: hairline),
                  const SizedBox(height: 10),
                  Text(
                    'DOCUMENTS',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DocRow(label: 'Application letter', value: row.applicationLetter),
                  _DocRow(label: 'Resume', value: row.resume),
                  _DocRow(label: 'TOR', value: row.tor),
                  _DocRow(
                    label: 'Eligibility / trainings',
                    value: row.eligibilityTrainings,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: primary, height: 1.35),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hasFile = value != 'No' && value.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            hasFile ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 16,
            color: hasFile ? const Color(0xFF2E7D32) : secondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (label) {
      case 'Hired':
        bg = const Color(0xFF2E7D32);
        fg = Colors.white;
        break;
      case 'Documents Approved':
        bg = const Color(0xFF1565C0);
        fg = Colors.white;
        break;
      case 'Exam Passed':
        bg = AppTheme.primaryNavy;
        fg = Colors.white;
        break;
      case 'Exam Not Passed':
      case 'Documents Declined':
        bg = Colors.red.shade700;
        fg = Colors.white;
        break;
      case 'Exam Submitted':
        bg = const Color(0xFF6A1B9A);
        fg = Colors.white;
        break;
      default:
        final dark = AppTheme.dashIsDark(context);
        bg = dark ? const Color(0xFF37474F) : const Color(0xFFECEFF1);
        fg = dark ? Colors.white70 : const Color(0xFF455A64);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ExamChip extends StatelessWidget {
  const _ExamChip({required this.outcome});

  final String outcome;

  @override
  Widget build(BuildContext context) {
    final isPassed = outcome == 'Passed';
    final isFailed = outcome == 'Failed';
    final isNone = outcome == 'No exam';

    Color bg;
    Color fg;
    if (isPassed) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else if (isFailed) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
    } else if (isNone) {
      bg = AppTheme.dashMutedSurfaceOf(context);
      fg = AppTheme.dashTextSecondaryOf(context);
    } else {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
    }

    if (AppTheme.dashIsDark(context)) {
      if (isPassed) {
        bg = const Color(0xFF1B3D24);
        fg = const Color(0xFF81C784);
      } else if (isFailed) {
        bg = const Color(0xFF3D2020);
        fg = const Color(0xFFE57373);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        outcome,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value%',
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PdfPreviewPane extends StatelessWidget {
  const _PdfPreviewPane({
    required this.rows,
    required this.filterSummary,
  });

  final List<RspApplicationsReportRow> rows;
  final String filterSummary;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);

    return PdfPreview(
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      maxPageWidth: 900,
      pdfPreviewPageDecoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      scrollViewDecoration: BoxDecoration(
        color: AppTheme.dashCanvasOf(context),
      ),
      loadingWidget: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Building PDF preview…',
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
            ),
          ],
        ),
      ),
      build: (_) async {
        final doc = await RspApplicationsReportExport.buildPdf(
          rows: rows,
          filterSummary: filterSummary,
        );
        return doc.save();
      },
    );
  }
}
