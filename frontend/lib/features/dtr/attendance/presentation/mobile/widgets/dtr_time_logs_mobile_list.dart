import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/attendance_source_badge.dart';

class DtrTimeLogsMobileList extends StatelessWidget {
  const DtrTimeLogsMobileList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class DtrTimeLogMobileCard extends StatelessWidget {
  const DtrTimeLogMobileCard({
    super.key,
    required this.employeeName,
    required this.dateLabel,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.late,
    required this.undertime,
    required this.remarkChip,
    required this.source,
    required this.showActions,
    required this.onEdit,
    required this.onDelete,
  });

  final String employeeName;
  final String dateLabel;
  final String amIn;
  final String amOut;
  final String pmIn;
  final String pmOut;
  final String late;
  final String undertime;
  final Widget remarkChip;
  final String? source;
  final bool showActions;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              remarkChip,
              if (showActions) ...[
                const SizedBox(width: 4),
                _DtrTimeLogMobileActions(onEdit: onEdit, onDelete: onDelete),
              ],
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _DtrTimeLogTimeTile(label: 'AM In', value: amIn),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DtrTimeLogTimeTile(label: 'AM Out', value: amOut),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DtrTimeLogTimeTile(label: 'PM In', value: pmIn),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _DtrTimeLogTimeTile(label: 'PM Out', value: pmOut),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DtrTimeLogMetaChip(label: 'Late', value: late),
              _DtrTimeLogMetaChip(label: 'Undertime', value: undertime),
              AttendanceSourceBadge(source: source, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _DtrTimeLogMobileActions extends StatelessWidget {
  const _DtrTimeLogMobileActions({
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 22,
        color: AppTheme.dashTextSecondaryOf(context),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Actions',
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit_rounded,
                size: 20,
                color: AppTheme.dashTextPrimaryOf(ctx),
              ),
              const SizedBox(width: 12),
              Text(
                'Edit',
                style: TextStyle(color: AppTheme.dashTextPrimaryOf(ctx)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 20, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red.shade700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DtrTimeLogTimeTile extends StatelessWidget {
  const _DtrTimeLogTimeTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != '—';
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasValue
                  ? AppTheme.dashTextPrimaryOf(context)
                  : AppTheme.dashTextSecondaryOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DtrTimeLogMetaChip extends StatelessWidget {
  const _DtrTimeLogMetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
