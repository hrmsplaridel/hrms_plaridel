import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  bool _firebaseReady = false;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _lastRegisteredToken;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!_isMessagingSupported) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('PushNotificationService.init skipped: $e');
      return;
    }

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      unawaited(_registerToken(token));
    });
  }

  Future<void> syncTokenWithBackend() async {
    if (!_firebaseReady) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(token);
    } catch (e) {
      debugPrint('PushNotificationService.syncTokenWithBackend failed: $e');
    }
  }

  Future<void> unregisterCurrentToken() async {
    if (!_firebaseReady) return;

    try {
      final token =
          _lastRegisteredToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await ApiClient.instance.delete<Map<String, dynamic>>(
        '/api/notifications/push-token',
        data: {'token': token},
        options: Options(extra: {'skipAuthRefresh': true}),
      );
      _lastRegisteredToken = null;
    } catch (e) {
      debugPrint('PushNotificationService.unregisterCurrentToken failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    if (token.isEmpty || token == _lastRegisteredToken) return;

    try {
      await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/notifications/push-token',
        data: {'token': token, 'platform': _platformName()},
      );
      _lastRegisteredToken = token;
    } catch (e) {
      debugPrint('PushNotificationService._registerToken failed: $e');
    }
  }

  String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  bool get _isMessagingSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
