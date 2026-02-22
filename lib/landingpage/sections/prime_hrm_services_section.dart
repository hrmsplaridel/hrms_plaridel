import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Prime HRM Services: 4 cards with icon and short description.
class PrimeHrmServicesSection extends StatelessWidget {
  const PrimeHrmServicesSection({super.key});

  static const _services = [
    (
      'Recruitment, Selection & Placement',
      Icons.person_search_outlined,
      'Merit-based hiring and placement in accordance with CSC rules and standards.',
    ),
    (
      'Learning & Development',
      Icons.school_outlined,
      'Training programs and capacity building for a competent workforce.',
    ),
    (
      'Performance Management',
      Icons.assessment_outlined,
      'Objective performance evaluation and feedback aligned with organizational goals.',
    ),
    (
      'Rewards & Recognition',
      Icons.emoji_events_outlined,
      'Recognition and incentives for exemplary service and achievements.',
    ),
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
            'Prime HRM Services',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Core HR services aligned with the Civil Service Commission Prime HRM roadmap.',
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
                    for (int i = 0; i < _services.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i < _services.length - 1 ? 20 : 0),
                          child: _ServiceCard(
                            title: _services[i].$1,
                            icon: _services[i].$2,
                            description: _services[i].$3,
                          ),
                        ),
                      ),
                  ],
                )
              : Column(
                  children: [
                    for (int i = 0; i < _services.length; i++) ...[
                      _ServiceCard(
                        title: _services[i].$1,
                        icon: _services[i].$2,
                        description: _services[i].$3,
                      ),
                      if (i < _services.length - 1) const SizedBox(height: 16),
                    ],
                  ],
                ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatefulWidget {
  const _ServiceCard({
    required this.title,
    required this.icon,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hover ? AppTheme.offWhite : AppTheme.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hover ? AppTheme.primaryNavy.withOpacity(0.2) : AppTheme.lightGray,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, color: AppTheme.primaryNavy, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: AppTheme.cardTitleSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.description,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: AppTheme.smallSize,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
