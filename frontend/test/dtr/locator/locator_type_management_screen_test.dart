import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/locator_type_management_screen.dart';

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

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LocatorTypeManagementScreen())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterRequiredFields(WidgetTester tester) async {
    await tester.enterText(textField('System code'), 'remote_work');
    await tester.enterText(textField('Request type name'), 'Remote Work');
    await tester.enterText(textField('Short display name'), 'Remote');
    await tester.enterText(textField('DTR display text'), 'Remote');
    await tester.enterText(textField('DTR print text'), 'REMOTE');
  }

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
}
