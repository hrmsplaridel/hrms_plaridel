import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Routes for the nested navigator inside admin/employee dashboard content.
abstract final class DashboardContentRoutes {
  static const home = '/';
  static const settings = '/settings';
}

/// Nested [Navigator] so opening Settings pushes a route instead of rebuilding
/// the entire dashboard body (DTR, charts, etc. stay mounted underneath).
class DashboardContentNavigator extends StatefulWidget {
  const DashboardContentNavigator({
    super.key,
    required this.navigatorKey,
    required this.homeBuilder,
    required this.settingsPanel,
    required this.homeScrollPadding,
    required this.settingsScrollPadding,
    this.homeCacheKey,
    this.homeRefreshKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function() homeBuilder;
  final Widget settingsPanel;
  final EdgeInsets homeScrollPadding;
  final EdgeInsets settingsScrollPadding;
  final Object? homeCacheKey;
  final Object? homeRefreshKey;

  static bool isSettingsOnTop(NavigatorState? nav) {
    if (nav == null) return false;
    return nav.canPop();
  }

  static void openSettings(GlobalKey<NavigatorState> key) {
    final nav = key.currentState;
    if (nav == null) return;
    if (isSettingsOnTop(nav)) return;
    nav.pushNamed(DashboardContentRoutes.settings);
  }

  /// Pops settings/profile overlays while keeping the live home route mounted.
  static void showHome(GlobalKey<NavigatorState> key) {
    final nav = key.currentState;
    if (nav == null) return;
    while (nav.canPop()) {
      nav.pop();
    }
  }

  @override
  State<DashboardContentNavigator> createState() =>
      _DashboardContentNavigatorState();
}

class _DashboardContentNavigatorState extends State<DashboardContentNavigator> {
  static final Object _fallbackHomeCacheKey = Object();
  static const int _maxHomeCacheEntries = 4;

  final ValueNotifier<int> _homeVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> _settingsVersion = ValueNotifier<int>(0);
  final Map<Object, _DashboardHomeEntry> _homeCache =
      <Object, _DashboardHomeEntry>{};
  int _homeCacheClock = 0;
  bool _homeRefreshScheduled = false;
  bool _settingsRefreshScheduled = false;

  @override
  void didUpdateWidget(covariant DashboardContentNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeCacheKey != widget.homeCacheKey ||
        oldWidget.homeRefreshKey != widget.homeRefreshKey ||
        oldWidget.homeScrollPadding != widget.homeScrollPadding) {
      _scheduleHomeRefresh();
    }
    if (oldWidget.settingsPanel != widget.settingsPanel ||
        oldWidget.settingsScrollPadding != widget.settingsScrollPadding) {
      _scheduleSettingsRefresh();
    }
  }

  void _scheduleHomeRefresh() {
    if (_homeRefreshScheduled) return;
    _homeRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeRefreshScheduled = false;
      if (!mounted) return;
      _homeVersion.value++;
    });
  }

  void _scheduleSettingsRefresh() {
    if (_settingsRefreshScheduled) return;
    _settingsRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settingsRefreshScheduled = false;
      if (!mounted) return;
      _settingsVersion.value++;
    });
  }

  @override
  void dispose() {
    _homeVersion.dispose();
    _settingsVersion.dispose();
    super.dispose();
  }

  Object get _effectiveHomeCacheKey =>
      widget.homeCacheKey ?? widget.homeRefreshKey ?? _fallbackHomeCacheKey;

  Widget _buildHomeCacheStack(BuildContext context) {
    final cacheKey = _effectiveHomeCacheKey;
    final refreshKey = widget.homeRefreshKey ?? cacheKey;
    final existing = _homeCache[cacheKey];

    if (existing == null ||
        existing.refreshKey != refreshKey ||
        existing.padding != widget.homeScrollPadding) {
      _homeCache[cacheKey] = _DashboardHomeEntry(
        cacheKey: cacheKey,
        refreshKey: refreshKey,
        padding: widget.homeScrollPadding,
        child: RepaintBoundary(
          child: SingleChildScrollView(
            key: PageStorageKey<Object>(cacheKey),
            padding: widget.homeScrollPadding,
            child: widget.homeBuilder(),
          ),
        ),
        lastUsed: ++_homeCacheClock,
      );
    } else {
      existing.lastUsed = ++_homeCacheClock;
    }

    _trimHomeCache(activeKey: cacheKey);
    final entries = _homeCache.values.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    return _DashboardHomeCacheStack(entries: entries, activeKey: cacheKey);
  }

  void _trimHomeCache({required Object activeKey}) {
    if (_homeCache.length <= _maxHomeCacheEntries) return;
    final removable =
        _homeCache.entries.where((entry) => entry.key != activeKey).toList()
          ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final entry in removable) {
      if (_homeCache.length <= _maxHomeCacheEntries) return;
      _homeCache.remove(entry.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: widget.navigatorKey,
      initialRoute: DashboardContentRoutes.home,
      onGenerateRoute: (settings) {
        final isSettings = settings.name == DashboardContentRoutes.settings;
        return PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, __, ___) => isSettings
              ? _DashboardScrollPage(
                  listenable: _settingsVersion,
                  paddingBuilder: () => widget.settingsScrollPadding,
                  childBuilder: () => widget.settingsPanel,
                )
              : _DashboardHomeCachePage(
                  listenable: _homeVersion,
                  stackBuilder: _buildHomeCacheStack,
                ),
          transitionDuration: isSettings
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (_, animation, __, child) {
            if (!isSettings) return child;
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        );
      },
    );
  }
}

class _DashboardHomeCachePage extends StatelessWidget {
  const _DashboardHomeCachePage({
    required this.listenable,
    required this.stackBuilder,
  });

  final ValueListenable<int> listenable;
  final WidgetBuilder stackBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, _, __) => stackBuilder(context),
    );
  }
}

class _DashboardHomeCacheStack extends StatelessWidget {
  const _DashboardHomeCacheStack({
    required this.entries,
    required this.activeKey,
  });

  final List<_DashboardHomeEntry> entries;
  final Object activeKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.dashCanvasOf(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final entry in entries)
            Positioned.fill(
              child: Offstage(
                offstage: entry.cacheKey != activeKey,
                child: TickerMode(
                  enabled: entry.cacheKey == activeKey,
                  child: entry.child,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardHomeEntry {
  _DashboardHomeEntry({
    required this.cacheKey,
    required this.refreshKey,
    required this.padding,
    required this.child,
    required this.lastUsed,
  });

  final Object cacheKey;
  final Object refreshKey;
  final EdgeInsets padding;
  final Widget child;
  int lastUsed;
}

class _DashboardScrollPage extends StatelessWidget {
  const _DashboardScrollPage({
    required this.listenable,
    required this.paddingBuilder,
    required this.childBuilder,
  });

  final ValueListenable<int> listenable;
  final EdgeInsets Function() paddingBuilder;
  final Widget Function() childBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, version, __) {
        return ColoredBox(
          color: AppTheme.dashCanvasOf(context),
          child: RepaintBoundary(
            child: SingleChildScrollView(
              key: ValueKey<int>(version),
              padding: paddingBuilder(),
              child: childBuilder(),
            ),
          ),
        );
      },
    );
  }
}
