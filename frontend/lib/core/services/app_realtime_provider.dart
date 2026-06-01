import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:hrms_plaridel/core/api/config.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';

class AppRealtimeEvent {
  const AppRealtimeEvent({
    required this.name,
    this.payload = const <String, dynamic>{},
    this.createdAt,
  });

  final String name;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  factory AppRealtimeEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return AppRealtimeEvent(
      name: json['event']?.toString() ?? '',
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  String? payloadString(String key) {
    final value = payload[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Set<String> payloadStringSet(String key) {
    final value = payload[key];
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toSet();
    }
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? <String>{} : {text};
  }

  bool affectsUser(String? userId) {
    final normalized = userId?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    final directUserId = payloadString('userId');
    final snakeUserId = payloadString('user_id');
    final userIds = <String>{
      ...payloadStringSet('userIds'),
      ...payloadStringSet('user_ids'),
      if (directUserId != null) directUserId,
      if (snakeUserId != null) snakeUserId,
    };
    return userIds.isEmpty || userIds.contains(normalized);
  }
}

class AppRealtimeProvider extends ChangeNotifier {
  AppRealtimeProvider();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  String? _currentUserId;
  bool _disposed = false;
  bool _connecting = false;
  bool _connected = false;

  final _eventController = StreamController<AppRealtimeEvent>.broadcast();

  Stream<AppRealtimeEvent> get events => _eventController.stream;
  bool get connected => _connected;

  void setCurrentUser(String? userId) {
    final normalized = userId?.trim();
    final nextUserId = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_currentUserId == nextUserId) return;

    _currentUserId = nextUserId;
    _reconnectTimer?.cancel();
    _closeSocket();
    _connected = false;
    notifyListeners();

    if (nextUserId != null) {
      unawaited(_connect());
    }
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || _currentUserId == null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    WebSocketChannel? openedChannel;

    try {
      final token = await TokenStorage.instance.getToken();
      if (_disposed || _currentUserId == null) return;
      if (token == null || token.isEmpty) {
        _scheduleReconnect();
        return;
      }

      _closeSocket();
      final wsUrl = _buildWsUrl(token);
      final channel = WebSocketChannel.connect(wsUrl);
      openedChannel = channel;
      _channel = channel;
      _socketSub = channel.stream.listen(
        _handleMessage,
        onDone: _handleDisconnected,
        onError: (_) => _handleDisconnected(),
        cancelOnError: true,
      );
      await channel.ready;
      if (_disposed || !identical(_channel, channel)) return;
      _connected = true;
      notifyListeners();
    } catch (_) {
      if (openedChannel == null || identical(_channel, openedChannel)) {
        _handleDisconnected();
      }
    } finally {
      _connecting = false;
    }
  }

  Uri _buildWsUrl(String token) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final path = '$basePath/ws/app';
    return base.replace(
      scheme: scheme,
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: {...base.queryParameters, 'token': token},
    );
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map) return;
      final event = AppRealtimeEvent.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (event.name.isEmpty || event.name == 'connected') return;
      _eventController.add(event);
    } catch (_) {
      // Ignore malformed realtime frames.
    }
  }

  void _handleDisconnected() {
    if (_disposed) return;
    _connected = false;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _currentUserId == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_connect());
    });
  }

  void _closeSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _closeSocket();
    _eventController.close();
    super.dispose();
  }
}
