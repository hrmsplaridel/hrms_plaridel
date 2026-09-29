import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_bridge.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ApiClient.instance.init);

  setUp(() {
    LocatorSlipDataCache.instance.invalidateAll();
    ApiClient.instance.dio.interceptors.clear();
  });

  tearDown(() {
    LocatorSlipDataCache.instance.invalidateAll();
    ApiClient.instance.dio.interceptors.clear();
  });

  testWidgets('locator type event invalidates the global type cache', (
    tester,
  ) async {
    final adapter = _LocatorTypeAdapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;

    await LocatorSlipDataCache.instance.listTypes();
    await LocatorSlipDataCache.instance.listTypes();
    expect(adapter.requestCount, 1);

    final realtime = _FakeRealtimeProvider();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRealtimeProvider>.value(
        value: realtime,
        child: const AppRealtimeBridge(child: SizedBox()),
      ),
    );

    realtime.emit(
      const AppRealtimeEvent(
        name: 'locator_type_updated',
        payload: {'action': 'updated', 'code': 'locator'},
      ),
    );
    await tester.pump();

    await LocatorSlipDataCache.instance.listTypes();
    expect(adapter.requestCount, 2);

    await tester.pumpWidget(const SizedBox());
  });
}

class _LocatorTypeAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'GET');
    expect(options.uri.path, '/api/locator-slips/types');
    requestCount += 1;
    return ResponseBody.fromString(
      jsonEncode(const [
        {
          'code': 'locator',
          'label': 'Locator / Official Business',
          'is_active': true,
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeRealtimeProvider extends AppRealtimeProvider {
  final _events = StreamController<AppRealtimeEvent>.broadcast();

  @override
  Stream<AppRealtimeEvent> get events => _events.stream;

  void emit(AppRealtimeEvent event) => _events.add(event);

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
