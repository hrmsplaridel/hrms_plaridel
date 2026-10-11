import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';

bool isRateLimitError(Object error) =>
    error is DioException && error.response?.statusCode == 429;

class RateLimitCooldownException extends DioException {
  RateLimitCooldownException(
    RequestOptions options,
    String scope,
    int seconds, {
    String? message,
    String? code,
  }) : super(
         requestOptions: options,
         type: DioExceptionType.badResponse,
         response: Response(
           requestOptions: options,
           statusCode: 429,
           headers: Headers.fromMap({
             'retry-after': ['$seconds'],
           }),
           data: {
             'error': message == null
                 ? 'Too many requests. Please wait $seconds seconds before trying again.'
                 : (code?.startsWith('DTR_ASSISTANT_') == true
                       ? message
                       : '$message Retry in $seconds seconds.'),
             'code': code ?? 'RATE_LIMIT_COOLDOWN',
             'rateLimitScope': scope,
             'retryAfterSeconds': seconds,
           },
         ),
       );
}

/// Coordinates request budgets within one client. It never queues or replays a request.
class RateLimitCooldown {
  RateLimitCooldown({
    DateTime Function()? now,
    int Function()? jitterMilliseconds,
  }) : _now = now ?? DateTime.now,
       _jitter = jitterMilliseconds ?? (() => 250 + Random().nextInt(751));

  final DateTime Function() _now;
  final int Function() _jitter;
  final Map<String, DateTime> _until = {};
  static const _knownScopes = {
    'api_read',
    'api_write',
    'api_heavy',
    'network_read',
    'network_write',
    'auth_login',
    'auth_register',
    'auth_refresh',
    'auth_logout',
    'network_auth_refresh',
    'network_auth_logout',
    'auth_password_change',
    'auth_password_reset',
    'auth_password_reset_verify',
    'assistant_chat',
    'assistant_exports',
    'assistant_reset',
    'assistant_feedback',
  };

  RateLimitCooldownException? blocked(RequestOptions options) {
    _prune();
    for (final scope in _scopes(options)) {
      final until = _until[_key(options, scope)];
      if (until != null) return _error(options, scope, until);
    }
    return null;
  }

  RateLimitCooldownException record(DioException error) {
    final options = error.requestOptions;
    final data = error.response?.data;
    final declared = data is Map ? data['rateLimitScope']?.toString() : null;
    final code = data is Map ? data['code']?.toString() ?? '' : '';
    final scope = _knownScopes.contains(declared)
        ? declared!
        : code.startsWith('DTR_ASSISTANT_')
        ? _assistantScope(options.uri.path)
        : _routeScope(options);
    final header = error.response?.headers.value('retry-after');
    final headerSeconds = int.tryParse(header ?? '');
    final date = _httpDate(header);
    final bodySeconds = data is Map
        ? int.tryParse('${data['retryAfterSeconds']}')
        : null;
    final seconds =
        (headerSeconds ??
                (date == null
                    ? bodySeconds
                    : ((date.difference(_now()).inMilliseconds + 999) ~/
                          1000)) ??
                30)
            .clamp(1, 86400);
    _prune();
    final key = _key(options, scope);
    if (_until.length >= 128 && !_until.containsKey(key)) {
      _until.remove(_until.keys.first);
    }
    final next = _now().add(
      Duration(seconds: seconds, milliseconds: _jitter().clamp(0, 1000)),
    );
    if (_until[key] == null || next.isAfter(_until[key]!)) _until[key] = next;
    return _error(
      options,
      scope,
      _until[key]!,
      message: data is Map ? data['error']?.toString() : null,
      code: code.isEmpty ? null : code,
    );
  }

  void _prune() => _until.removeWhere((_, until) => !until.isAfter(_now()));
  RateLimitCooldownException _error(
    RequestOptions options,
    String scope,
    DateTime until, {
    String? message,
    String? code,
  }) => RateLimitCooldownException(
    options,
    scope,
    ((until.difference(_now()).inMilliseconds + 999) ~/ 1000).clamp(1, 86401),
    message: message,
    code: code,
  );

  String _key(RequestOptions options, String scope) {
    var identity = 'network';
    if (scope.startsWith('api_') ||
        scope.startsWith('assistant_') ||
        scope == 'auth_refresh' ||
        scope == 'auth_logout' ||
        scope.startsWith('route:')) {
      final token = options.headers['Authorization']?.toString() ?? '';
      identity = token.isEmpty ? 'anonymous' : token;
      try {
        // Local cooldown grouping only; server authentication remains authoritative.
        final payload = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(token.split('.')[1])),
          ),
        );
        if (payload is Map && payload['id'] is String) {
          identity = 'user:${payload['id']}';
        }
      } catch (_) {}
    }
    final uri = options.uri;
    return '${uri.scheme}://${uri.host}:${uri.port}|$scope|$identity';
  }

  String _routeScope(RequestOptions o) =>
      'route:${o.method.toUpperCase()}:${o.uri.path}';
  String _assistantScope(String path) =>
      'assistant_${path.split('/').where((p) => p.isNotEmpty).skip(2).firstOrNull ?? 'chat'}';
  Set<String> _scopes(RequestOptions o) {
    final path = o.uri.path.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    final read = ['GET', 'HEAD', 'OPTIONS'].contains(o.method.toUpperCase());
    final scopes = <String>{_routeScope(o)};
    if (path.startsWith('/api/')) {
      scopes.add(read ? 'network_read' : 'network_write');
      final heavy =
          o.method.toUpperCase() == 'POST' &&
          (path == '/api/dtr-daily-summary/bulk-report' ||
              RegExp(
                r'^/api/(leave|locator-slips)/print/(requests/[^/]+/render|types/[^/]+/preview)$',
              ).hasMatch(path));
      scopes.add(
        read
            ? 'api_read'
            : heavy
            ? 'api_heavy'
            : 'api_write',
      );
      if (path.startsWith('/api/dtr-assistant/')) {
        scopes.add(_assistantScope(path));
      }
    }
    final authScope = switch (path) {
      '/auth/login' => 'auth_login',
      '/auth/register' => 'auth_register',
      '/auth/refresh' => 'auth_refresh',
      '/auth/logout' => 'auth_logout',
      '/auth/forgot-password' => 'auth_password_reset',
      '/auth/reset-password' => 'auth_password_reset_verify',
      '/auth/change-password' => 'auth_password_change',
      _ =>
        o.method.toUpperCase() == 'DELETE' && path.startsWith('/auth/sessions/')
            ? 'auth_logout'
            : null,
    };
    if (authScope != null) scopes.addAll([authScope, 'network_$authScope']);
    return scopes;
  }

  DateTime? _httpDate(String? text) {
    if (text == null) return null;
    final match = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(match[2]!);
    if (month < 0) return null;
    return DateTime.utc(
      int.parse(match[3]!),
      month + 1,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }
}
