import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/training_daily_report.dart';
import '../landingpage/constants/app_theme.dart';
import '../widgets/read_only_saved_entry_dialog.dart';
import '../widgets/training_daily_report_read_only_view.dart';

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
      final updated =
          await TrainingDailyReportRepo.instance.markAsSeen(report.id);
      if (!mounted) return;
      setState(() {
        final idx = _reports.indexWhere((r) => r.id == report.id);
        if (idx != -1) _reports[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as seen.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark as seen: $e')),
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text('Training Daily Reports'),
      ),
      backgroundColor: const Color(0xFFF3F4F6),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 24 : 12,
          vertical: isWide ? 20 : 12,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWide ? 1100 : double.infinity),
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
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Monitor daily reports from employees under training, review attachments, and mark them as seen.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color:
                                    AppTheme.textSecondary.withValues(alpha: 0.8),
                                size: 22,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.55,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onSubmitted: (_) => _load(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton.filled(
                          tooltip: 'Refresh',
                          onPressed: _load,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            foregroundColor: AppTheme.textPrimary,
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                            : _reports.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.assignment_outlined,
                                      size: 48,
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No training daily reports found.',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _ReportsList(
                                reports: _reports,
                                onMarkSeen: _markSeen,
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

void _showAttachmentPreview(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attachment preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Preview for this file type is not supported.',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  final uri = Uri.parse(url);
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                                label: const Text('Open in new tab'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({
    required this.reports,
    required this.onMarkSeen,
  });

  final List<TrainingDailyReport> reports;
  final void Function(TrainingDailyReport) onMarkSeen;

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
              ? () => _showAttachmentPreview(context, r.attachmentUrl!)
              : null,
          onMarkSeen: () => onMarkSeen(r),
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
  });

  final TrainingDailyReport report;
  final VoidCallback? onViewFile;
  final VoidCallback onMarkSeen;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 6,
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
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryNavy,
                  AppTheme.primaryNavyLight,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.title,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusChip(status: r.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.description ?? 'No description provided.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Submitted ${r.submittedAt.toLocal()}',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Training daily report',
                  previewBuilder: () =>
                      TrainingDailyReportReadOnlyView(report: r),
                  contentWidth: 560,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('View form'),
              ),
              if (onViewFile != null) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onViewFile,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: const Text('Attachment'),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: onMarkSeen,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: const Text('Mark as seen'),
              ),
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

