import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

/// Exact location: JPC5+GXV, Dipolog - Oroquieta National Rd, Plaridel, Misamis Occidental
const _officeLocation = LatLng(8.6214, 123.7102);
const _googleMapsUrl =
    'https://www.google.com/maps/search/?api=1&query=JPC5%2BGXV%2C+Dipolog+-+Oroquieta+National+Rd%2C+Plaridel%2C+Misamis+Occidental';

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.offWhite,
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
                  fontSize: AppTheme.sectionTitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Get in touch with the Human Resource Management and Development Office',
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
        Icon(icon, color: AppTheme.primaryNavy, size: 24),
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

/// OpenStreetMap showing HRMD Office (no API key required).
/// Tap "Open in Google Maps" to view in Google Maps.
class _OfficeMap extends StatelessWidget {
  const _OfficeMap();

  static const _mapHeight = 240.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: _mapHeight,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _officeLocation,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.scrollWheelZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'hrms_plaridel',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _officeLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: AppTheme.primaryNavy,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
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
                  vertical: 10,
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
