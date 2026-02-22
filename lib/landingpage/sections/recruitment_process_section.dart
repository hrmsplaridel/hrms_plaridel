import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Step-by-step recruitment process. Registration only after passing exam.
class RecruitmentProcessSection extends StatelessWidget {
  const RecruitmentProcessSection({
    super.key,
    this.onStartApplicationTap,
  });

  final VoidCallback? onStartApplicationTap;

  static const _steps = [
    ('Submit Basic Information', Icons.description),
    ('Take Online Screening Exam', Icons.quiz_outlined),
    ('View Exam Result', Icons.assignment_outlined),
    ('Complete Registration (only if passed)', Icons.how_to_reg),
    ('Interview & Final Hiring', Icons.groups_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recruitment Process',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Applicants must take the screening exam before registration. Complete the steps below to apply.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: AppTheme.bodySize,
            ),
          ),
          const SizedBox(height: 32),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      Expanded(
                        child: _ProcessStep(
                          stepNumber: i + 1,
                          title: _steps[i].$1,
                          icon: _steps[i].$2,
                        ),
                      ),
                      if (i < _steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Icon(
                            Icons.arrow_forward,
                            color: AppTheme.textSecondary.withOpacity(0.6),
                            size: 20,
                          ),
                        ),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (int i = 0; i < _steps.length; i++) ...[
                      _ProcessStep(
                        stepNumber: i + 1,
                        title: _steps[i].$1,
                        icon: _steps[i].$2,
                      ),
                      if (i < _steps.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Icon(
                            Icons.arrow_downward,
                            color: AppTheme.textSecondary.withOpacity(0.6),
                            size: 24,
                          ),
                        ),
                    ],
                  ],
                ),
          const SizedBox(height: 40),
          Center(
            child: FilledButton.icon(
              onPressed: onStartApplicationTap,
              icon: const Icon(Icons.play_arrow, size: 22),
              label: const Text('Start Application'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size(0, 52),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessStep extends StatefulWidget {
  const _ProcessStep({
    required this.stepNumber,
    required this.title,
    required this.icon,
  });

  final int stepNumber;
  final String title;
  final IconData icon;

  @override
  State<_ProcessStep> createState() => _ProcessStepState();
}

class _ProcessStepState extends State<_ProcessStep> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _hover ? AppTheme.offWhite : AppTheme.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hover ? AppTheme.primaryNavy.withOpacity(0.3) : AppTheme.lightGray,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.stepNumber}',
                    style: const TextStyle(
                      color: AppTheme.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(widget.icon, color: AppTheme.primaryNavy, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.smallSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
