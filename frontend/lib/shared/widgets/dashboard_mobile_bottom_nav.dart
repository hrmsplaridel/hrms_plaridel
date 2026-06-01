import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// One destination in the mobile dashboard bottom bar.
class DashboardMobileNavItem {
  const DashboardMobileNavItem({
    required this.icon,
    required this.label,
    this.shortLabel,
  });

  final IconData icon;
  final String label;

  /// Compact label for narrow bottom bars; falls back to [label].
  final String? shortLabel;

  String displayLabel(bool compact) =>
      compact && shortLabel != null && shortLabel!.isNotEmpty
      ? shortLabel!
      : label;
}

/// Full-width bottom navigation for dashboards with several sections.
///
/// Distributes items evenly across the screen (no cramped fixed-width tiles).
class DashboardMobileBottomNav extends StatelessWidget {
  const DashboardMobileBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DashboardMobileNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Minimum content height (icon + label + padding), excluding safe area.
  static const double barHeight = 56;

  /// Extra scroll padding to reserve above the system home indicator.
  static double scrollPaddingExtra(BuildContext context) =>
      barHeight + MediaQuery.paddingOf(context).bottom + 6;

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compactLabels = width < 420 || items.length > 5;

    return Material(
      color: panel,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: hairline)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            height: barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _MobileNavDestination(
                        item: items[i],
                        label: items[i].displayLabel(compactLabels),
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavDestination extends StatelessWidget {
  const _MobileNavDestination({
    required this.item,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DashboardMobileNavItem item;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = AppTheme.dashTextSecondaryOf(context);
    final fg = selected ? Colors.white : inactive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryNavy : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 20, color: fg),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontSize: 9.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.0,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
