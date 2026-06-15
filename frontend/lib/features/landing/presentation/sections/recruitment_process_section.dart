import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

/// Step-by-step recruitment process. Registration only after passing exam.
class RecruitmentProcessSection extends StatelessWidget {
  const RecruitmentProcessSection({super.key, this.onStartApplicationTap});

  final VoidCallback? onStartApplicationTap;

  static const _steps = [
    ('Submit Basic Information', Icons.description),
    ('Document Review', Icons.folder_open_outlined),
    ('Screening Exams', Icons.quiz_outlined),
    ('Deliberation', Icons.record_voice_over_outlined),
    ('Final Requirements', Icons.health_and_safety_outlined),
    ('Orientation & Account', Icons.badge_outlined),
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
              fontSize: AppTheme.sectionTitleSize + 2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Applicants must take the screening exam before registration. Complete the steps below to apply.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: AppTheme.bodySize,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
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
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.6,
                            ),
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
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.6,
                            ),
                            size: 24,
                          ),
                        ),
                    ],
                  ],
                ),
          const SizedBox(height: 44),
          Center(
            child: FilledButton.icon(
              onPressed: onStartApplicationTap,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text('Start Application'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 18,
                ),
                minimumSize: const Size(0, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
                shadowColor: AppTheme.primaryNavy.withValues(alpha: 0.35),
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
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _hover ? AppTheme.offWhite : AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover
                ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                : const Color(0xFFE8EAED),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.09 : 0.055),
              blurRadius: _hover ? 20 : 14,
              offset: Offset(0, _hover ? 7 : 4),
            ),
            BoxShadow(
              color: AppTheme.primaryNavy.withValues(
                alpha: _hover ? 0.08 : 0.05,
              ),
              blurRadius: _hover ? 14 : 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.stepNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(widget.icon, color: AppTheme.primaryNavy, size: 26),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.smallSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
