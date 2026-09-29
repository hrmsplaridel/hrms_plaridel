import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/locator_type_management_screen.dart';
import 'package:provider/provider.dart';

void main() {
  final requests = <RequestOptions>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
  });

  setUp(() {
    requests.clear();
    LocatorSlipDataCache.instance.invalidateTypes();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.method == 'GET' &&
              options.path ==
                  '/api/locator-slips/types?include_inactive=true') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const [],
              ),
            );
            return;
          }
          if (options.method == 'POST' &&
              options.path == '/api/locator-slips/types') {
            final data = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 201,
                data: {
                  ...data,
                  'id': '11111111-1111-4111-8111-111111111111',
                  'is_system': false,
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 404,
              ),
            ),
          );
        },
      ),
    );
  });

  tearDown(() {
    LocatorSlipDataCache.instance.invalidateTypes();
    ApiClient.instance.dio.interceptors.clear();
  });

  Finder textField(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

  Finder coverageDropdown() => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Time coverage behavior',
  );

  Future<_FakeRealtimeProvider> mount(
    WidgetTester tester, {
    _FakeRealtimeProvider? realtime,
  }) async {
    final provider = realtime ?? _FakeRealtimeProvider();
    addTearDown(provider.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRealtimeProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: LocatorTypeManagementScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> enterRequiredFields(WidgetTester tester) async {
    await tester.enterText(textField('System code'), 'remote_work');
    await tester.enterText(textField('Request type name'), 'Remote Work');
    await tester.enterText(textField('Short display name'), 'Remote');
    await tester.enterText(textField('DTR display text'), 'Remote');
    await tester.enterText(textField('DTR print text'), 'REMOTE');
  }

  testWidgets(
    'empty API result stays empty instead of showing local defaults',
    (tester) async {
      await mount(tester);

      expect(find.text('0 locator types'), findsOneWidget);
      expect(find.text('No locator types configured'), findsOneWidget);
      expect(find.text('Locator / Official Business'), findsNothing);
      expect(find.text('Pass Slip'), findsNothing);
      expect(find.text('Create Type'), findsOneWidget);
    },
  );

  testWidgets('catalog load failure stays visible and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            attempts += 1;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 503,
                    data: const {'error': 'Catalog unavailable'},
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const [],
              ),
            );
          },
        ),
      );

    await mount(tester);

    expect(find.text('Could not load locator types'), findsOneWidget);
    expect(find.text('Catalog unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Could not load locator types'), findsNothing);
    expect(find.text('No locator types configured'), findsOneWidget);
  });

  testWidgets('invalid sort order blocks creation before the API call', (
    tester,
  ) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('Sort order'), '1.5');

    await tester.tap(find.text('Create Type'));
    await tester.pump();

    expect(
      find.text('Sort order must be a whole number from 0 to 2147483647'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });

  testWidgets('valid rules are sent without normalization', (tester) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('Sort order'), '30');
    tester
        .widget<DropdownButtonFormField<String>>(coverageDropdown())
        .onChanged!('wfh');
    await tester.pump();

    await tester.tap(find.text('Create Type'));
    await tester.pumpAndSettle();

    final post = requests.singleWhere((request) => request.method == 'POST');
    final data = Map<String, dynamic>.from(post.data as Map);
    expect(data['sort_order'], 30);
    expect(data['coverage_mode'], 'wfh');
    expect(find.text('Locator type added.'), findsOneWidget);
  });

  testWidgets('invalid code and oversized text block creation', (tester) async {
    await mount(tester);
    await enterRequiredFields(tester);
    await tester.enterText(textField('System code'), 'a');
    await tester.enterText(
      textField('Request type name'),
      List<String>.filled(101, 'x').join(),
    );

    await tester.tap(find.text('Create Type'));
    await tester.pump();

    expect(
      find.text('Use 2-64 letters, numbers, underscores, or hyphens'),
      findsOneWidget,
    );
    expect(
      find.text('Request type name must be 100 characters or less'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
  });

  testWidgets('remote locator type event refreshes the visible catalog', (
    tester,
  ) async {
    final realtime = await mount(tester);
    final before = requests
        .where(
          (request) =>
              request.method == 'GET' &&
              request.path == '/api/locator-slips/types?include_inactive=true',
        )
        .length;

    realtime.emit(
      const AppRealtimeEvent(
        name: 'locator_type_updated',
        payload: {'action': 'updated', 'code': 'remote_work'},
      ),
    );
    await tester.pumpAndSettle();

    final after = requests
        .where(
          (request) =>
              request.method == 'GET' &&
              request.path == '/api/locator-slips/types?include_inactive=true',
        )
        .length;
    expect(after, greaterThan(before));
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
