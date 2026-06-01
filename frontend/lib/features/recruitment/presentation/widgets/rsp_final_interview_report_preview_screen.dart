import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_final_interview_report_export.dart';

/// Preview for the Final interview (passed exam) report.
class RspFinalInterviewReportPreviewScreen extends StatefulWidget {
  const RspFinalInterviewReportPreviewScreen({
    super.key,
    required this.rows,
    required this.filterSummary,
  });

  final List<RspFinalInterviewReportRow> rows;
  final String filterSummary;

  static Future<void> open(
    BuildContext context, {
    required List<RspFinalInterviewReportRow> rows,
    required String filterSummary,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RspFinalInterviewReportPreviewScreen(
          rows: rows,
          filterSummary: filterSummary,
        ),
      ),
    );
  }

  @override
  State<RspFinalInterviewReportPreviewScreen> createState() =>
      _RspFinalInterviewReportPreviewScreenState();
}

class _RspFinalInterviewReportPreviewScreenState
    extends State<RspFinalInterviewReportPreviewScreen> {
  int _viewIndex = 0;
  bool _exporting = false;

  int get _scheduledCount =>
      widget.rows.where((r) => r.finalInterviewScheduled.isNotEmpty).length;

  int get _hiredCount => widget.rows.where((r) => r.hired == 'Yes').length;

  Future<void> _runExport(
    Future<void> Function() action,
    String success,
  ) async {
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

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      body: Column(
        children: [
          Material(
            color: panel,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: primary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Final interview report',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                '${widget.rows.length} passed exam',
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _ViewToggle(
                      index: _viewIndex,
                      enabled: !_exporting,
                      onChanged: (i) => setState(() => _viewIndex = i),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        _MiniStat(
                          label: 'Applicants',
                          value: '${widget.rows.length}',
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          label: 'Scheduled',
                          value: '$_scheduledCount',
                          color: const Color(0xFF6A1B9A),
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          label: 'Hired',
                          value: '$_hiredCount',
                          color: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: muted,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: hairline),
                      ),
                      child: Text(
                        widget.filterSummary,
                        style: TextStyle(color: secondary, fontSize: 13),
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
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = widget.rows[i];
                      return _ApplicantCard(index: i + 1, row: r);
                    },
                  )
                : PdfPreview(
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    useActions: false,
                    maxPageWidth: 900,
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFE8E8E8),
                    ),
                    scrollViewDecoration: BoxDecoration(
                      color: AppTheme.dashCanvasOf(context),
                    ),
                    build: (_) async {
                      final doc = await RspFinalInterviewReportExport.buildPdf(
                        rows: widget.rows,
                        filterSummary: widget.filterSummary,
                      );
                      return doc.save();
                    },
                  ),
          ),
          _ExportBottomBar(
            exporting: _exporting,
            accent: accent,
            onCsv: () => _runExport(
              () => RspFinalInterviewReportExport.shareCsv(
                rows: widget.rows,
                filterSummary: widget.filterSummary,
              ),
              'CSV downloaded.',
            ),
            onPdf: () => _runExport(
              () => RspFinalInterviewReportExport.sharePdf(
                rows: widget.rows,
                filterSummary: widget.filterSummary,
              ),
              'PDF downloaded.',
            ),
            onPrint: () => _runExport(
              () => RspFinalInterviewReportExport.printPdf(
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
              label: 'Cards',
              selected: index == 0,
              enabled: enabled,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _ToggleChip(
              label: 'PDF',
              selected: index == 1,
              enabled: enabled,
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
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final accent = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;

    return Material(
      color: selected ? panel : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? accent
                    : AppTheme.dashTextSecondaryOf(context),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
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
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    final hairline = AppTheme.dashHairlineOf(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hairline),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.index, required this.row});

  final int index;
  final RspFinalInterviewReportRow row;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.letterheadOrange, width: 3),
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text('$index', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    row.fullName.isEmpty ? '(No name)' : row.fullName,
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${row.examScorePercent}%',
                  style: TextStyle(
                    color: AppTheme.letterheadOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusPill(label: row.pipelineStatus),
                const SizedBox(height: 8),
                if (row.positionApplied.isNotEmpty)
                  Text(
                    'Position: ${row.positionApplied}',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                if (row.email.isNotEmpty)
                  Text(
                    'Email: ${row.email}',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                if (row.finalInterviewScheduled.isNotEmpty)
                  Text(
                    'Interview: ${row.finalInterviewScheduled}',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _Tag(label: 'Result: ${row.finalInterviewResult}'),
                    _Tag(label: 'HR setup: ${row.hrAccountSetup}'),
                    _Tag(label: 'Hired: ${row.hired}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(
          alpha: AppTheme.dashIsDark(context) ? 0.25 : 0.08,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.dashTextPrimaryOf(context),
        ),
      ),
    );
  }
}

class _ExportBottomBar extends StatelessWidget {
  const _ExportBottomBar({
    required this.exporting,
    required this.accent,
    required this.onCsv,
    required this.onPdf,
    required this.onPrint,
  });

  final bool exporting;
  final Color accent;
  final VoidCallback onCsv;
  final VoidCallback onPdf;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);

    return Material(
      color: panel,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: hairline)),
          ),
          child: exporting
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCsv,
                        child: const Text('CSV'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPdf,
                        child: const Text('PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onPrint,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Print'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
