import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Shield icon above title
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryNavy.withOpacity(0.3),
                    width: 2,
                  ),
                  color: AppTheme.primaryNavy.withOpacity(0.08),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppTheme.primaryNavy,
                  size: 24,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'About the HRMO',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: AppTheme.sectionTitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'The Human Resource Management Office ensures efficient and merit-based recruitment of personnel and provides continuous learning opportunities to develop a competent, ethical, and service-oriented workforce in accordance with Civil Service Commission standards.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: isWide ? 18 : 16,
                  height: 1.7,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
