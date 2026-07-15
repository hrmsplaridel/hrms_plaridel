import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/desktop_lifecycle.dart';
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
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  String? _lastRegisteredToken;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'hrms_notifications',
        'HRMS Notifications',
        description: 'DTR, leave, locator, and HRMS alerts.',
        importance: Importance.high,
      );

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (_isLocalNotificationSupported) {
      try {
        await _initLocalNotifications();
      } catch (e) {
        debugPrint('Local notification initialization skipped: $e');
      }
    }

    if (!_isMessagingSupported) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
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
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    final windows = WindowsInitializationSettings(
      appName: 'HRMS Plaridel',
      appUserModelId: 'MunicipalityOfPlaridel.HRMS',
      guid: 'ec0e2e3a-2e0e-4ed7-a71c-b1dc2f587426',
      iconPath: DesktopLifecycleService.instance.notificationIconPath,
    );
    final settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: windows,
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) {
        unawaited(DesktopLifecycleService.instance.showWindow());
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'HRMS';
    final body = notification?.body ?? message.data['body']?.toString() ?? '';

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap(
            'notification_large_icon',
          ),
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['notification_id']?.toString(),
    );
  }

  Future<void> showDesktopNotification({
    required String id,
    required String title,
    String? body,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    await _localNotifications.show(
      id: id.hashCode & 0x7fffffff,
      title: title.isEmpty ? 'HRMS Plaridel' : title,
      body: body ?? '',
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(),
      ),
      payload: id,
    );
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

      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
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

  bool get _isLocalNotificationSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundMessageSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundMessageSub = null;
  }
}
