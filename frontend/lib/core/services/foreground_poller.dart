import 'dart:async';
import 'package:flutter/widgets.dart';

/// Poll only while the app is visible. Owners perform their existing immediate resume refresh.
class ForegroundPoller with WidgetsBindingObserver {
  ForegroundPoller({required this.interval, required this.onTick}) {
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  final Duration interval;
  final VoidCallback onTick;
  Timer? _timer;
  bool _cancelled = false;

  void _start() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (_cancelled || (state != null && state != AppLifecycleState.resumed)) {
      return;
    }
    _timer ??= Timer.periodic(interval, (_) => onTick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
