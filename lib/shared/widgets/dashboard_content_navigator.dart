import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';

/// Routes for the nested navigator inside admin/employee dashboard content.
abstract final class DashboardContentRoutes {
  static const home = '/';
  static const settings = '/settings';
}

/// Nested [Navigator] so opening Settings pushes a route instead of rebuilding
/// the entire dashboard body (DTR, charts, etc. stay mounted underneath).
class DashboardContentNavigator extends StatelessWidget {
  const DashboardContentNavigator({
    super.key,
    required this.navigatorKey,
    required this.homeBuilder,
    required this.settingsPanel,
    required this.homeScrollPadding,
    required this.settingsScrollPadding,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function() homeBuilder;
  final Widget settingsPanel;
  final EdgeInsets homeScrollPadding;
  final EdgeInsets settingsScrollPadding;

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

  /// Pops settings (if any) and replaces the home route with fresh content.
  static void showHome(GlobalKey<NavigatorState> key) {
    final nav = key.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(
      DashboardContentRoutes.home,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      initialRoute: DashboardContentRoutes.home,
      onGenerateRoute: (settings) {
        final isSettings = settings.name == DashboardContentRoutes.settings;
        final body = isSettings ? settingsPanel : homeBuilder();
        final padding =
            isSettings ? settingsScrollPadding : homeScrollPadding;
        return PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, __, ___) => _DashboardScrollPage(
            padding: padding,
            child: body,
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
    required this.padding,
    required this.child,
  });

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.dashCanvasOf(context),
      child: SingleChildScrollView(
        padding: padding,
        child: child,
      ),
    );
  }
}
