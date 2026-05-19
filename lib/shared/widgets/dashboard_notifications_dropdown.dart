import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../notifications/open_notifications_panel.dart';

/// Header bell that opens an edusync-style notifications dropdown.
class DashboardNotificationBellButton extends StatefulWidget {
  const DashboardNotificationBellButton({
    super.key,
    this.compact = false,
    this.onViewAll,
  });

  final bool compact;
  final VoidCallback? onViewAll;

  @override
  State<DashboardNotificationBellButton> createState() =>
      _DashboardNotificationBellButtonState();
}

class _DashboardNotificationBellButtonState
    extends State<DashboardNotificationBellButton> {
  void _openViewAll(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    if (widget.onViewAll != null) {
      widget.onViewAll!();
      return;
    }
    openNotificationsPanel(context);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 20.0 : 22.0;
    final pad = widget.compact ? 8.0 : 10.0;

    return PopupMenuButton<void>(
      offset: const Offset(0, 48),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      constraints: const BoxConstraints(minWidth: 380, maxWidth: 420),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: EdgeInsets.zero,
      color: AppTheme.dashPanelOf(context),
      itemBuilder: (menuContext) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: DashboardNotificationsDropdownPanel(
            onViewAll: () => _openViewAll(menuContext),
          ),
        ),
      ],
      child: Tooltip(
        message: 'Notifications',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Icon(
                  Icons.notifications_outlined,
                  color: AppTheme.primaryNavy,
                  size: iconSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown body: blue header, list / empty state, Clear all + View all.
class DashboardNotificationsDropdownPanel extends StatelessWidget {
  const DashboardNotificationsDropdownPanel({
    super.key,
    required this.onViewAll,
  });

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DropdownHeader(unreadCount: 0),
          const SizedBox(
            height: 200,
            child: _DropdownComingSoon(),
          ),
          _DropdownFooter(onViewAll: onViewAll),
        ],
      ),
    );
  }
}

class _DropdownHeader extends StatelessWidget {
  const _DropdownHeader({
    required this.unreadCount,
    this.onMarkAllRead,
  });

  final int unreadCount;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        color: AppTheme.primaryNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onMarkAllRead != null)
            TextButton(
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Mark all as read',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _DropdownComingSoon extends StatelessWidget {
  const _DropdownComingSoon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_outlined,
                size: 36,
                color: AppTheme.primaryNavy.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Implementing soon',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'In-app notifications are coming in a future update.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownFooter extends StatelessWidget {
  const _DropdownFooter({
    required this.onViewAll,
  });

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear All'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                side: const BorderSide(color: AppTheme.primaryNavy),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onViewAll,
              icon: const Icon(Icons.notifications_rounded, size: 18),
              label: const Text('View All'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
