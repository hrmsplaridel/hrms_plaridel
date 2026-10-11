import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class WorkforceSetupNavigation extends StatelessWidget {
  const WorkforceSetupNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const sections = [4, 5, 6, 7, 13, 9, 10];
  static const _labels = [
    'Assignments',
    'Departments',
    'Positions',
    'Shifts',
    'Weekly Schedule',
    'Holidays',
    'Attendance Policies',
  ];
  static const _icons = [
    Icons.assignment_rounded,
    Icons.business_rounded,
    Icons.work_rounded,
    Icons.access_time_rounded,
    Icons.calendar_view_week_rounded,
    Icons.calendar_today_rounded,
    Icons.policy_rounded,
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Workforce Setup',
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: AppTheme.dashPanelOf(context),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Wrap(
          children: [
            for (var i = 0; i < sections.length; i++) _tab(context, i),
          ],
        ),
      ),
    ],
  );
  Widget _tab(BuildContext context, int i) {
    final selected = selectedIndex == sections[i];
    final foreground = selected
        ? Colors.white
        : AppTheme.dashTextSecondaryOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppTheme.primaryNavy : Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(sections[i]),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 148, minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_icons[i], size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
