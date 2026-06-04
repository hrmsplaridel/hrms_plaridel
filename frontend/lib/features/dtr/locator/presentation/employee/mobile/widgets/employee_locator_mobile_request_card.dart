import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class EmployeeLocatorMobileRequestCard extends StatelessWidget {
  const EmployeeLocatorMobileRequestCard({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.office,
    required this.remarks,
    required this.segmentsText,
    required this.typeLabel,
    required this.statusPill,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String dateLabel;
  final String office;
  final String remarks;
  final String segmentsText;
  final String typeLabel;
  final Widget statusPill;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final selectedColor = dark
        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
        : AppTheme.primaryNavy.withValues(alpha: 0.08);
    final borderColor = isSelected
        ? AppTheme.primaryNavy.withValues(alpha: dark ? 0.75 : 0.4)
        : AppTheme.dashHairlineOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  statusPill,
                ],
              ),
              const SizedBox(height: 12),
              Text(
                office.trim().isEmpty ? 'Location not set' : office,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (remarks.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  remarks.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LocatorMobileMetaChip(
                    icon: Icons.schedule_rounded,
                    label: segmentsText,
                  ),
                  _LocatorMobileMetaChip(
                    icon: Icons.category_outlined,
                    label: typeLabel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocatorMobileMetaChip extends StatelessWidget {
  const _LocatorMobileMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.dashTextSecondaryOf(context)),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
