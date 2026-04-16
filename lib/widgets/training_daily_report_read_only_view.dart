import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/training_daily_report.dart';
import '../landingpage/constants/app_theme.dart';
import 'rsp_form_header_footer.dart';

/// Same layout as the employee submit form, read-only (for View / saved records).
class TrainingDailyReportReadOnlyView extends StatelessWidget {
  const TrainingDailyReportReadOnlyView({super.key, required this.report});

  final TrainingDailyReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final hasFile = r.attachmentName != null && r.attachmentName!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daily Training Report',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Submitted record (read-only)',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RspSpacedOutlineField(
                  child: TextFormField(
                    initialValue: r.employeeName ?? '—',
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Employee',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: AppTheme.offWhite,
                    ),
                  ),
                ),
                RspSpacedOutlineField(
                  child: TextFormField(
                    initialValue: r.title,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Report title',
                      prefixIcon: const Icon(Icons.article_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                RspSpacedOutlineField(
                  child: TextFormField(
                    initialValue: r.description ?? '',
                    readOnly: true,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText:
                          (r.description == null || r.description!.trim().isEmpty)
                              ? 'No description provided.'
                              : null,
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: rspFormFieldVerticalGap),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.1),
                    ),
                    color: Colors.grey.shade50,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        color: AppTheme.textSecondary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasFile
                              ? r.attachmentName!
                              : 'No attachment uploaded',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (r.attachmentUrl != null && hasFile)
                        TextButton(
                          onPressed: () async {
                            final uri = Uri.tryParse(r.attachmentUrl!);
                            if (uri != null &&
                                await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          child: const Text('Open'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaChip(
                      icon: Icons.flag_outlined,
                      label: 'Status',
                      value: r.status,
                    ),
                    _MetaChip(
                      icon: Icons.schedule_rounded,
                      label: 'Submitted',
                      value: r.submittedAt.toLocal().toString().split('.').first,
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryNavy),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                value.isEmpty ? '—' : value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
