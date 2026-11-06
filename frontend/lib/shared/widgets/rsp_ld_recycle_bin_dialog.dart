import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/data/repositories/rsp_ld_saved_entries_api.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';

/// One saved form row shown in the recycle bin.
class RspLdRecycleBinItem {
  const RspLdRecycleBinItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.previewBuilder,
    this.previewWidth = 960,
  });

  final String id;
  final String title;
  final String subtitle;
  final Widget Function()? previewBuilder;
  final double previewWidth;
}

/// Date portion of `deleted_at` from a recycled form row.
String rspLdRecycleRemovedOn(Map<String, dynamic> row) {
  final raw = row['deleted_at']?.toString() ?? '';
  if (raw.length >= 10) return raw.substring(0, 10);
  return '—';
}

/// Recycle bin for RSP and L&D saved forms. View, restore, or delete permanently.
Future<void> showRspLdRecycleBin({
  required BuildContext context,
  required String table,
  required RspLdRecycleBinItem? Function(Map<String, dynamic> row) mapRow,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _RspLdRecycleBinDialog(
      table: table,
      mapRow: mapRow,
      onChanged: onChanged,
    ),
  );
}

class RspLdRecycleBinButton extends StatelessWidget {
  const RspLdRecycleBinButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback? onPressed;

  /// Text button used inside [RspLdFormHeader]. Outlined button otherwise.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.restore_from_trash_outlined, size: 20),
        label: const Text('Recycle bin'),
        style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
      label: const Text('Recycle bin'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      ),
    );
  }
}

class _RspLdRecycleBinDialog extends StatefulWidget {
  const _RspLdRecycleBinDialog({
    required this.table,
    required this.mapRow,
    required this.onChanged,
  });

  final String table;
  final RspLdRecycleBinItem? Function(Map<String, dynamic> row) mapRow;
  final VoidCallback onChanged;

  @override
  State<_RspLdRecycleBinDialog> createState() => _RspLdRecycleBinDialogState();
}

class _RspLdRecycleBinDialogState extends State<_RspLdRecycleBinDialog> {
  bool _loading = true;
  String? _error;
  List<RspLdRecycleBinItem> _items = [];
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
      final rows = await RspLdSavedEntriesApi.listRecycledRows(widget.table);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final row in rows)
            if (widget.mapRow(row) case final item?) item,
        ];
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

  Future<void> _restore(RspLdRecycleBinItem item) async {
    setState(() => _busyId = item.id);
    try {
      await RspLdSavedEntriesApi.restoreRow(widget.table, item.id);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} restored.')),
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

  Future<void> _deleteForever(RspLdRecycleBinItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '${item.title} will be removed. This cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = item.id);
    try {
      await RspLdSavedEntriesApi.permanentlyDeleteRow(widget.table, item.id);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} deleted permanently.')),
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

  void _view(RspLdRecycleBinItem item) {
    final preview = item.previewBuilder;
    if (preview == null) return;
    showReadOnlySavedEntryDialog(
      context,
      title: item.title,
      subtitle: item.subtitle,
      previewBuilder: preview,
      contentWidth: item.previewWidth,
    );
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
                'The recycle bin is empty. Deleted form records will appear here.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open View to check the saved form before you restore or delete it.',
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
                        final item = _items[index];
                        final busy = _busyId == item.id;
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
                                item.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppTheme.dashTextPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.subtitle,
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
                                    if (item.previewBuilder != null)
                                      TextButton.icon(
                                        onPressed: _busyId == null
                                            ? () => _view(item)
                                            : null,
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('View'),
                                      ),
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _restore(item)
                                          : null,
                                      icon: const Icon(
                                        Icons.restore_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Restore'),
                                    ),
                                    TextButton.icon(
                                      onPressed: _busyId == null
                                          ? () => _deleteForever(item)
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
