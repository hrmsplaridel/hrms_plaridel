import 'package:flutter/material.dart';

import '../api/user_facing_api_error.dart';
import '../data/training_daily_report.dart';
import '../landingpage/constants/app_theme.dart';
import '../widgets/read_only_saved_entry_dialog.dart';
import '../widgets/training_daily_report_read_only_view.dart';
import '../widgets/training_report_attachment_preview.dart';

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
      decoration: InputDecoration(
        hintText: 'Search by name, title, or notes…',
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.65),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppTheme.textSecondary.withValues(alpha: 0.75),
          size: 22,
        ),
        filled: true,
        fillColor: AppTheme.offWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppTheme.lightGray.withValues(alpha: 0.9),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppTheme.lightGray.withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppTheme.primaryNavy.withValues(alpha: 0.65),
            width: 1.5,
          ),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TrainingDailyReportRepo.instance.listAllReports(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _reports = list;
          _loading = false;
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
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
      backgroundColor: AppTheme.sectionAlt,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
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
                  Text(
                    'Training Daily Reports',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitor daily reports from employees under training, review attachments, and mark them as seen.',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.92),
                      fontSize: 14.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 56,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryNavy,
                          AppTheme.primaryNavy.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  narrowToolbar
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TrainingDailySearchField(
                              controller: _searchController,
                              onSubmitted: _load,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                tooltip: 'Refresh',
                                onPressed: _load,
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy
                                      .withValues(alpha: 0.1),
                                  foregroundColor: AppTheme.primaryNavy,
                                  side: BorderSide(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 22,
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
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: _load,
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.primaryNavy
                                    .withValues(alpha: 0.1),
                                foregroundColor: AppTheme.primaryNavy,
                                side: BorderSide(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                padding: const EdgeInsets.all(14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 22),
                            ),
                          ],
                        ),
                  const SizedBox(height: 16),
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
                                      Icons.assignment_outlined,
                                      size: 40,
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No reports match your search',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try another keyword or refresh after employees submit.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightGray.withValues(alpha: 0.85)),
        boxShadow: AppTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavy,
                  AppTheme.primaryNavyLight.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                    size: 24,
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
                                  r.employeeName ?? 'Unknown employee',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
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
                                      color: AppTheme.textSecondary.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        r.title,
                                        style: TextStyle(
                                          color: AppTheme.textSecondary
                                              .withValues(alpha: 0.95),
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
                          color: AppTheme.sectionAlt.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Text(
                          desc.isEmpty ? 'No description provided.' : desc,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: desc.isEmpty
                                ? AppTheme.textSecondary.withValues(alpha: 0.65)
                                : AppTheme.textPrimary.withValues(alpha: 0.88),
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
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Submitted $submitted',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.88,
                              ),
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
                      Divider(
                        height: 1,
                        color: AppTheme.lightGray.withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Wrap(
                              spacing: 0,
                              runSpacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: () => showReadOnlySavedEntryDialog(
                                    context,
                                    title: 'Training daily report',
                                    previewBuilder: () =>
                                        TrainingDailyReportReadOnlyView(
                                          report: r,
                                        ),
                                    contentWidth: 560,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primaryNavy,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.article_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('View form'),
                                ),
                                if (onViewFile != null)
                                  TextButton.icon(
                                    onPressed: onViewFile,
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.primaryNavy,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('View file'),
                                  ),
                              ],
                            ),
                          ),
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
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: onMarkSeen,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryNavy,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
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
    Color color;
    switch (status.toLowerCase()) {
      case 'seen':
        color = const Color(0xFF0EA5E9);
        break;
      case 'reviewed':
        color = Colors.indigo;
        break;
      case 'approved':
        color = Colors.green;
        break;
      case 'needs_revision':
      case 'needs-revision':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    final label = status.isEmpty
        ? '—'
        : (status[0].toUpperCase() + status.substring(1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
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
