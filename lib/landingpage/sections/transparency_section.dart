import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class TransparencySection extends StatelessWidget {
  const TransparencySection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    final items = [
      ('View Citizen\'s Charter', Icons.menu_book_outlined),
      ('Download HR Forms', Icons.download_outlined),
      ('View HR Policies', Icons.policy_outlined),
      ('View Announcements', Icons.campaign_outlined),
    ];

    return SectionContainer(
      backgroundColor: AppTheme.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Action button in upper right
          Positioned(
            top: 0,
            right: 0,
            child: TextButton.icon(
              onPressed: () => _handleViewAllDocuments(context),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('View All Documents'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          Column(
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
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: items
                          .map(
                            (i) => _TransparencyButton(
                              label: i.$1,
                              icon: i.$2,
                              onTap: () => _handleTap(context, i.$1),
                            ),
                          )
                          .toList(),
                    )
                  : Column(
                      children: items
                          .map(
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TransparencyButton(
                                label: i.$1,
                                icon: i.$2,
                                onTap: () => _handleTap(context, i.$1),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, String item) {
    // Ready for backend integration
  }

  void _handleViewAllDocuments(BuildContext context) {
    // Ready for backend integration
  }
}

class _TransparencyButton extends StatelessWidget {
  const _TransparencyButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
        hoverColor: AppTheme.primaryNavy.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.lightGray),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.primaryNavy, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: AppTheme.bodySize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
