import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import '../../data/dtr_report_period.dart';

/// Filter controls only. The report page owns selection, loading and export state.
class DtrReportFilters extends StatelessWidget {
  const DtrReportFilters({
    super.key,
    required this.isMobile,
    required this.selfService,
    required this.searchController,
    required this.departments,
    required this.selectedDepartmentId,
    required this.selectedEmployeeStatus,
    required this.selectedMonth,
    required this.selectedYear,
    required this.availableReportYears,
    required this.rangeStartDay,
    required this.rangeEndDay,
    required this.selectedCount,
    required this.bulkExportBusy,
    required this.bulkExportPrepared,
    required this.bulkExportTotal,
    required this.officialActionsEnabled,
    required this.hasUnverifiedBulkAttendance,
    required this.onSearchChanged,
    required this.onDepartmentChanged,
    required this.onEmployeeStatusChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onRangeStartChanged,
    required this.onRangeEndChanged,
    required this.onReset,
    required this.onBulkPrint,
    required this.onBulkExport,
    this.onHabitualAttendance,
  });
  final bool isMobile,
      selfService,
      bulkExportBusy,
      officialActionsEnabled,
      hasUnverifiedBulkAttendance;
  final TextEditingController searchController;
  final List<DepartmentOption> departments;
  final String? selectedDepartmentId;
  final String selectedEmployeeStatus;
  final int selectedMonth,
      selectedYear,
      rangeStartDay,
      rangeEndDay,
      selectedCount,
      bulkExportPrepared,
      bulkExportTotal;
  final List<int> availableReportYears;
  final ValueChanged<String> onSearchChanged, onEmployeeStatusChanged;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<int> onMonthChanged,
      onYearChanged,
      onRangeStartChanged,
      onRangeEndChanged;
  final VoidCallback onReset, onBulkPrint, onBulkExport;
  final VoidCallback? onHabitualAttendance;
  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final dayItems = List.generate(
      DateTime(selectedYear, selectedMonth + 1, 0).day,
      (i) => i + 1,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!selfService)
          SizedBox(
            width: isMobile ? double.infinity : 280,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: AppTheme.dashFieldTextStyle(context),
              decoration: AppTheme.dashInputDecoration(
                context,
                hintText: 'Search name or ID...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                radius: 8,
              ),
            ),
          ),
        if (!isMobile) ...[
          if (!selfService)
            DropdownButton<String?>(
              value: selectedDepartmentId,
              dropdownColor: AppTheme.dashPanelOf(context),
              style: AppTheme.dashFieldTextStyle(context),
              hint: Text(
                'All departments',
                style: AppTheme.dashFieldHintStyle(context),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'All departments',
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
                ...departments.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(
                      d.name,
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                ),
              ],
              onChanged: onDepartmentChanged,
            ),
          if (!selfService)
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                key: ValueKey('employee-status-$selectedEmployeeStatus'),
                initialValue: selectedEmployeeStatus,
                dropdownColor: AppTheme.dashPanelOf(context),
                style: AppTheme.dashFieldTextStyle(context),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Current employee status',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  radius: 8,
                ),
                items: const ['Active', 'Inactive', 'All']
                    .map(
                      (status) => DropdownMenuItem<String>(
                        value: status,
                        child: Text(status),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == selectedEmployeeStatus) {
                    return;
                  }
                  onEmployeeStatusChanged(value);
                },
              ),
            ),
          DropdownButton<int>(
            value: selectedMonth,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: List.generate(12, (i) => i + 1)
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      dtrReportMonths[m - 1],
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onMonthChanged(v);
            },
          ),
          DropdownButton<int>(
            value: selectedYear,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: availableReportYears
                .map(
                  (y) => DropdownMenuItem(
                    value: y,
                    child: Text(
                      '$y',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onYearChanged(v);
            },
          ),
          DropdownButton<int>(
            value: rangeStartDay,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: dayItems
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      'From day $d',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              onRangeStartChanged(v);
            },
          ),
          DropdownButton<int>(
            value: rangeEndDay,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: dayItems
                .where((d) => d >= rangeStartDay)
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      'To day $d',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onRangeEndChanged(v);
            },
          ),
        ] else ...[
          if (!selfService) ...[
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: selectedDepartmentId,
                dropdownColor: AppTheme.dashPanelOf(context),
                style: AppTheme.dashFieldTextStyle(context),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  radius: 8,
                ),
                hint: Text(
                  'All departments',
                  style: AppTheme.dashFieldHintStyle(context),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'All departments',
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                  ...departments.map(
                    (d) => DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(
                        d.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.dashFieldTextStyle(context),
                      ),
                    ),
                  ),
                ],
                onChanged: onDepartmentChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                key: ValueKey('employee-status-$selectedEmployeeStatus'),
                initialValue: selectedEmployeeStatus,
                dropdownColor: AppTheme.dashPanelOf(context),
                style: AppTheme.dashFieldTextStyle(context),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Current employee status',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  radius: 8,
                ),
                items: const ['Active', 'Inactive', 'All']
                    .map(
                      (status) => DropdownMenuItem<String>(
                        value: status,
                        child: Text(status),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == selectedEmployeeStatus) {
                    return;
                  }
                  onEmployeeStatusChanged(value);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: selectedMonth,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: List.generate(12, (i) => i + 1)
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            dtrReportMonths[m - 1],
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onMonthChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: selectedYear,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: availableReportYears
                      .map(
                        (y) => DropdownMenuItem(
                          value: y,
                          child: Text(
                            '$y',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onYearChanged(v);
                  },
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: rangeStartDay,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: dayItems
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            'From $d',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    onRangeStartChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: rangeEndDay,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    radius: 8,
                  ),
                  items: dayItems
                      .where((d) => d >= rangeStartDay)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            'To $d',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onRangeEndChanged(v);
                  },
                ),
              ),
            ],
          ),
        ],
        if (onHabitualAttendance != null)
          OutlinedButton.icon(
            onPressed: onHabitualAttendance,
            icon: const Icon(Icons.warning_amber_rounded, size: 18),
            label: const Text('Habitual tardiness'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: BorderSide(
                color: AppTheme.primaryNavy.withValues(alpha: 0.5),
              ),
            ),
          ),
        OutlinedButton(
          onPressed: onReset,
          style: OutlinedButton.styleFrom(
            backgroundColor: dark
                ? Colors.green.shade900.withValues(alpha: 0.4)
                : const Color(0xFFE8F5E9),
            foregroundColor: dark
                ? Colors.green.shade300
                : const Color(0xFF2E7D32),
            side: BorderSide(
              color: dark ? Colors.green.shade700 : const Color(0xFF81C784),
            ),
          ),
          child: const Text('RESET'),
        ),
        if (selectedCount > 1) ...[
          Text(
            bulkExportBusy && bulkExportTotal > 0
                ? '$bulkExportPrepared/$bulkExportTotal prepared'
                : '$selectedCount selected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          FilledButton.icon(
            onPressed:
                bulkExportBusy ||
                    !officialActionsEnabled ||
                    hasUnverifiedBulkAttendance
                ? null
                : onBulkPrint,
            icon: bulkExportBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded, size: 18),
            label: Text(bulkExportBusy ? 'Preparing' : 'Bulk print'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.white,
              disabledBackgroundColor: AppTheme.dashMutedSurfaceOf(context),
              disabledForegroundColor: AppTheme.dashTextSecondaryOf(
                context,
              ).withValues(alpha: 0.7),
            ),
          ),
          OutlinedButton.icon(
            onPressed:
                bulkExportBusy ||
                    !officialActionsEnabled ||
                    hasUnverifiedBulkAttendance
                ? null
                : onBulkExport,
            icon: const Icon(Icons.file_download_rounded, size: 18),
            label: const Text('Export selected'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryNavy,
              side: BorderSide(
                color: AppTheme.primaryNavy.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
