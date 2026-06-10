import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/push_notification_service.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/core/utils/webview_platform_init_stub.dart'
    if (dart.library.html) 'package:hrms_plaridel/core/utils/webview_platform_init_web.dart'
    as webview_platform_init;
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';

class AppBootstrap {
  const AppBootstrap({required this.auth, required this.themeNotifier});

  final AuthProvider auth;
  final ThemeModeNotifier themeNotifier;
}

Future<AppBootstrap> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(FormPdf.warmupPrintAssets());

  if (kIsWeb) {
    webview_platform_init.registerWebViewPlatform();
  }

  ApiClient.instance.init();
  await PushNotificationService.instance.init();

  return AppBootstrap(
    auth: AuthProvider(),
    themeNotifier: ThemeModeNotifier(initial: ThemeMode.light),
  );
}
