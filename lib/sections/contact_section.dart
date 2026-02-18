import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.offWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Contact Us',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: AppTheme.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Get in touch with the Human Resource Management Office',
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
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _ContactItem(
                            icon: Icons.location_on_outlined,
                            label: 'Office Address',
                            value: 'Municipal Hall, Plaridel, Misamis Occidental, Philippines',
                          ),
                          SizedBox(height: 24),
                          _ContactItem(
                            icon: Icons.phone_outlined,
                            label: 'Contact Number',
                            value: '(088) 123-4567',
                          ),
                          SizedBox(height: 24),
                          _ContactItem(
                            icon: Icons.email_outlined,
                            label: 'Official Email',
                            value: 'hrmo@plaridel.gov.ph',
                          ),
                          SizedBox(height: 24),
                          _ContactItem(
                            icon: Icons.access_time_outlined,
                            label: 'Office Hours',
                            value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 1,
                      child: _MapPlaceholder(),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const _ContactItem(
                      icon: Icons.location_on_outlined,
                      label: 'Office Address',
                      value: 'Municipal Hall, Plaridel, Misamis Occidental, Philippines',
                    ),
                    const SizedBox(height: 20),
                    const _ContactItem(
                      icon: Icons.phone_outlined,
                      label: 'Contact Number',
                      value: '(088) 123-4567',
                    ),
                    const SizedBox(height: 20),
                    const _ContactItem(
                      icon: Icons.email_outlined,
                      label: 'Official Email',
                      value: 'hrmo@plaridel.gov.ph',
                    ),
                    const SizedBox(height: 20),
                    const _ContactItem(
                      icon: Icons.access_time_outlined,
                      label: 'Office Hours',
                      value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                    ),
                    const SizedBox(height: 24),
                    _MapPlaceholder(),
                  ],
                ),
        ],
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: AppTheme.primaryNavy,
          size: 24,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: AppTheme.smallSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: AppTheme.bodySize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 48,
            color: AppTheme.textSecondary.withOpacity(0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'Map Placeholder',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: AppTheme.bodySize,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Plaridel, Misamis Occidental',
            style: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.8),
              fontSize: AppTheme.smallSize,
            ),
          ),
        ],
      ),
    );
  }
}
