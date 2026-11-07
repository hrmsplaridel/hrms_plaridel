import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

class _PendingRoster {
  _PendingRoster(this.options, this.handler);
  final RequestOptions options;
  final RequestInterceptorHandler handler;

  void succeed(String name, {int total = 1}) => handler.resolve(
    Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'employees': [
          {
            'id': name,
            'full_name': name,
            'biometric_user_id': '7',
            'employee_number': 7,
            'is_active': true,
          },
        ],
        'total': total,
      },
    ),
  );

  void fail({bool proxyHtml = false}) => handler.reject(
    DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: 502,
        data: proxyHtml
            ? '<html>Bad Gateway</html>'
            : {'error': 'Device connection timed out.'},
      ),
    ),
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final pending = <_PendingRoster>[];
  var rosterOpen = false;

  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    pending.clear();
    rosterOpen = false;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (rosterOpen && options.path == '/api/employees') {
            pending.add(_PendingRoster(options, handler));
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path == '/api/biometric-devices'
                  ? [
                      {
                        'id': 'offline',
                        'name': 'Offline clock',
                        'vendor': 'zkteco',
                      },
                      {'id': 'online', 'name': 'Testing', 'vendor': 'zkteco'},
                    ]
                  : <dynamic>[],
            ),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManageEmployee(canCreateAccount: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    rosterOpen = true;
    await tester.tap(find.text('Biometric roster'));
    await _flush(tester);
    expect(pending, hasLength(1));
  }

  Future<void> select(WidgetTester tester, String device) async {
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await _flush(tester);
    await tester.tap(find.text(device).last);
    await _flush(tester);
  }

  testWidgets(
    'old device failure cannot overwrite the selected device roster',
    (tester) async {
      await open(tester);
      pending[0].succeed('Initial employee');
      await _flush(tester);
      await select(tester, 'Offline clock');
      await select(tester, 'Testing');
      pending[2].succeed('Current employee');
      await _flush(tester);
      pending[1].fail();
      await _flush(tester);
      expect(find.text('Current employee'), findsOneWidget);
      expect(find.textContaining('timed out'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late device success cannot overwrite All devices results', (
    tester,
  ) async {
    await open(tester);
    pending[0].succeed('Initial employee');
    await _flush(tester);
    await select(tester, 'Testing');
    await select(tester, 'All devices (HRMS only)');
    expect(
      pending[2].options.queryParameters,
      isNot(contains('biometric_device_id')),
    );
    pending[2].succeed('All employees result');
    await _flush(tester);
    pending[1].succeed('Old device employee');
    await _flush(tester);
    expect(find.text('All employees result'), findsOneWidget);
    expect(find.text('Old device employee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'current error shows backend detail and Retry repeats current filters',
    (tester) async {
      await open(tester);
      pending[0].succeed('Initial employee');
      await _flush(tester);
      await select(tester, 'Testing');
      await tester.tap(find.text('Has ID'));
      await _flush(tester);
      pending[1].succeed('Outdated filter result');
      pending[2].fail();
      await _flush(tester);
      expect(
        find.textContaining('Device connection timed out.'),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      final query = Map<String, dynamic>.from(
        pending[2].options.queryParameters,
      );
      await tester.tap(find.text('Retry'));
      await _flush(tester);
      expect(pending[3].options.queryParameters, query);
      pending[3].succeed('Recovered employee');
      await _flush(tester);
      expect(find.text('Recovered employee'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('timed out'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search changes ignore a response during the debounce window', (
    tester,
  ) async {
    await open(tester);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search name, email, employee no., biometric ID…',
    );
    await tester.enterText(search, 'Maria');
    pending[0].succeed('Old search employee');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Old search employee'), findsNothing);
    await _flush(tester);
    expect(pending[1].options.queryParameters['q'], 'Maria');
    pending[1].succeed('Maria Employee');
    await _flush(tester);
    expect(find.text('Maria Employee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter switch invalidates a delayed next-page response', (
    tester,
  ) async {
    await open(tester);
    pending[0].succeed('First page employee', total: 51);
    await _flush(tester);
    await tester.tap(find.text('Next'));
    await _flush(tester);
    expect(pending[1].options.queryParameters['offset'], 50);
    await tester.tap(find.text('Missing ID'));
    await _flush(tester);
    expect(pending[2].options.queryParameters['offset'], 0);
    expect(pending[2].options.queryParameters['biometric_filter'], 'missing');
    pending[2].succeed('Current filter employee');
    await _flush(tester);
    pending[1].succeed('Old second page employee', total: 51);
    await _flush(tester);
    expect(find.text('Current filter employee'), findsOneWidget);
    expect(find.text('Old second page employee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'HTML gateway failure stays readable and offers retry on mobile',
    (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      pending[0].fail(proxyHtml: true);
      await _flush(tester);
      expect(
        find.textContaining('Server is temporarily unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('<html>'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing the dialog ignores pending responses', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Close'));
    await _flush(tester);
    pending[0].fail();
    await _flush(tester);
    expect(find.text('Biometric roster'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
