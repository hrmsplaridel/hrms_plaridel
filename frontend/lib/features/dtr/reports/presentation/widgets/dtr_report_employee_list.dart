import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

String _compactEmployeeNo(String employeeNo) {
  return employeeNo.replaceFirst(
    RegExp(r'^EMP[-\s]*', caseSensitive: false),
    '',
  );
}

/// Multi-select bar above the employee list (count, select all, clear, exit).
class DtrEmployeeSelectionToolbar extends StatelessWidget {
  const DtrEmployeeSelectionToolbar({
    super.key,
    required this.employees,
    required this.selectedEmployeeIds,
    required this.multiSelectMode,
    required this.bulkExportBusy,
    required this.bulkExportPrepared,
    required this.bulkExportTotal,
    required this.onSelectAll,
    required this.onClear,
    required this.onExit,
    this.compact = false,
  });

  final List<EmployeeOption> employees;
  final Set<String> selectedEmployeeIds;
  final bool multiSelectMode;
  final bool bulkExportBusy;
  final int bulkExportPrepared;
  final int bulkExportTotal;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onExit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selectedCount = selectedEmployeeIds.length;
    final allFilteredSelected =
        employees.isNotEmpty &&
        employees.every((e) => selectedEmployeeIds.contains(e.id));
    if (!multiSelectMode) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bulkExportBusy && bulkExportTotal > 0
                  ? '$bulkExportPrepared/$bulkExportTotal prepared'
                  : (selectedCount == 0 ? '' : '$selectedCount selected'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Select all filtered employees',
            onPressed: employees.isEmpty || allFilteredSelected
                ? null
                : onSelectAll,
            icon: const Icon(Icons.select_all_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          ),
          if (selectedCount > 0)
            IconButton(
              tooltip: 'Clear selected employees',
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
          IconButton(
            tooltip: 'Exit multi-select (Esc)',
            onPressed: onExit,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          ),
        ],
      ),
    );
  }
}

/// Employee picker for the DTR report. [compact] is the stacked layout used on
/// narrower screens; the default is the 260px side column.
class DtrReportEmployeeList extends StatelessWidget {
  const DtrReportEmployeeList({
    super.key,
    required this.loading,
    required this.employees,
    required this.selectedEmployeeId,
    required this.checkedEmployeeIds,
    required this.multiSelectMode,
    required this.toolbar,
    required this.onEmployeeTap,
    required this.onCheckedChanged,
    this.compact = false,
  });

  final bool loading;
  final List<EmployeeOption> employees;
  final String? selectedEmployeeId;
  final Set<String> checkedEmployeeIds;
  final bool multiSelectMode;
  final Widget toolbar;
  final ValueChanged<EmployeeOption> onEmployeeTap;
  final void Function(String employeeId, bool checked) onCheckedChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      if (compact) {
        return const WorkforceRowsSkeleton(
          columns: [1, 3],
          rows: 3,
          label: 'Loading employees',
        );
      }
      return const SizedBox(
        width: 260,
        child: SingleChildScrollView(
          child: WorkforceRowsSkeleton(
            columns: [1, 3],
            label: 'Loading employees',
          ),
        ),
      );
    }
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: compact ? null : 260,
      constraints: compact ? null : const BoxConstraints(maxWidth: 260),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          toolbar,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                if (multiSelectMode) const SizedBox(width: 32),
                SizedBox(
                  width: 60,
                  child: Text(
                    'EMP ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Employee Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: employees.length,
              itemBuilder: (ctx, i) {
                final e = employees[i];
                final isSelected = e.id == selectedEmployeeId;
                final isChecked = checkedEmployeeIds.contains(e.id);
                return InkWell(
                  onTap: () => onEmployeeTap(e),
                  child: Container(
                    color: isSelected
                        ? (dark
                              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                              : AppTheme.primaryNavy.withValues(alpha: 0.08))
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (multiSelectMode) ...[
                          SizedBox(
                            width: 28,
                            child: Checkbox(
                              value: isChecked,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (value) =>
                                  onCheckedChanged(e.id, value ?? false),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        SizedBox(
                          width: 60,
                          child: Tooltip(
                            message: e.displayEmployeeNo,
                            child: Text(
                              _compactEmployeeNo(e.displayEmployeeNo),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.dashTextPrimaryOf(ctx),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.isActive
                                ? e.fullName
                                : '${e.fullName} (${e.currentStatusLabel})',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.dashTextPrimaryOf(ctx),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
