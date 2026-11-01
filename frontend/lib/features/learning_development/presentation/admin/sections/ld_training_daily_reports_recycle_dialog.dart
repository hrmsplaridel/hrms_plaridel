import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/training_daily_report_read_only_view.dart';

Future<void> showTrainingDailyReportsRecycleBin({
  required BuildContext context,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _TrainingDailyReportsRecycleDialog(onChanged: onChanged),
  );
}

class _TrainingDailyReportsRecycleDialog extends StatefulWidget {
  const _TrainingDailyReportsRecycleDialog({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_TrainingDailyReportsRecycleDialog> createState() =>
      _TrainingDailyReportsRecycleDialogState();
}

class _TrainingDailyReportsRecycleDialogState
    extends State<_TrainingDailyReportsRecycleDialog> {
  bool _loading = true;
  String? _error;
  List<TrainingDailyReport> _items = [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _busyId = null;
    });
    try {
      final items = await TrainingDailyReportRepo.instance.listRecycledReports();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingApiError(e);
      });
    }
  }

  String _removedOn(TrainingDailyReport report) {
    final when = report.deletedAt?.toLocal();
    if (when == null) return '—';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }

  void _view(TrainingDailyReport report) {
    showReadOnlySavedEntryDialog(
      context,
      title: 'Training daily report',
      subtitle: report.title.trim().isEmpty ? 'Untitled report' : report.title,
      previewBuilder: () => TrainingDailyReportReadOnlyView(report: report),
      contentWidth: 640,
    );
  }

  Future<void> _restore(TrainingDailyReport report) async {
    setState(() => _busyId = report.id);
    try {
      await TrainingDailyReportRepo.instance.restoreReport(report.id);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${report.title} restored.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
      setState(() => _busyId = null);
    }
  }

  Future<void> _deleteForever(TrainingDailyReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '${report.title} and its attachment will be removed. This cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = report.id);
    try {
      await TrainingDailyReportRepo.instance.permanentlyDeleteReport(report.id);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${report.title} deleted permanently.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
      setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recycle bin'),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading recycle bin…'),
                  ],
                ),
              )
            : _error != null
            ? Text(_error!)
            : _items.isEmpty
            ? const Text(
                'The recycle bin is empty. Deleted training reports will appear here.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open View to check the report and its file before you restore or delete it.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final report = _items[index];
                        final busy = _busyId == report.id;
                        final who = (report.employeeName ?? '').trim().isEmpty
                            ? 'Unknown employee'
                            : report.employeeName!.trim();
                        return Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          decoration: BoxDecoration(
                            color: AppTheme.dashPanelOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.dashHairlineOf(context),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.title.trim().isEmpty
                                    ? 'Untitled report'
                                    : report.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppTheme.dashTextPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$who · Removed ${_removedOn(report)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppTheme.dashTextSecondaryOf(context),
                                ),
                              ),
                              if (busy)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _view(report)
                                          : null,
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('View'),
                                    ),
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _restore(report)
                                          : null,
                                      icon: const Icon(
                                        Icons.restore_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Restore'),
                                    ),
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _deleteForever(report)
                                          : null,
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Delete permanently'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFFC62828),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
