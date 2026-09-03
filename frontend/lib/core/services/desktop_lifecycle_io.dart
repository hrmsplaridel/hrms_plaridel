import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopLifecycleService with WindowListener, TrayListener {
  DesktopLifecycleService._();

  static final DesktopLifecycleService instance = DesktopLifecycleService._();

  bool _initialized = false;
  bool _exiting = false;
  String? _notificationIconPath;

  String? get notificationIconPath => _notificationIconPath;

  Future<void> initialize({bool startHidden = false}) async {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);

    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final trayIcon = File(
      '$executableDirectory\\data\\flutter_assets\\windows\\runner\\resources\\app_icon.ico',
    );
    final developmentIcon = File('windows/runner/resources/app_icon.ico');
    final iconPath = trayIcon.existsSync()
        ? trayIcon.path
        : developmentIcon.absolute.path;
    _notificationIconPath = iconPath;

    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('HRMS Plaridel');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open_hrms', label: 'Open HRMS'),
          MenuItem.separator(),
          MenuItem(key: 'exit_hrms', label: 'Exit HRMS'),
        ],
      ),
    );

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        args: const ['--hidden'],
      );
      await launchAtStartup.enable();
    } catch (error) {
      debugPrint('Could not enable HRMS launch at startup: $error');
    }

    if (startHidden) {
      await windowManager.hide();
    }
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows requires the menu owner to be foregrounded so an outside click
    // dismisses the native popup. This does not make the hidden HRMS window visible.
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_hrms':
        showWindow();
        return;
      case 'exit_hrms':
        _exit();
        return;
    }
  }
}
