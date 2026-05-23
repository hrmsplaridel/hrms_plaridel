import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../leave/leave_provider.dart';
import '../notifications/notification_provider.dart';
import 'app_realtime_provider.dart';

class AppRealtimeBridge extends StatefulWidget {
  const AppRealtimeBridge({super.key, required this.child});

  final Widget child;

  @override
  State<AppRealtimeBridge> createState() => _AppRealtimeBridgeState();
}

class _AppRealtimeBridgeState extends State<AppRealtimeBridge> {
  AppRealtimeProvider? _provider;
  StreamSubscription<AppRealtimeEvent>? _eventsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = context.read<AppRealtimeProvider>();
    if (identical(_provider, nextProvider)) return;

    _eventsSub?.cancel();
    _provider = nextProvider;
    _eventsSub = nextProvider.events.listen(_handleEvent);
  }

  void _handleEvent(AppRealtimeEvent event) {
    if (!mounted) return;
    if (event.name == 'leave_updated') {
      try {
        context.read<LeaveProvider>().invalidateCachedLeaveData();
      } catch (_) {}
      return;
    }
    if (event.name != 'notification_created') return;

    final notifications = context.read<NotificationProvider>();
    if (notifications.items.isEmpty) {
      unawaited(notifications.refreshUnreadCount());
    } else {
      unawaited(notifications.loadNotifications());
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
