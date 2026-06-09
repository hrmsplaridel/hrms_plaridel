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
    this.homeRefreshKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function() homeBuilder;
  final Widget settingsPanel;
  final EdgeInsets homeScrollPadding;
  final EdgeInsets settingsScrollPadding;
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
  final ValueNotifier<int> _homeVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> _settingsVersion = ValueNotifier<int>(0);

  @override
  void didUpdateWidget(covariant DashboardContentNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeRefreshKey != widget.homeRefreshKey ||
        oldWidget.homeScrollPadding != widget.homeScrollPadding) {
      _homeVersion.value++;
    }
    if (oldWidget.settingsPanel != widget.settingsPanel ||
        oldWidget.settingsScrollPadding != widget.settingsScrollPadding) {
      _settingsVersion.value++;
    }
  }

  @override
  void dispose() {
    _homeVersion.dispose();
    _settingsVersion.dispose();
    super.dispose();
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
          pageBuilder: (_, __, ___) => _DashboardScrollPage(
            listenable: isSettings ? _settingsVersion : _homeVersion,
            paddingBuilder: () => isSettings
                ? widget.settingsScrollPadding
                : widget.homeScrollPadding,
            childBuilder: () =>
                isSettings ? widget.settingsPanel : widget.homeBuilder(),
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
      builder: (context, _, __) {
        return ColoredBox(
          color: AppTheme.dashCanvasOf(context),
          child: SingleChildScrollView(
            padding: paddingBuilder(),
            child: childBuilder(),
          ),
        );
      },
    );
  }
}
