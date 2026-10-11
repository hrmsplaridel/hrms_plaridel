import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ClientDeviceHeader.build();
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await TokenStorage.instance.setTokens(
      access: 'old-access',
      refresh: 'saved-refresh',
    );
  });
  for (final status in [429, 500, 503, 401, 403]) {
    test(
      'refresh $status ${status == 401 || status == 403 ? 'invalidates' : 'preserves'} the session',
      () async {
        final requests = Dio()
          ..httpClientAdapter = _Adapter(
            (_) async => _json(401, {'error': 'Expired access'}),
          );
        var refreshCalls = 0;
        final refresh = Dio()
          ..httpClientAdapter = _Adapter((_) async {
            refreshCalls++;
            return _json(
              status,
              {'error': 'Refresh failed'},
              headers: {
                'retry-after': ['60'],
              },
            );
          });
        final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
          ..init();
        final error = await _failure(client);
        final invalid = status == 401 || status == 403;
        expect(
          await TokenStorage.instance.getToken(),
          invalid ? isNull : 'old-access',
        );
        expect(
          await TokenStorage.instance.getRefreshToken(),
          invalid ? isNull : 'saved-refresh',
        );
        expect(error.response?.statusCode, invalid ? 401 : status);
        if (!invalid) {
          await _failure(client);
          expect(refreshCalls, 1);
        }
      },
    );
  }
  test(
    'refresh timeout preserves credentials and propagates a temporary error',
    () async {
      final requests = Dio()
        ..httpClientAdapter = _Adapter((_) async => _json(401, {}));
      final refresh = Dio()
        ..httpClientAdapter = _Adapter(
          (o) async => throw DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
          ),
        );
      final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
        ..init();
      expect((await _failure(client)).type, DioExceptionType.receiveTimeout);
      expect(await TokenStorage.instance.getRefreshToken(), 'saved-refresh');
    },
  );
  test(
    'concurrent access failures share refresh and retry with rotated credentials',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final requests = Dio()
        ..httpClientAdapter = _Adapter(
          (o) async => o.headers['Authorization'] == 'Bearer new-access'
              ? _json(200, {'ok': true})
              : _json(401, {}),
        );
      final refresh = Dio()
        ..httpClientAdapter = _Adapter((_) async {
          calls++;
          await gate.future;
          return _json(200, {
            'token': 'new-access',
            'refreshToken': 'new-refresh',
          });
        });
      final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
        ..init();
      final first = client.get('/api/a'), second = client.get('/api/b');
      while (calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      expect(
        (await Future.wait([first, second])).every((r) => r.statusCode == 200),
        isTrue,
      );
      expect(calls, 1);
      expect(await TokenStorage.instance.getRefreshToken(), 'new-refresh');
    },
  );
  test('refresh can recover after its Retry-After cooldown', () async {
    var calls = 0;
    final requests = Dio()
      ..httpClientAdapter = _Adapter(
        (o) async => o.headers['Authorization'] == 'Bearer new-access'
            ? _json(200, {})
            : _json(401, {}),
      );
    final refresh = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        calls++;
        return calls == 1
            ? _json(
                429,
                {},
                headers: {
                  'retry-after': ['1'],
                },
              )
            : _json(200, {
                'token': 'new-access',
                'refreshToken': 'new-refresh',
              });
      });
    final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
      ..init();
    await _failure(client);
    await _failure(client);
    expect(calls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect((await client.get('/auth/me')).statusCode, 200);
    expect(calls, 2);
  });
  test('malformed refresh success preserves the previous session', () async {
    final requests = Dio()
      ..httpClientAdapter = _Adapter((_) async => _json(401, {}));
    final refresh = Dio()
      ..httpClientAdapter = _Adapter(
        (_) async => _json(200, {'token': 'incomplete-access'}),
      );
    final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
      ..init();
    expect((await _failure(client)).response?.statusCode, 502);
    expect(await TokenStorage.instance.getToken(), 'old-access');
    expect(await TokenStorage.instance.getRefreshToken(), 'saved-refresh');
  });
  test(
    'a successful late refresh does not resurrect a signed-out session',
    () async {
      final started = Completer<void>(), gate = Completer<void>();
      final requests = Dio()
        ..httpClientAdapter = _Adapter((_) async => _json(401, {}));
      final refresh = Dio()
        ..httpClientAdapter = _Adapter((_) async {
          started.complete();
          await gate.future;
          return _json(200, {
            'token': 'new-access',
            'refreshToken': 'new-refresh',
          });
        });
      final client = ApiClient.forTesting(dio: requests, refreshDio: refresh)
        ..init();
      final failure = _failure(client);
      await started.future;
      await TokenStorage.instance.clearAllTokens();
      gate.complete();
      expect((await failure).type, DioExceptionType.cancel);
      expect(await TokenStorage.instance.getToken(), isNull);
      expect(await TokenStorage.instance.getRefreshToken(), isNull);
    },
  );
}

Future<DioException> _failure(ApiClient client) async {
  try {
    await client.get('/auth/me');
  } on DioException catch (e) {
    return e;
  }
  throw StateError('Expected a request failure');
}

ResponseBody _json(
  int status,
  Map<String, dynamic> data, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    'content-type': ['application/json'],
    ...headers,
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}
