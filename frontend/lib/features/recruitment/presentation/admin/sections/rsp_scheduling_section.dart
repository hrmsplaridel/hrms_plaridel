import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_final_interview_scheduler.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_orientation_scheduler.dart';

/// RSP Scheduling: deliberation (after exam) and orientation (after final requirements).
class RspSchedulingSection extends StatefulWidget {
  const RspSchedulingSection({super.key});

  @override
  State<RspSchedulingSection> createState() => _RspSchedulingSectionState();
}

class _RspSchedulingSectionState extends State<RspSchedulingSection> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final accentNavy = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.calendar_month_outlined,
                size: 26,
                color: accentNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scheduling',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage two scheduling stages: deliberation for applicants who passed '
                    'the screening exam, and orientation after they comply with final requirements.',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('Deliberation'),
              icon: Icon(Icons.groups_rounded, size: 18),
            ),
            ButtonSegment(
              value: 1,
              label: Text('Orientation'),
              icon: Icon(Icons.school_rounded, size: 18),
            ),
          ],
          selected: {_tabIndex},
          onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tabIndex == 0
              ? 'Schedule deliberation and record pass/fail for screening-exam passers.'
              : 'Schedule orientation for applicants with approved final requirements.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.dashTextSecondaryOf(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        if (_tabIndex == 0)
          const RspFinalInterviewScheduler(embedded: true)
        else
          const RspOrientationScheduler(embedded: true),
      ],
    );
  }
}
