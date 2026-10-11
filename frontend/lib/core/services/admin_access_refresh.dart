import 'dart:async';
import 'foreground_refresh.dart';
import 'app_realtime_provider.dart';

/// Reloads authoritative access after a targeted event or socket reconnect.
class AdminAccessRefresh {
  AdminAccessRefresh({required this.realtime, required this.onRefresh}) {
    _refresh = ForegroundRefresh(onRefresh: onRefresh);
    _connected = realtime.connected;
    _subscription = realtime.events.listen((event) {
      if (event.name == 'admin_access_changed') {
        unawaited(refresh(trailing: true));
      }
    });
    realtime.addListener(_connectionChanged);
  }

  final AppRealtimeProvider realtime;
  final Future<void> Function() onRefresh;
  late final StreamSubscription<AppRealtimeEvent> _subscription;
  bool _connected = false;
  bool _disposed = false;
  late final ForegroundRefresh _refresh;

  void _connectionChanged() {
    final connected = realtime.connected;
    if (connected && !_connected) unawaited(refresh(trailing: true));
    _connected = connected;
  }

  Future<void> refresh({bool trailing = false}) =>
      _disposed ? Future.value() : _refresh.refresh(trailing: trailing);

  void dispose() {
    _disposed = true;
    _refresh.dispose();
    realtime.removeListener(_connectionChanged);
    unawaited(_subscription.cancel());
  }
}
