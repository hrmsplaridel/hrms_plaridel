import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Observes the TickerMode used by the dashboard's cached feature stack.
/// Listening directly also detects tabs whose offstage subtree isn't rebuilt.
mixin WorkforceTabRefreshMixin<T extends StatefulWidget> on State<T> {
  ValueListenable<TickerModeData>? _tabActivity;
  bool _wasActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = TickerMode.getValuesNotifier(context);
    if (identical(activity, _tabActivity)) return;
    _tabActivity?.removeListener(_onTabActivityChanged);
    _tabActivity = activity;
    _wasActive = activity.value.enabled;
    activity.addListener(_onTabActivityChanged);
  }

  void _onTabActivityChanged() {
    final active = _tabActivity!.value.enabled;
    if (active && !_wasActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabActivity!.value.enabled) onWorkforceTabReactivated();
      });
    }
    _wasActive = active;
  }

  void onWorkforceTabReactivated();

  @override
  void dispose() {
    _tabActivity?.removeListener(_onTabActivityChanged);
    super.dispose();
  }
}
