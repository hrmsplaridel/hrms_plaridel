import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/app/app.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await TokenStorage.instance.clearAllTokens();
  });

  test('temporary backend failure preserves the saved session', () async {
    await TokenStorage.instance.setTokens(
      access: 'saved-access-token',
      refresh: 'saved-refresh-token',
    );
    ApiClient.instance.dio.httpClientAdapter = _UnavailableAdapter();

    final result = await AuthProvider().restoreSession();

    expect(result, SessionRestoreResult.temporarilyUnavailable);
    expect(await TokenStorage.instance.getToken(), 'saved-access-token');
    expect(
      await TokenStorage.instance.getRefreshToken(),
      'saved-refresh-token',
    );
  });

  testWidgets('startup retries an unavailable saved session automatically', (
    tester,
  ) async {
    final auth = _RetryingAuthProvider();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MyApp(
        auth: auth,
        themeNotifier: ThemeModeNotifier(initial: ThemeMode.light),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('Waiting for the HRMS server').evaluate().isNotEmpty,
    );

    expect(auth.restoreCalls, 1);
    expect(find.text('Retry now'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(tester, () => auth.restoreCalls == 2);

    expect(auth.restoreCalls, 2);
    expect(find.text('Waiting for the HRMS server'), findsOneWidget);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 150,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  fail('Timed out waiting for the expected startup state.');
}

class _RetryingAuthProvider extends AuthProvider {
  int restoreCalls = 0;

  @override
  Future<SessionRestoreResult> restoreSession() async {
    restoreCalls += 1;
    return SessionRestoreResult.temporarilyUnavailable;
  }
}

class _UnavailableAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketExceptionForTest(),
    );
  }

  @override
  void close({bool force = false}) {}
}

class SocketExceptionForTest implements Exception {
  const SocketExceptionForTest();

  @override
  String toString() => 'Server unavailable';
}
