import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/shared/widgets/training_daily_report_date_filter.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/training_daily_report_read_only_view.dart';
import 'package:hrms_plaridel/shared/widgets/training_report_attachment_preview.dart';

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

  bool get _hasActiveFilters =>
      _searchController.text.trim().isNotEmpty || _filterByDate != null;

  int get _reviewedCount =>
      _reports.where((r) => _isReviewedStatus(r.status)).length;

  int get _unreviewedCount => _reports.length - _reviewedCount;

  void _onFilterDateChanged(DateTime? day) {
    setState(() => _filterByDate = day);
    _load();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _filterByDate = null);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
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
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
      ).showSnackBar(const SnackBar(content: Text('Marked report as seen.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark as seen: $e')));
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${userFacingApiError(e)}')),
      );
    }
  }

  @override
  void dispose() {
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
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = _reports[index];
              return _TrainingReportCard(
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
                  _searchController.clear();
                  _load();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      onSubmitted: (_) => _load(),
    );

    final dateControls = TrainingDailyReportDateToolbar(
      filterByDate: _filterByDate,
      datesWithReports: _datesWithReports,
      onDateChanged: _onFilterDateChanged,
      compact: mobile,
    );

    final refresh = IconButton(
      tooltip: 'Refresh reports',
      onPressed: _loading ? null : _load,
      icon: _loading
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
              refresh,
            ],
          ),
          if (_hasActiveFilters) Align(alignment: Alignment.centerLeft, child: clear),
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
      ),
      _StatChip(
        icon: Icons.mark_email_unread_outlined,
        label: '$_unreviewedCount Unreviewed',
        color: AppTheme.primaryNavy,
      ),
      _StatChip(
        icon: Icons.check_circle_outline_rounded,
        label: '$_reviewedCount Reviewed',
        color: const Color(0xFF2E7D32),
      ),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
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
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
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
  });

  final bool hasFilters;
  final DateTime? filterByDate;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final title = hasFilters
        ? 'No reports found'
        : 'No training reports yet';
    final subtitle = hasFilters
        ? (filterByDate != null
              ? 'No training reports match your current search or selected date.'
              : 'Try adjusting your search or filters.')
        : 'Daily reports submitted by employees undergoing training will appear here.';

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
                TextButton(onPressed: onClear, child: const Text('Clear filters')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingReportCard extends StatelessWidget {
  const _TrainingReportCard({
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
  Widget build(BuildContext context) {
    final r = report;
    final desc = (r.description ?? '').trim();
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final name = r.employeeName ?? 'Unknown employee';
    final reviewed = _isReviewedStatus(r.status);

    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.03),
        child: Container(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 14, compact ? 12 : 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hairline),
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
              Row(
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
                          r.title.trim().isEmpty ? 'Untitled training' : r.title,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ReportStatusBadge(status: r.status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _meta(context, Icons.event_outlined, _formatReportDate(r.submittedAt)),
                  _meta(context, Icons.schedule_rounded, _formatReportTime(r.submittedAt)),
                ],
              ),
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: desc.isEmpty ? secondary.withValues(alpha: 0.8) : primary,
                  fontSize: 13.5,
                  height: 1.4,
                  fontStyle: desc.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              if (r.attachmentUrl != null) ...[
                const SizedBox(height: 10),
                _attachmentChip(context, r),
              ],
              const SizedBox(height: 12),
              _actions(context, reviewed: reviewed),
            ],
          ),
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

  Widget _meta(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.dashTextSecondaryOf(context)),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  Widget _attachmentChip(BuildContext context, TrainingDailyReport r) {
    final fileName = (r.attachmentName ?? 'Attachment').trim();
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
            Icons.attach_file_rounded,
            size: 16,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
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
            child: FilledButton(
              onPressed: onView,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('View Report'),
            ),
          )
        : OutlinedButton(
            onPressed: onView,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.35)),
              minimumSize: const Size(0, 40),
            ),
            child: const Text('View'),
          );

    final seenBtn = compact
        ? SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onMarkSeen,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(reviewed ? 'Mark as seen again' : 'Mark as Seen'),
            ),
          )
        : FilledButton(
            onPressed: onMarkSeen,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Mark as Seen'),
          );

    final deleteBtn = IconButton(
      tooltip: 'Delete report',
      onPressed: onDelete,
      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
    );

    if (compact) {
      return Column(
        children: [
          viewBtn,
          const SizedBox(height: 8),
          seenBtn,
          Align(alignment: Alignment.centerRight, child: deleteBtn),
        ],
      );
    }

    return Row(
      children: [
        viewBtn,
        const SizedBox(width: 8),
        seenBtn,
        const Spacer(),
        deleteBtn,
      ],
    );
  }
}

String _formatReportDate(DateTime utc) {
  final l = utc.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[l.month - 1]} ${l.day}, ${l.year}';
}

String _formatReportTime(DateTime utc) {
  final l = utc.toLocal();
  final hour = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${l.minute.toString().padLeft(2, '0')} $ampm';
}
