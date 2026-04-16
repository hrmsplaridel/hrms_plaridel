import 'package:flutter/material.dart';

import '../utils/responsive_right_side_panel.dart';
import 'notification_tap_result.dart';
import 'notifications_screen.dart';

/// Same presentation as [openResponsiveLeaveFormHost]: right-side panel with a draggable
/// left edge (and double-tap to max/restore). On narrow screens, opens full-screen.
///
/// Returns [NotificationTapResult] when the user taps a notification (for routing);
/// `null` when the panel is closed without choosing an item (e.g. backdrop tap).
Future<NotificationTapResult?> openNotificationsPanel(BuildContext context) {
  return openResponsiveRightSidePanel<NotificationTapResult?>(
    context: context,
    barrierLabel: 'Close notifications',
    minWidth: 760,
    initialWidthFraction: 0.52,
    builder: (_) => const NotificationsScreen(),
  );
}
