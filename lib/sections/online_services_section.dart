import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class OnlineServicesSection extends StatelessWidget {
  const OnlineServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    final services = [
      ('Apply for Job', Icons.work_outline),
      ('Check Application Status', Icons.fact_check_outlined),
      ('View Training Schedule', Icons.calendar_month_outlined),
      ('Submit Training Request', Icons.request_quote_outlined),
      ('View Development Records', Icons.folder_open_outlined),
    ];

    return SectionContainer(
      backgroundColor: AppTheme.sectionAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Online Services',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = isWide ? 3 : (constraints.maxWidth > 500 ? 2 : 1);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: isWide ? 2.2 : 2.0,
                children: services
                    .map(
                      (s) => _ServiceCard(
                        title: s.$1,
                        icon: s.$2,
                        onTap: () => _handleServiceTap(context, s.$1),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handleServiceTap(BuildContext context, String service) {
    // Ready for backend integration
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: AppTheme.primaryNavy.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.lightGray),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, color: AppTheme.primaryNavy, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: AppTheme.bodySize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
