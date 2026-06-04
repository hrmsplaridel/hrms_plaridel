import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppLayoutPlatform { mobile, web, desktop }

class PlatformLayout {
  const PlatformLayout._();

  static const double mobileBreakpoint = 600;

  static AppLayoutPlatform of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < mobileBreakpoint) return AppLayoutPlatform.mobile;
    if (kIsWeb) return AppLayoutPlatform.web;
    return AppLayoutPlatform.desktop;
  }

  static bool isMobile(BuildContext context) {
    return of(context) == AppLayoutPlatform.mobile;
  }

  static bool isWeb(BuildContext context) {
    return of(context) == AppLayoutPlatform.web;
  }

  static bool isDesktop(BuildContext context) {
    return of(context) == AppLayoutPlatform.desktop;
  }
}

class PlatformLayoutBuilder extends StatelessWidget {
  const PlatformLayoutBuilder({
    super.key,
    required this.mobile,
    required this.web,
    required this.desktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder web;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    switch (PlatformLayout.of(context)) {
      case AppLayoutPlatform.mobile:
        return mobile(context);
      case AppLayoutPlatform.web:
        return web(context);
      case AppLayoutPlatform.desktop:
        return desktop(context);
    }
  }
}
