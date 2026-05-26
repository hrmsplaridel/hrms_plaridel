import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Sent as `X-HRMS-Device` on login/refresh so sessions show platform / unit.
class ClientDeviceHeader {
  ClientDeviceHeader._();

  static String? _cached;

  static Future<String> build() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cached = '${_platformLabel()} · ${info.appName} ${info.version}';
    } catch (_) {
      _cached = _platformLabel();
    }
    return _cached!;
  }

  static String _platformLabel() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iPhone or iPad',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.linux => 'Linux PC',
      TargetPlatform.fuchsia => 'Device',
    };
  }
}
