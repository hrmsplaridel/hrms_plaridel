import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../landingpage/constants/app_theme.dart';
import '../data/training_daily_report.dart';

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
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Monitor daily reports from employees under training',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Search by employee name or report title, preview attachments, and mark reports as seen.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search',
                            hintText: 'Employee name or report title',
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _reports.isEmpty
                            ? Center(
                                child: Text(
                                  'No training daily reports found.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : _ReportsTable(
                                reports: _reports,
                                isWide: isWide,
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

class _ReportsTable extends StatelessWidget {
  const _ReportsTable({
    required this.reports,
    required this.isWide,
    required this.onMarkSeen,
  });

  final List<TrainingDailyReport> reports;
  final bool isWide;
  final void Function(TrainingDailyReport) onMarkSeen;

  @override
  Widget build(BuildContext context) {
    Future<void> showAttachmentPreview(String url) async {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 900,
                maxHeight: 700,
              ),
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

    if (!isWide) {
      return ListView.builder(
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final r = reports[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
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
                      const SizedBox(width: 8),
                      _StatusChip(status: r.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (r.description != null && r.description!.trim().isNotEmpty)
                    Text(
                      r.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    )
                  else
                    Text(
                      'No description provided.',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.8),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Submitted ${r.submittedAt.toLocal()}',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (r.attachmentUrl != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.attachment_rounded,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            r.attachmentName ?? 'Attachment uploaded',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (r.attachmentUrl != null)
                        TextButton.icon(
                          onPressed: () {
                            final url = r.attachmentUrl;
                            if (url == null) return;
                            showAttachmentPreview(url);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('View file'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => onMarkSeen(r),
                        child: const Text('Mark as seen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Wide: table layout.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowHeight: 56,
        columns: const [
          DataColumn(label: Text('Employee')),
          DataColumn(label: Text('Report title')),
          DataColumn(label: Text('Description')),
          DataColumn(label: Text('Submitted at')),
          DataColumn(label: Text('Attachment')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: reports.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(r.employeeName ?? 'Unknown')),
              DataCell(Text(r.title)),
              DataCell(
                Text(
                  r.description ?? 'No description',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DataCell(
                Text(
                  r.submittedAt.toLocal().toString(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              DataCell(
                r.attachmentUrl != null
                    ? TextButton.icon(
                        onPressed: () async {
                          final url = r.attachmentUrl;
                          if (url == null) return;
                          await showAttachmentPreview(url);
                        },
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View file'),
                      )
                    : const Text(
                        'None',
                        style: TextStyle(fontSize: 12),
                      ),
              ),
              DataCell(_StatusChip(status: r.status)),
              DataCell(
                TextButton(
                  onPressed: () => onMarkSeen(r),
                  child: const Text('Mark as seen'),
                ),
              ),
            ],
          );
        }).toList(),
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
        color = Colors.blueGrey;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

