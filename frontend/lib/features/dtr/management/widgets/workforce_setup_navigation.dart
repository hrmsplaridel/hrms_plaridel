import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/platform_layout.dart';
import 'package:hrms_plaridel/features/dtr/dtr_routes.dart';

/// Workforce Setup section switcher: one scrollable tab row on tablet and
/// desktop, a dropdown on mobile.
class WorkforceSetupNavigation extends StatefulWidget {
  const WorkforceSetupNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final DtrPage selected;
  final ValueChanged<DtrPage> onSelected;

  @override
  State<WorkforceSetupNavigation> createState() =>
      _WorkforceSetupNavigationState();
}

class _WorkforceSetupNavigationState extends State<WorkforceSetupNavigation> {
  final _scroll = ScrollController();
  final _tabKeys = {for (final p in DtrPage.workforcePages) p: GlobalKey()};
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static IconData _iconFor(DtrPage page) => switch (page) {
    DtrPage.assignments => Icons.assignment_rounded,
    DtrPage.departments => Icons.business_rounded,
    DtrPage.positions => Icons.work_rounded,
    DtrPage.shifts => Icons.access_time_rounded,
    DtrPage.weeklySchedule => Icons.calendar_view_week_rounded,
    DtrPage.holidays => Icons.calendar_today_rounded,
    DtrPage.attendancePolicies => Icons.policy_rounded,
    _ => Icons.settings_rounded,
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateArrows);
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(covariant WorkforceSetupNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _tabKeys[widget.selected]?.currentContext;
      if (tab != null) {
        Scrollable.ensureVisible(
          tab,
          alignment: 0.5,
          duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
          curve: Curves.easeOutCubic,
        );
      }
      _updateArrows();
    });
  }

  void _updateArrows() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final left = p.pixels > p.minScrollExtent + 1;
    final right = p.pixels < p.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollBy(double direction) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.animateTo(
      (p.pixels + direction * p.viewportDimension * 0.6).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < PlatformLayout.mobileBreakpoint;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Workforce Setup',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          mobile ? _buildDropdown(context) : _buildTabRow(context),
        ],
      );
    },
  );

  Widget _buildDropdown(BuildContext context) =>
      DropdownButtonFormField<DtrPage>(
        key: ValueKey(widget.selected),
        initialValue: widget.selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Section',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final page in DtrPage.workforcePages)
            DropdownMenuItem(value: page, child: Text(page.title)),
        ],
        onChanged: (page) {
          if (page != null && page != widget.selected) widget.onSelected(page);
        },
      );

  Widget _buildTabRow(BuildContext context) {
    final muted = AppTheme.dashTextSecondaryOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
          return false;
        },
        // Arrows float over the row so showing them never shifts the tabs.
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final page in DtrPage.workforcePages)
                    _tab(context, page),
                ],
              ),
            ),
            if (_canScrollLeft)
              Positioned(
                left: 0,
                top: 0,
                bottom: 3,
                child: _scrollArrow(
                  context,
                  tooltip: 'Scroll tabs left',
                  icon: Icons.chevron_left_rounded,
                  color: muted,
                  onPressed: () => _scrollBy(-1),
                ),
              ),
            if (_canScrollRight)
              Positioned(
                right: 0,
                top: 0,
                bottom: 3,
                child: _scrollArrow(
                  context,
                  tooltip: 'Scroll tabs right',
                  icon: Icons.chevron_right_rounded,
                  color: muted,
                  onPressed: () => _scrollBy(1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scrollArrow(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) => Material(
    color: AppTheme.dashCanvasOf(context),
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      color: color,
      onPressed: onPressed,
    ),
  );

  Widget _tab(BuildContext context, DtrPage page) {
    final selected = widget.selected == page;
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final foreground = selected
        ? accent
        : AppTheme.dashTextSecondaryOf(context);
    return Semantics(
      key: _tabKeys[page],
      container: true,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => widget.onSelected(page),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(page), size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                page.title,
                style: TextStyle(
                  color: selected
                      ? AppTheme.dashTextPrimaryOf(context)
                      : foreground,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
