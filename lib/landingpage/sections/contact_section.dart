import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

const _googleMapsUrl =
    'https://www.google.com/maps/search/?api=1&query=JPC5%2BGXV%2C+Dipolog+-+Oroquieta+National+Rd%2C+Plaridel%2C+Misamis+Occidental';

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.offWhite,
      borderRadius: 20,
      withShadow: true,
      margin: const EdgeInsets.symmetric(vertical: 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Contact Us',
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
                  color: AppTheme.primaryNavy.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Get in touch with the Human Resource Management and Development Office',
                textAlign: TextAlign.center,
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
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              _ContactItem(
                                icon: Icons.location_on_outlined,
                                label: 'Office Address',
                                value:
                                    'Municipal Hall of Plaridel, Misamis Occidental',
                              ),
                              SizedBox(height: 24),
                              _ContactItem(
                                icon: Icons.phone_outlined,
                                label: 'Contact Number',
                                value: '(088) 3448-200',
                              ),
                              SizedBox(height: 24),
                              _ContactItem(
                                icon: Icons.email_outlined,
                                label: 'Official Email',
                                value:
                                    'plaridel_misocc@yahoo.com / asensoplaridel@gmail.com',
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
                        Expanded(flex: 1, child: _OfficeMap()),
                      ],
                    )
                  : Column(
                      children: [
                        const _ContactItem(
                          icon: Icons.location_on_outlined,
                          label: 'Office Address',
                          value:
                              'JPC5+GXV, Dipolog - Oroquieta National Rd, Plaridel, Misamis Occidental',
                        ),
                        const SizedBox(height: 20),
                        const _ContactItem(
                          icon: Icons.phone_outlined,
                          label: 'Contact Number',
                          value: '(088) 3448-200',
                        ),
                        const SizedBox(height: 20),
                        const _ContactItem(
                          icon: Icons.email_outlined,
                          label: 'Official Email',
                          value: 'plaridel_misocc@yahoo.com',
                        ),
                        const SizedBox(height: 20),
                        const _ContactItem(
                          icon: Icons.access_time_outlined,
                          label: 'Office Hours',
                          value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                        ),
                        const SizedBox(height: 24),
                        const _OfficeMap(),
                      ],
                    ),
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
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryNavy, size: 22),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: AppTheme.bodySize,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Location card with static preview and link to open in Google Maps.
class _OfficeMap extends StatelessWidget {
  const _OfficeMap();

  static const _mapHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAED)),
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: _mapHeight,
            child: ColoredBox(
              color: AppTheme.offWhite,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 56,
                      color: AppTheme.primaryNavy.withOpacity(0.6),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Municipal Hall of Plaridel\nMisamis Occidental',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: AppTheme.smallSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Material(
            color: AppTheme.white,
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse(_googleMapsUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: AppTheme.primaryNavy,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Open in Google Maps',
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: AppTheme.smallSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
