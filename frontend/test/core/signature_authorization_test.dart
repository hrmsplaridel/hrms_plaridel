import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    if (stream != null) await stream.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final multipart in [false, true]) {
    test(
      'confirmation retries the exact ${multipart ? 'multipart' : 'JSON'} request once',
      () async {
        final seen = <RequestOptions>[];
        final dio = Dio()
          ..httpClientAdapter = Adapter((options) {
            seen.add(options);
            final confirmed =
                options.headers['X-Signature-Authorization'] == 'proof';
            return ResponseBody.fromString(
              jsonEncode({'ok': confirmed}),
              confirmed ? 200 : 428,
              headers: {
                'content-type': ['application/json'],
                if (!confirmed) 'x-signature-challenge': ['challenge'],
              },
            );
          });
        final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())
          ..init();
        client.signingConfirmation = (challenge) async {
          expect(challenge, 'challenge');
          return 'proof';
        };
        final data = multipart
            ? FormData.fromMap({
                'reason': 'Meeting',
                'file': MultipartFile.fromBytes([
                  1,
                  2,
                  3,
                ], filename: 'file.png'),
              })
            : {'reason': 'Meeting'};
        final response = await client.post('/api/example/sign', data: data);
        expect(response.statusCode, 200);
        expect(seen.length, 2);
        expect(seen[0].headers['X-Signing-Request-Id'], isNotEmpty);
        expect(
          seen[1].headers['X-Signing-Request-Id'],
          seen[0].headers['X-Signing-Request-Id'],
        );
      },
    );
  }
  test(
    'cancelling confirmation does not retry or submit credentials',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter((_) {
          calls++;
          return ResponseBody.fromString(
            '{}',
            428,
            headers: {
              'content-type': ['application/json'],
              'x-signature-challenge': ['challenge'],
            },
          );
        });
      final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())..init();
      client.signingConfirmation = (_) async => null;
      await expectLater(
        client.post('/api/example/sign'),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    },
  );
}
