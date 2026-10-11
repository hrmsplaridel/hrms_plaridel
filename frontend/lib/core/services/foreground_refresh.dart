import 'dart:async';
import 'package:flutter/widgets.dart';

/// Serializes refreshes, pauses background work, and refreshes on return.
class ForegroundRefresh with WidgetsBindingObserver {
  ForegroundRefresh({required this.onRefresh, this.interval}) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  final Future<void> Function() onRefresh;
  final Duration Function()? interval;
  Timer? _timer;
  Future<void>? _running;
  bool _foreground = true, _disposed = false, _trailing = false;

  Future<void> refresh({bool trailing = false}) {
    if (_disposed || !_foreground) return Future.value();
    if (_running != null) {
      _trailing |= trailing;
      return _running!;
    }
    _timer?.cancel();
    _timer = null;
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(_run(completion));
    return completion.future;
  }

  Future<void> _run(Completer<void> completion) async {
    do {
      _trailing = false;
      try {
        await onRefresh();
      } catch (error) {
        debugPrint('Foreground refresh failed: $error');
      }
    } while (_trailing && _foreground && !_disposed);
    _running = null;
    completion.complete();
    _schedule();
  }

  void _schedule() {
    if (_disposed || !_foreground || interval == null || _running != null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(interval!(), () {
      _timer = null;
      unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      unawaited(refresh(trailing: true));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
