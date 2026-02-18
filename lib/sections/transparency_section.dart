import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class TransparencySection extends StatelessWidget {
  const TransparencySection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    final items = [
      (
        'Citizen\'s Charter',
        Icons.menu_book_outlined,
        'View our commitment to public service standards',
      ),
      (
        'Hiring Announcements',
        Icons.campaign_outlined,
        'Latest job openings and hiring updates',
      ),
      (
        'HR Policies & Guidelines',
        Icons.policy_outlined,
        'Official human resource policies and issuances',
      ),
      (
        'Downloadable Forms',
        Icons.download_outlined,
        'Access and download official HR forms',
      ),
    ];

    return SectionContainer(
      backgroundColor: AppTheme.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Transparency',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Promoting openness and accountability in public service',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: AppTheme.bodySize,
            ),
          ),
          const SizedBox(height: 32),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map(
                        (i) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: _TransparencyCard(
                              title: i.$1,
                              icon: i.$2,
                              description: i.$3,
                              onTap: () => _handleTap(context, i.$1),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                )
              : Column(
                  children: items
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _TransparencyCard(
                            title: i.$1,
                            icon: i.$2,
                            description: i.$3,
                            onTap: () => _handleTap(context, i.$1),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, String item) {
    // Ready for backend integration
  }
}

class _TransparencyCard extends StatelessWidget {
  const _TransparencyCard({
    required this.title,
    required this.icon,
    required this.description,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(4),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: AppTheme.primaryNavy.withOpacity(0.04),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.lightGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primaryNavy, size: 40),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: AppTheme.cardTitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: AppTheme.smallSize,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
