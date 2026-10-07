import 'dart:async';
import 'package:flutter/foundation.dart';
import 'app_realtime_provider.dart';

/// Reloads authoritative access after a targeted event or socket reconnect.
class AdminAccessRefresh {
  AdminAccessRefresh({required this.realtime, required this.onRefresh}) {
    _connected = realtime.connected;
    _subscription = realtime.events.listen((event) {
      if (event.name == 'admin_access_changed') unawaited(refresh());
    });
    realtime.addListener(_connectionChanged);
  }

  final AppRealtimeProvider realtime;
  final Future<void> Function() onRefresh;
  late final StreamSubscription<AppRealtimeEvent> _subscription;
  bool _connected = false;
  bool _disposed = false;
  bool _running = false;
  bool _queued = false;

  void _connectionChanged() {
    final connected = realtime.connected;
    if (connected && !_connected) unawaited(refresh());
    _connected = connected;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        try {
          await onRefresh();
        } catch (error) {
          debugPrint('Access refresh failed: $error');
        }
      } while (_queued && !_disposed);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    realtime.removeListener(_connectionChanged);
    unawaited(_subscription.cancel());
  }
}
