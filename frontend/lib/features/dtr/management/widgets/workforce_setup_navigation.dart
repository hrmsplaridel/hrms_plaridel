import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';

class WorkforceSetupNavigation extends StatelessWidget {
  const WorkforceSetupNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final DtrPage selected;
  final ValueChanged<DtrPage> onSelected;

  static IconData _iconFor(DtrPage page) => switch (page) {
    DtrPage.assignments => Icons.assignment_rounded,
    DtrPage.departments => Icons.business_rounded,
    DtrPage.positions => Icons.work_rounded,
    DtrPage.shifts => Icons.access_time_rounded,
    DtrPage.weeklySchedule => Icons.calendar_view_week_rounded,
    DtrPage.holidays => Icons.calendar_today_rounded,
    DtrPage.attendancePolicies => Icons.policy_rounded,
    _ => Icons.settings_rounded,
  };

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
            for (final page in DtrPage.workforcePages) _tab(context, page),
          ],
        ),
      ),
    ],
  );
  Widget _tab(BuildContext context, DtrPage page) {
    final selected = this.selected == page;
    final foreground = selected
        ? Colors.white
        : AppTheme.dashTextSecondaryOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppTheme.primaryNavy : Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(page),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 148, minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconFor(page), size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    page.title,
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
