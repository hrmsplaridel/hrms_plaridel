import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDarkModePrefKey = 'hrms_dark_mode';

/// Persists light/dark preference for [MaterialApp.themeMode].
class ThemeModeNotifier extends ChangeNotifier {
  ThemeModeNotifier({required ThemeMode initial}) : _mode = initial;

  ThemeMode _mode;
  bool _persisting = false;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Updates UI immediately; persistence runs in the background.
  void toggle() {
    setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    _persistInBackground();
  }

  void _persistInBackground() {
    if (_persisting) return;
    _persisting = true;
    unawaited(() async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kDarkModePrefKey, _mode == ThemeMode.dark);
      } finally {
        _persisting = false;
      }
    }());
  }

  /// Call from [main] after [SharedPreferences.getInstance].
  static Future<ThemeModeNotifier> load() async {
    final p = await SharedPreferences.getInstance();
    final dark = p.getBool(_kDarkModePrefKey) ?? false;
    return ThemeModeNotifier(
      initial: dark ? ThemeMode.dark : ThemeMode.light,
    );
  }
}
