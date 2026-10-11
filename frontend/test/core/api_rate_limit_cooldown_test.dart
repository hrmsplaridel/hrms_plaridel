import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/core/api/rate_limit_cooldown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ClientDeviceHeader.build();
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await TokenStorage.instance.setTokens(
      access: 'employee-a',
      refresh: 'refresh-a',
    );
  });
  test(
    'PDF 429 bytes share heavy cooldown while ordinary writes and other users remain available',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((o) {
          calls++;
          return calls == 1
              ? _json(429, {
                  'code': 'RATE_LIMITED',
                  'error': 'PDF limit reached',
                  'rateLimitScope': 'api_heavy',
                  'retryAfterSeconds': 60,
                })
              : _json(200, {});
        });
      final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())..init();
      final error = await _failure(
        () => client.post<List<int>>(
          '/api/leave/print/requests/a/render',
          options: Options(responseType: ResponseType.bytes),
        ),
      );
      expect(error.response?.data['rateLimitScope'], 'api_heavy');
      expect(
        error.response?.data['retryAfterSeconds'],
        inInclusiveRange(60, 61),
      );
      expect(error.response?.data['error'], contains('PDF limit reached'));
      await _failure(
        () => client.post('/api/locator-slips/print/types/b/preview'),
      );
      await _failure(() => client.post('/api/dtr-daily-summary/bulk-report'));
      expect(calls, 1);
      expect((await client.post('/api/leave/a/approve')).statusCode, 200);
      expect(await TokenStorage.instance.getToken(), 'employee-a');
      await TokenStorage.instance.setTokens(
        access: 'employee-b',
        refresh: 'refresh-b',
      );
      expect(
        (await client.post('/api/dtr-daily-summary/bulk-report')).statusCode,
        200,
      );
      expect(calls, 3);
    },
  );
  test(
    'byte errors retain network scope and safely fall back for invalid bodies',
    () {
      final request = RequestOptions(
        path: '/api/leave/print/requests/a/render',
        method: 'POST',
      );
      for (final body in <List<int>>[
        utf8.encode(jsonEncode({'rateLimitScope': 'network_write'})),
        [255],
        utf8.encode('not json'),
        utf8.encode('[]'),
        utf8.encode('${' ' * 4096}{"rateLimitScope":"network_write"}'),
      ]) {
        final cooldown = RateLimitCooldown(jitterMilliseconds: () => 0);
        cooldown.record(
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 429,
              data: body,
              headers: Headers.fromMap({
                'retry-after': ['60'],
              }),
            ),
          ),
        );
        expect(cooldown.blocked(request), isNotNull);
        final otherWrite = cooldown.blocked(
          RequestOptions(path: '/api/leave/a/approve', method: 'POST'),
        );
        expect(otherWrite != null, body.first == 123);
        expect(
          cooldown.blocked(RequestOptions(path: '/api/notifications')),
          isNull,
        );
      }
    },
  );
  test(
    'PDF busy responses expose a readable message without replay or sign-out',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((o) {
          calls++;
          return o.path.endsWith('/render')
              ? _json(503, {
                  'code': 'HEAVY_OPERATION_BUSY',
                  'error':
                      'Report/PDF processing is busy. Please try again in 5 seconds.',
                  'retryAfterSeconds': 5,
                }, '5')
              : _json(200, {});
        });
      final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())..init();
      final error = await _failure(
        () => client.post<List<int>>(
          '/api/leave/print/requests/id/render',
          options: Options(responseType: ResponseType.bytes),
        ),
      );
      expect(error.response?.data, isA<Map>());
      expect(error.message, contains('try again in 5 seconds'));
      expect(calls, 1);
      expect(await TokenStorage.instance.getToken(), 'employee-a');
      expect((await client.post('/api/leave/id/approve')).statusCode, 200);
      expect(calls, 2);
    },
  );
  test(
    'shared read cooldown stops polling without blocking writes or replaying requests',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((o) {
          calls++;
          return o.method == 'GET'
              ? _json(429, {
                  'error': 'Read limit',
                  'rateLimitScope': 'api_read',
                }, '60')
              : _json(200, {});
        });
      final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())..init();
      expect(
        (await _failure(
          () => client.get('/api/notifications/unread-count'),
        )).response?.statusCode,
        429,
      );
      final blocked = await _failure(
        () => client.get('/api/leave/my-requests'),
      );
      expect(blocked.response?.data['retryAfterSeconds'], greaterThan(0));
      expect(calls, 1);
      expect((await client.post('/api/leave/request/approve')).statusCode, 200);
      expect(calls, 2);
      expect(await TokenStorage.instance.getToken(), 'employee-a');
    },
  );
  test(
    'heavy cooldown leaves ordinary writes available and never retries approval',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((_) {
          calls++;
          return _json(429, {
            'rateLimitScope': calls == 1 ? 'api_heavy' : 'api_write',
          }, '60');
        });
      final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())..init();
      await _failure(() => client.post('/api/dtr-daily-summary/bulk-report'));
      await _failure(() => client.post('/api/leave/print/requests/id/render'));
      expect(calls, 1);
      await _failure(() => client.post('/api/leave/id/approve'));
      await _failure(() => client.post('/api/locator-slips/id/approve'));
      expect(calls, 2);
    },
  );
  test(
    'cooldowns expire, survive token rotation for the same user, and isolate accounts and origins',
    () {
      var now = DateTime.utc(2026, 10, 11);
      final cooldown = RateLimitCooldown(
        now: () => now,
        jitterMilliseconds: () => 0,
      );
      RequestOptions request(
        String user, {
        String origin = 'https://hrms.test',
      }) => RequestOptions(
        path: '$origin/api/leave',
        headers: {'Authorization': 'Bearer ${_token(user)}'},
      );
      final a = request('a');
      cooldown.record(
        DioException(
          requestOptions: a,
          response: Response(
            requestOptions: a,
            statusCode: 429,
            data: {'rateLimitScope': 'api_read'},
            headers: Headers.fromMap({
              'retry-after': ['60'],
            }),
          ),
        ),
      );
      expect(cooldown.blocked(request('a')), isNotNull);
      final rotated = request('a');
      rotated.headers['Authorization'] =
          '${rotated.headers['Authorization']}-rotated';
      expect(cooldown.blocked(rotated), isNotNull);
      expect(cooldown.blocked(request('b')), isNull);
      expect(
        cooldown.blocked(request('a', origin: 'https://other.test')),
        isNull,
      );
      now = now.add(const Duration(seconds: 61));
      expect(cooldown.blocked(a), isNull);
    },
  );
  test(
    'HTTP-date Retry-After and malformed fallback produce bounded cooldowns',
    () {
      final now = DateTime.utc(2026, 10, 11, 10);
      final cooldown = RateLimitCooldown(
        now: () => now,
        jitterMilliseconds: () => 0,
      );
      final o = RequestOptions(path: '/api/employees');
      final error = cooldown.record(
        DioException(
          requestOptions: o,
          response: Response(
            requestOptions: o,
            statusCode: 429,
            data: {'rateLimitScope': 'api_read'},
            headers: Headers.fromMap({
              'retry-after': ['Sun, 11 Oct 2026 10:01:00 GMT'],
            }),
          ),
        ),
      );
      expect(error.response?.data['retryAfterSeconds'], 60);
      final fallback =
          RateLimitCooldown(now: () => now, jitterMilliseconds: () => 0).record(
            DioException(
              requestOptions: o,
              response: Response(
                requestOptions: o,
                statusCode: 429,
                data: {},
                headers: Headers.fromMap({
                  'retry-after': ['invalid'],
                }),
              ),
            ),
          );
      expect(fallback.response?.data['retryAfterSeconds'], 30);
    },
  );
  test(
    'assistant and unscoped endpoint limits do not freeze unrelated features',
    () {
      final cooldown = RateLimitCooldown(jitterMilliseconds: () => 0);
      final chat = RequestOptions(
        path: '/api/dtr-assistant/chat',
        method: 'POST',
      );
      final limited = cooldown.record(
        DioException(
          requestOptions: chat,
          response: Response(
            requestOptions: chat,
            statusCode: 429,
            data: {
              'error': 'Daghan ra kaayo ang imong chatbot requests.',
              'code': 'DTR_ASSISTANT_CHAT_BURST_LIMITED',
              'retryAfterSeconds': 60,
            },
          ),
        ),
      );
      expect(
        limited.response?.data['code'],
        'DTR_ASSISTANT_CHAT_BURST_LIMITED',
      );
      expect(limited.response?.data['error'], startsWith('Daghan'));
      expect(cooldown.blocked(chat), isNotNull);
      expect(
        cooldown.blocked(
          RequestOptions(path: '/api/leave/id/approve', method: 'POST'),
        ),
        isNull,
      );
      final endpoint = RequestOptions(path: '/api/employees');
      cooldown.record(
        DioException(
          requestOptions: endpoint,
          response: Response(
            requestOptions: endpoint,
            statusCode: 429,
            data: {},
          ),
        ),
      );
      expect(cooldown.blocked(endpoint), isNotNull);
      expect(
        cooldown.blocked(RequestOptions(path: '/api/departments')),
        isNull,
      );
    },
  );
}

String _token(String id) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'id': id}))).replaceAll('=', '')}.signature';
Future<DioException> _failure(Future<dynamic> Function() request) async {
  try {
    await request();
  } on DioException catch (e) {
    return e;
  }
  throw StateError('Expected rate-limit failure');
}

ResponseBody _json(int status, Map<String, dynamic> data, [String? retry]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        'content-type': ['application/json'],
        if (retry != null) 'retry-after': [retry],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}
