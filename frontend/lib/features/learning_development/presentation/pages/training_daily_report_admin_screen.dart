import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/widgets/training_daily_report_date_filter.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/training_daily_report_read_only_view.dart';
import 'package:hrms_plaridel/shared/widgets/training_report_attachment_preview.dart';

String _formatTrainingDailySubmittedAt(DateTime utc) {
  final l = utc.toLocal();
  String z2(int x) => x.toString().padLeft(2, '0');
  return '${l.year}-${z2(l.month)}-${z2(l.day)} ${z2(l.hour)}:${z2(l.minute)}:${z2(l.second)}';
}

class _TrainingDailySearchField extends StatelessWidget {
  const _TrainingDailySearchField({
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final void Function() onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search by name, title, or notes…',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppTheme.dashTextSecondaryOf(context),
          size: 22,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class TrainingDailyReportAdminScreen extends StatefulWidget {
  const TrainingDailyReportAdminScreen({super.key});

  @override
  State<TrainingDailyReportAdminScreen> createState() =>
      _TrainingDailyReportAdminScreenState();
}

class _TrainingDailyReportAdminScreenState
    extends State<TrainingDailyReportAdminScreen> {
  final _searchController = TextEditingController();
  bool _loading = false;
  List<TrainingDailyReport> _reports = [];
  DateTime? _filterByDate;
  final Set<DateTime> _reportDatesCache = {};
  final Map<DateTime, int> _countByDay = {};

  List<DateTime> get _datesWithReports {
    final list = _reportDatesCache.toList()..sort((a, b) => b.compareTo(a));
    if (_filterByDate != null && !list.any((d) => d == _filterByDate)) {
      list.insert(0, _filterByDate!);
    }
    return list;
  }

  void _onFilterDateChanged(DateTime? day) {
    setState(() => _filterByDate = day);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateQ = _filterByDate != null
          ? TrainingDailyReportDateUtils.formatQuery(_filterByDate!)
          : null;
      final list = await TrainingDailyReportRepo.instance.listAllReports(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        fromDate: dateQ,
        toDate: dateQ,
      );
      if (mounted) {
        setState(() {
          _reports = list;
          _loading = false;
          if (_filterByDate == null) {
            _reportDatesCache.clear();
            _countByDay.clear();
            for (final r in list) {
              final d = TrainingDailyReportDateUtils.toLocalDate(r.submittedAt);
              _reportDatesCache.add(d);
              _countByDay[d] = (_countByDay[d] ?? 0) + 1;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _markSeen(TrainingDailyReport report) async {
    try {
      final updated = await TrainingDailyReportRepo.instance.markAsSeen(
        report.id,
      );
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((r) => r.id == report.id);
        if (idx != -1) _reports[idx] = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as seen.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to mark as seen: $e')));
      }
    }
  }

  Future<void> _confirmAndDelete(TrainingDailyReport report) async {
    final who = report.employeeName ?? 'Unknown employee';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          'This permanently removes the record from the system. '
          'Attachments linked to this report will also be removed.\n\n'
          '$who — ${report.title}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TrainingDailyReportRepo.instance.deleteReport(report.id);
      if (!mounted) return;
      setState(() {
        _reports.removeWhere((r) => r.id == report.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report deleted.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: ${userFacingApiError(e)}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1024;
    final narrowToolbar = width < 720;

    final dark = AppTheme.dashIsDark(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: dark ? AppTheme.dashPanelOf(context) : AppTheme.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 148,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: AppTheme.primaryNavy,
            ),
            label: Text(
              'Back to L&D',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        title: const SizedBox.shrink(),
      ),
      backgroundColor: AppTheme.sectionAltOf(context),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 24 : 12,
          vertical: isWide ? 20 : 12,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 1100 : double.infinity,
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 24 : 16,
                vertical: isWide ? 20 : 16,
              ),
              decoration: BoxDecoration(
                color: AppTheme.dashPanelOf(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.07),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryNavy.withValues(alpha: 0.14),
                              AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                            ],
                          ),
                          border: Border.all(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          size: 26,
                          color: AppTheme.primaryNavy,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Training Daily Reports',
                              style: TextStyle(
                                color: AppTheme.dashTextPrimaryOf(context),
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Monitor daily reports from employees under training, review attachments, and mark them as seen.',
                              style: TextStyle(
                                color: AppTheme.dashTextSecondaryOf(context),
                                fontSize: 14.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.dashMutedSurfaceOf(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.dashHairlineOf(context),
                      ),
                    ),
                    child: narrowToolbar
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TrainingDailySearchField(
                                controller: _searchController,
                                onSubmitted: _load,
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 20,
                                ),
                                label: const Text('Refresh'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _TrainingDailySearchField(
                                  controller: _searchController,
                                  onSubmitted: _load,
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 20,
                                ),
                                label: const Text('Refresh'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  TrainingDailyReportDateFilterBar(
                    filterByDate: _filterByDate,
                    datesWithReports: _datesWithReports,
                    onDateChanged: _onFilterDateChanged,
                    countForDay: (day) => _countByDay[day] ?? 0,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _reports.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.08,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _filterByDate != null
                                          ? Icons.event_busy_rounded
                                          : Icons.assignment_outlined,
                                      size: 40,
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _filterByDate != null
                                        ? 'No reports on ${TrainingDailyReportDateUtils.formatDisplay(_filterByDate!)}'
                                        : 'No reports match your search',
                                    style: TextStyle(
                                      color: AppTheme.dashTextPrimaryOf(
                                        context,
                                      ),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _filterByDate != null
                                        ? 'Pick another date from the calendar or tap Show all.'
                                        : 'Try another keyword or refresh after employees submit.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppTheme.dashTextSecondaryOf(
                                        context,
                                      ),
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _ReportsList(
                            reports: _reports,
                            onMarkSeen: _markSeen,
                            onDelete: _confirmAndDelete,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({
    required this.reports,
    required this.onMarkSeen,
    required this.onDelete,
  });

  final List<TrainingDailyReport> reports;
  final void Function(TrainingDailyReport) onMarkSeen;
  final Future<void> Function(TrainingDailyReport) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = reports[index];
        return _ReportCard(
          report: r,
          onViewFile: r.attachmentUrl != null
              ? () => showTrainingReportAttachmentPreview(
                  context,
                  url: r.attachmentUrl!,
                  fileName: r.attachmentName,
                  mimeType: r.attachmentType,
                )
              : null,
          onMarkSeen: () => onMarkSeen(r),
          onDelete: () => onDelete(r),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    this.onViewFile,
    required this.onMarkSeen,
    required this.onDelete,
  });

  final TrainingDailyReport report;
  final VoidCallback? onViewFile;
  final VoidCallback onMarkSeen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final desc = (r.description ?? '').trim();
    final submitted = _formatTrainingDailySubmittedAt(r.submittedAt);

    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final name = r.employeeName ?? 'Unknown employee';
    final parts = name.trim().split(RegExp(r'\s+'));
    var initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryNavy.withValues(alpha: 0.16),
                        AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: AppTheme.dashIsDark(context)
                          ? AppTheme.primaryNavyLight
                          : AppTheme.primaryNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.topic_rounded,
                                      size: 15,
                                      color: secondary.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        r.title,
                                        style: TextStyle(
                                          color: secondary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _StatusChip(status: r.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: muted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: hairline),
                        ),
                        child: Text(
                          desc.isEmpty ? 'No description provided.' : desc,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: desc.isEmpty
                                ? secondary.withValues(alpha: 0.75)
                                : primary,
                            fontSize: 13.5,
                            height: 1.45,
                            fontStyle: desc.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: secondary.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Submitted $submitted',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: hairline),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => showReadOnlySavedEntryDialog(
                                  context,
                                  title: 'Training daily report',
                                  subtitle: r.title.trim().isNotEmpty
                                      ? r.title
                                      : r.submittedAt
                                            .toLocal()
                                            .toString()
                                            .split('.')
                                            .first,
                                  previewBuilder: () =>
                                      TrainingDailyReportReadOnlyView(
                                        report: r,
                                      ),
                                  contentWidth: 640,
                                ),
                                icon: const Icon(
                                  Icons.article_outlined,
                                  size: 18,
                                ),
                                label: const Text('View form'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryNavy,
                                  side: BorderSide(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              if (onViewFile != null)
                                OutlinedButton.icon(
                                  onPressed: onViewFile,
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('View file'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryNavy,
                                    side: BorderSide(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: onDelete,
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.red.shade700,
                                ),
                                label: Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              FilledButton(
                                onPressed: onMarkSeen,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Mark as seen',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    Color color;
    switch (status.toLowerCase()) {
      case 'seen':
        color = const Color(0xFF0EA5E9);
        break;
      case 'reviewed':
        color = dark ? const Color(0xFF9FA8DA) : Colors.indigo;
        break;
      case 'approved':
        color = dark ? const Color(0xFF81C784) : Colors.green;
        break;
      case 'needs_revision':
      case 'needs-revision':
        color = dark ? const Color(0xFFFFB74D) : Colors.orange;
        break;
      case 'submitted':
        color = dark ? const Color(0xFFB0BEC5) : Colors.blueGrey;
        break;
      default:
        color = dark ? const Color(0xFFB0BEC5) : Colors.grey.shade700;
    }
    final label = status.isEmpty
        ? '—'
        : (status[0].toUpperCase() + status.substring(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: dark ? 0.22 : 0.14),
        border: Border.all(color: color.withValues(alpha: dark ? 0.45 : 0.28)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
