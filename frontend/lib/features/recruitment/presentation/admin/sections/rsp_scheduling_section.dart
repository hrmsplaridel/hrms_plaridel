import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_final_interview_scheduler.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_orientation_scheduler.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_scheduling_ui.dart';

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
    final accent = RspSchedulingUi.accentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: AppTheme.dashSurfaceCard(context, radius: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 24,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scheduling',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage applicant deliberation and orientation schedules.',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RspSchedulingUi.segmentedTabs<int>(
          context: context,
          segments: const [
            (value: 0, label: 'Deliberation', icon: Icons.groups_rounded),
            (value: 1, label: 'Orientation', icon: Icons.school_rounded),
          ],
          selected: _tabIndex,
          onChanged: (v) => setState(() => _tabIndex = v),
        ),
        const SizedBox(height: 18),
        if (_tabIndex == 0)
          const RspFinalInterviewScheduler(embedded: true)
        else
          const RspOrientationScheduler(embedded: true),
      ],
    );
  }
}
