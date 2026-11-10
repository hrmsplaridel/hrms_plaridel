import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/input_rules.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/shared/widgets/training_daily_report_date_filter.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/training_daily_report_read_only_view.dart';
import 'package:hrms_plaridel/shared/widgets/training_report_attachment_preview.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/ld_training_daily_reports_recycle_dialog.dart';

enum _StatusFilter { all, unreviewed, reviewed }

/// L&D admin: Training Daily Reports. Same APIs and actions as before.
class LdTrainingDailyReportsSection extends StatefulWidget {
  const LdTrainingDailyReportsSection({super.key});

  @override
  State<LdTrainingDailyReportsSection> createState() =>
      _LdTrainingDailyReportsSectionState();
}

class _LdTrainingDailyReportsSectionState
    extends State<LdTrainingDailyReportsSection> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = false;
  bool _refreshing = false;
  bool _bulkMarking = false;
  int _loadGeneration = 0;
  List<TrainingDailyReport> _reports = [];
  DateTime? _filterByDate;
  _StatusFilter _statusFilter = _StatusFilter.all;
  final Set<DateTime> _reportDatesCache = {};
  final Map<DateTime, int> _countByDay = {};

  List<DateTime> get _datesWithReports {
    final list = _reportDatesCache.toList()..sort((a, b) => b.compareTo(a));
    if (_filterByDate != null && !list.any((d) => d == _filterByDate)) {
      list.insert(0, _filterByDate!);
    }
    return list;
  }

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty ||
      _filterByDate != null ||
      _statusFilter != _StatusFilter.all;

  int get _reviewedCount =>
      _reports.where((r) => _isReviewedStatus(r.status)).length;

  int get _unreviewedCount => _reports.length - _reviewedCount;

  List<TrainingDailyReport> get _visibleReports {
    Iterable<TrainingDailyReport> list = _reports;
    switch (_statusFilter) {
      case _StatusFilter.unreviewed:
        list = list.where((r) => !_isReviewedStatus(r.status));
        break;
      case _StatusFilter.reviewed:
        list = list.where((r) => _isReviewedStatus(r.status));
        break;
      case _StatusFilter.all:
        break;
    }
    final sorted = list.toList()
      ..sort((a, b) {
        final aSeen = _isReviewedStatus(a.status);
        final bSeen = _isReviewedStatus(b.status);
        if (aSeen != bSeen) return aSeen ? 1 : -1;
        return b.submittedAt.compareTo(a.submittedAt);
      });
    return sorted;
  }

  void _onFilterDateChanged(DateTime? day) {
    setState(() => _filterByDate = day);
    _load();
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.clear();
    _searchController.addListener(_onSearchChanged);
    setState(() {
      _filterByDate = null;
      _statusFilter = _StatusFilter.all;
    });
    _load();
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
      }
    });
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
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _reports = list;
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
    } catch (_) {
      // Keep current list on failure.
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _markSeen(TrainingDailyReport report) async {
    try {
      final updated = await TrainingDailyReportRepo.instance.markAsSeen(
        report.id,
      );
      if (!mounted) return;
      _invalidateDocuTrackerDocuments();
      setState(() {
        final idx = _reports.indexWhere((r) => r.id == report.id);
        if (idx != -1) _reports[idx] = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked report as seen.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark as seen: $e')));
    }
  }

  Future<void> _markAllUnreviewedSeen() async {
    final pending = _visibleReports
        .where((r) => !_isReviewedStatus(r.status))
        .toList();
    if (pending.isEmpty || _bulkMarking) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark all as seen?'),
        content: Text(
          'Mark ${pending.length} unreviewed '
          '${pending.length == 1 ? 'report' : 'reports'} as seen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkMarking = true);
    var success = 0;
    try {
      for (final report in pending) {
        final updated = await TrainingDailyReportRepo.instance.markAsSeen(
          report.id,
        );
        if (!mounted) return;
        setState(() {
          final idx = _reports.indexWhere((r) => r.id == report.id);
          if (idx != -1) _reports[idx] = updated;
        });
        success += 1;
      }
      _invalidateDocuTrackerDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success == 1
                ? 'Marked 1 report as seen.'
                : 'Marked $success reports as seen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success > 0
                ? 'Marked $success, then failed: ${userFacingApiError(e)}'
                : 'Failed to mark as seen: ${userFacingApiError(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkMarking = false);
    }
  }

  void _invalidateDocuTrackerDocuments() {
    try {
      context.read<DocuTrackerProvider>().invalidateDocuments();
    } catch (_) {}
  }

  Future<void> _confirmAndDelete(TrainingDailyReport report) async {
    final who = report.employeeName ?? 'Unknown employee';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to recycle bin?'),
        content: Text(
          'The report moves to the recycle bin. You can view it, restore it, '
          'or delete it permanently from there.\n\n'
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
            child: const Text('Move to bin'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TrainingDailyReportRepo.instance.deleteReport(report.id);
      if (!mounted) return;
      _invalidateDocuTrackerDocuments();
      setState(() {
        _reports.removeWhere((r) => r.id == report.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Moved to the recycle bin.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${userFacingApiError(e)}')),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 720;
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Training Daily Reports',
          style: TextStyle(
            color: primary,
            fontSize: mobile ? 22 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.35,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Monitor employee training reports, attachments, and review status.',
          style: TextStyle(
            color: secondary,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        _filterToolbar(context, mobile: mobile, hairline: hairline),
        if (_datesWithReports.length > 1) ...[
          const SizedBox(height: 8),
          _daysWithReportsChips(context),
        ],
        if (!_loading && _reports.isNotEmpty) ...[
          const SizedBox(height: 12),
          _summaryRow(context, compact: mobile),
          if (_unreviewedCount > 0 &&
              _statusFilter != _StatusFilter.reviewed) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: (_bulkMarking || _loading || _refreshing)
                    ? null
                    : _markAllUnreviewedSeen,
                icon: _bulkMarking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_rounded, size: 18),
                label: Text(
                  _statusFilter == _StatusFilter.unreviewed
                      ? 'Mark visible as seen ($_unreviewedCount)'
                      : 'Mark all unreviewed ($_unreviewedCount)',
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_reports.isEmpty)
          _ReportEmptyState(
            hasFilters: _hasActiveFilters,
            filterByDate: _filterByDate,
            onClear: _hasActiveFilters ? _clearFilters : null,
          )
        else if (_visibleReports.isEmpty)
          _ReportEmptyState(
            hasFilters: true,
            filterByDate: _filterByDate,
            onClear: _clearFilters,
            customSubtitle: _statusFilter == _StatusFilter.unreviewed
                ? 'No unreviewed reports in this view. Switch to All or Reviewed, or clear filters.'
                : 'No reviewed reports match the current filters.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _visibleReports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = _visibleReports[index];
              return _TrainingReportCard(
                key: ValueKey(r.id),
                report: r,
                compact: mobile,
                onView: () => _openReport(context, r),
                onViewFile: r.attachmentUrl != null
                    ? () => showTrainingReportAttachmentPreview(
                        context,
                        url: r.attachmentUrl!,
                        fileName: r.attachmentName,
                        mimeType: r.attachmentType,
                      )
                    : null,
                onDownloadFile: r.attachmentUrl != null
                    ? () => _openAttachmentUrl(r.attachmentUrl!)
                    : null,
                onMarkSeen: () => _markSeen(r),
                onDelete: () => _confirmAndDelete(r),
              );
            },
          ),
      ],
    );
  }

  Widget _filterToolbar(
    BuildContext context, {
    required bool mobile,
    required Color hairline,
  }) {
    final search = TextField(
      controller: _searchController,
      enabled: !_loading,
      inputFormatters: InputRules.plainTextFormatters(
        maxLength: 200,
        allowNewlines: false,
      ),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search employee, training, or report...',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppTheme.dashTextSecondaryOf(context),
          size: 20,
        ),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.removeListener(_onSearchChanged);
                  _searchController.clear();
                  _searchController.addListener(_onSearchChanged);
                  setState(() {});
                  _load(silent: true);
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      onSubmitted: (_) {
        _searchDebounce?.cancel();
        _load(silent: true);
      },
    );

    final dateControls = TrainingDailyReportDateToolbar(
      filterByDate: _filterByDate,
      datesWithReports: _datesWithReports,
      onDateChanged: _onFilterDateChanged,
      compact: mobile,
    );

    final recycle = IconButton(
      tooltip: 'Recycle bin',
      onPressed: _loading
          ? null
          : () => showTrainingDailyReportsRecycleBin(
              context: context,
              onChanged: () {
                if (mounted) _load();
              },
            ),
      icon: const Icon(Icons.restore_from_trash_outlined),
    );

    final refresh = IconButton(
      tooltip: _refreshing ? 'Refreshing reports' : 'Refresh reports',
      onPressed: (_loading || _refreshing)
          ? null
          : () => _load(silent: true),
      icon: (_loading || _refreshing)
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
    );

    final clear = _hasActiveFilters
        ? TextButton(
            onPressed: _loading ? null : _clearFilters,
            child: const Text('Clear filters'),
          )
        : const SizedBox.shrink();

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: dateControls,
                ),
              ),
              recycle,
              refresh,
            ],
          ),
          if (_hasActiveFilters)
            Align(alignment: Alignment.centerLeft, child: clear),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      child: Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 8),
          dateControls,
          recycle,
          refresh,
          if (_hasActiveFilters) clear,
        ],
      ),
    );
  }

  Widget _daysWithReportsChips(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _datesWithReports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final day = _datesWithReports[index];
          final selected = _filterByDate == day;
          final count = _countByDay[day] ?? 0;
          return InputChip(
            visualDensity: VisualDensity.compact,
            label: Text(
              count > 0
                  ? '${TrainingDailyReportDateUtils.formatDisplay(day)} ($count)'
                  : TrainingDailyReportDateUtils.formatDisplay(day),
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: selected,
            onPressed: () => _onFilterDateChanged(day),
            selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
            side: BorderSide(
              color: selected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.4)
                  : AppTheme.dashHairlineOf(context),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow(BuildContext context, {required bool compact}) {
    final chips = [
      _StatChip(
        icon: Icons.assignment_outlined,
        label: '${_reports.length} Report${_reports.length == 1 ? '' : 's'}',
        color: AppTheme.dashTextSecondaryOf(context),
        selected: _statusFilter == _StatusFilter.all,
        onTap: () => setState(() => _statusFilter = _StatusFilter.all),
      ),
      _StatChip(
        icon: Icons.mark_email_unread_outlined,
        label: '$_unreviewedCount Unreviewed',
        color: AppTheme.primaryNavy,
        selected: _statusFilter == _StatusFilter.unreviewed,
        onTap: () => setState(() => _statusFilter = _StatusFilter.unreviewed),
      ),
      _StatChip(
        icon: Icons.check_circle_outline_rounded,
        label: '$_reviewedCount Reviewed',
        color: const Color(0xFF2E7D32),
        selected: _statusFilter == _StatusFilter.reviewed,
        onTap: () => setState(() => _statusFilter = _StatusFilter.reviewed),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (_statusFilter != _StatusFilter.all) ...[
          const SizedBox(height: 6),
          Text(
            _statusFilter == _StatusFilter.unreviewed
                ? 'Showing unreviewed only · tap All to reset'
                : 'Showing reviewed only · tap All to reset',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.dashTextSecondaryOf(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  void _openReport(BuildContext context, TrainingDailyReport r) {
    showReadOnlySavedEntryDialog(
      context,
      title: 'Training daily report',
      subtitle: r.title.trim().isNotEmpty
          ? r.title
          : r.submittedAt.toLocal().toString().split('.').first,
      previewBuilder: () => TrainingDailyReportReadOnlyView(report: r),
      contentWidth: 640,
    );
  }

  Future<void> _openAttachmentUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

bool _isReviewedStatus(String status) {
  switch (status.toLowerCase()) {
    case 'seen':
    case 'reviewed':
    case 'approved':
      return true;
    default:
      return false;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.45 : 0.18),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportStatusBadge extends StatelessWidget {
  const _ReportStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final reviewed = _isReviewedStatus(status);
    final color = reviewed ? const Color(0xFF2E7D32) : AppTheme.primaryNavy;
    final label = reviewed ? 'Reviewed' : 'Unreviewed';
    final icon = reviewed
        ? Icons.check_circle_outline_rounded
        : Icons.mark_email_unread_outlined;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportEmptyState extends StatelessWidget {
  const _ReportEmptyState({
    required this.hasFilters,
    required this.filterByDate,
    this.onClear,
    this.customSubtitle,
  });

  final bool hasFilters;
  final DateTime? filterByDate;
  final VoidCallback? onClear;
  final String? customSubtitle;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final title = hasFilters ? 'No reports found' : 'No training reports yet';
    final subtitle = customSubtitle ??
        (hasFilters
            ? (filterByDate != null
                  ? 'No training reports match your current search or selected date.'
                  : 'Try adjusting your search or filters.')
            : 'Daily reports submitted by employees undergoing training will appear here.');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 36,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
              ),
              if (onClear != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear filters'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingReportCard extends StatefulWidget {
  const _TrainingReportCard({
    super.key,
    required this.report,
    required this.compact,
    required this.onView,
    required this.onMarkSeen,
    required this.onDelete,
    this.onViewFile,
    this.onDownloadFile,
  });

  final TrainingDailyReport report;
  final bool compact;
  final VoidCallback onView;
  final VoidCallback onMarkSeen;
  final VoidCallback onDelete;
  final VoidCallback? onViewFile;
  final VoidCallback? onDownloadFile;

  @override
  State<_TrainingReportCard> createState() => _TrainingReportCardState();
}

class _TrainingReportCardState extends State<_TrainingReportCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // Unreviewed reports open by default so HR can review faster.
    _expanded = !_isReviewedStatus(widget.report.status);
  }

  TrainingDailyReport get report => widget.report;
  bool get compact => widget.compact;
  VoidCallback get onView => widget.onView;
  VoidCallback get onMarkSeen => widget.onMarkSeen;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback? get onViewFile => widget.onViewFile;
  VoidCallback? get onDownloadFile => widget.onDownloadFile;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final r = report;
    final desc = (r.description ?? '').trim();
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final name = r.employeeName ?? 'Unknown employee';
    final reviewed = _isReviewedStatus(r.status);
    final title = r.title.trim().isEmpty ? 'Untitled training' : r.title;
    final hasAttachment = r.attachmentUrl != null;
    final relative = _formatRelativeTime(r.submittedAt);

    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 16,
          14,
          compact ? 12 : 16,
          14,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: reviewed
                ? hairline
                : AppTheme.primaryNavy.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(8),
                hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.03),
                child: Semantics(
                  button: true,
                  expanded: _expanded,
                  label: _expanded ? 'Collapse report' : 'Expand report',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _initialsAvatar(context, name),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$title · ${_formatReportDate(r.submittedAt)} · ${_formatReportTime(r.submittedAt)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    relative,
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (hasAttachment) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.attach_file_rounded,
                                      size: 14,
                                      color: secondary,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Attachment',
                                      style: TextStyle(
                                        color: secondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!_expanded && desc.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: primary.withValues(alpha: 0.88),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ReportStatusBadge(status: r.status),
                        const SizedBox(width: 2),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: secondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Daily Report',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          desc.isEmpty ? 'No description provided.' : desc,
                          style: TextStyle(
                            color: desc.isEmpty
                                ? secondary.withValues(alpha: 0.8)
                                : primary,
                            fontSize: 13.5,
                            height: 1.4,
                            fontStyle: desc.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        if (r.attachmentUrl != null) ...[
                          const SizedBox(height: 10),
                          _attachmentChip(context, r),
                        ],
                        if (reviewed && r.seenAt != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Seen ${_formatReportDate(r.seenAt!)} · ${_formatReportTime(r.seenAt!)}',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _actions(context, reviewed: reviewed),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialsAvatar(BuildContext context, String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    var initials = '';
    if (parts.isNotEmpty) initials += parts.first[0].toUpperCase();
    if (parts.length > 1) initials += parts.last[0].toUpperCase();
    if (initials.isEmpty) initials = '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
        ),
      ),
    );
  }

  Widget _attachmentChip(BuildContext context, TrainingDailyReport r) {
    final label = _friendlyAttachmentLabel(r);
    final icon = _attachmentIcon(r);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
          ),
          if (onViewFile != null)
            TextButton(
              onPressed: onViewFile,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(44, 36),
              ),
              child: const Text('View'),
            ),
          if (onDownloadFile != null)
            TextButton(
              onPressed: onDownloadFile,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(44, 36),
              ),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, {required bool reviewed}) {
    final viewBtn = compact
        ? SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                side: BorderSide(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.35),
                ),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('View Report'),
            ),
          )
        : OutlinedButton(
            onPressed: onView,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: BorderSide(
                color: AppTheme.primaryNavy.withValues(alpha: 0.35),
              ),
              minimumSize: const Size(0, 40),
            ),
            child: const Text('View'),
          );

    final Widget seenBtn;
    if (reviewed) {
      seenBtn = compact
          ? SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMarkSeen,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Seen · mark again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            )
          : TextButton.icon(
              onPressed: onMarkSeen,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Seen · mark again'),
            );
    } else if (compact) {
      seenBtn = SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onMarkSeen,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Mark as Seen'),
        ),
      );
    } else {
      seenBtn = FilledButton.icon(
        onPressed: onMarkSeen,
        icon: const Icon(Icons.visibility_rounded, size: 18),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryNavy,
          minimumSize: const Size(0, 40),
        ),
        label: const Text('Mark as Seen'),
      );
    }

    final deleteBtn = IconButton(
      tooltip: 'Move to recycle bin',
      onPressed: onDelete,
      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!reviewed) ...[
            seenBtn,
            const SizedBox(height: 8),
            viewBtn,
          ] else ...[
            viewBtn,
            const SizedBox(height: 8),
            seenBtn,
          ],
          Align(alignment: Alignment.centerRight, child: deleteBtn),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!reviewed) seenBtn else viewBtn,
        if (!reviewed) viewBtn else seenBtn,
        deleteBtn,
      ],
    );
  }
}

String _formatReportDate(DateTime utc) {
  final l = utc.toLocal();
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
  return '${months[l.month - 1]} ${l.day}, ${l.year}';
}

String _formatReportTime(DateTime utc) {
  final l = utc.toLocal();
  final hour = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${l.minute.toString().padLeft(2, '0')} $ampm';
}

String _formatRelativeTime(DateTime utc) {
  final local = utc.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return _formatReportDate(utc);
}

String _friendlyAttachmentLabel(TrainingDailyReport r) {
  final name = (r.attachmentName ?? '').trim();
  final type = (r.attachmentType ?? '').toLowerCase();
  final ext = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  final looksHashed = RegExp(
    r'^[a-f0-9]{16,}\.[a-z0-9]+$',
    caseSensitive: false,
  ).hasMatch(name);

  final isImage = type.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);
  final isPdf = type.contains('pdf') || ext == 'pdf';

  if (looksHashed || name.isEmpty) {
    if (isImage) return 'Attached image${ext.isNotEmpty ? ' (.$ext)' : ''}';
    if (isPdf) return 'Attached PDF';
    return 'Attachment${ext.isNotEmpty ? ' (.$ext)' : ''}';
  }
  return name;
}

IconData _attachmentIcon(TrainingDailyReport r) {
  final name = (r.attachmentName ?? '').toLowerCase();
  final type = (r.attachmentType ?? '').toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : '';
  if (type.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext)) {
    return Icons.image_outlined;
  }
  if (type.contains('pdf') || ext == 'pdf') {
    return Icons.picture_as_pdf_outlined;
  }
  return Icons.attach_file_rounded;
}
