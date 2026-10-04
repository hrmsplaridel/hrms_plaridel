import 'dart:async';

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
    var requestCount = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.method, 'GET');
          expect(options.uri.path, '/api/locator-slips/types');
          requestCount += 1;
          handler.resolve(
            Response(
              requestOptions: options,
              data: const [
                {
                  'code': 'locator',
                  'label': 'Locator / Official Business',
                  'is_active': true,
                },
              ],
            ),
          );
        },
      ),
    );

    await tester.runAsync(() async {
      await LocatorSlipDataCache.instance.listTypes();
      await LocatorSlipDataCache.instance.listTypes();
    });
    expect(requestCount, 1);

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

    await tester.runAsync(LocatorSlipDataCache.instance.listTypes);
    expect(requestCount, 2);

    await tester.pumpWidget(const SizedBox());
  });
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
