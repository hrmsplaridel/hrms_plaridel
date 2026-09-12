import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/shifts/pages/manage_shift.dart';

void main() {
  final requests = <RequestOptions>[];
  final handlers = <RequestInterceptorHandler>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handlers.add(handler);
        },
      ),
    );
  });

  setUp(() {
    requests.clear();
    handlers.clear();
  });

  void succeed(int index, {String? name}) {
    handlers[index].resolve(
      Response<List<dynamic>>(
        requestOptions: requests[index],
        data: [
          if (name != null)
            {
              'id': name,
              'name': name,
              'start_time': '08:00',
              'end_time': '17:00',
            },
        ],
      ),
    );
  }

  void fail(int index) {
    handlers[index].reject(
      DioException(
        requestOptions: requests[index],
        response: Response<dynamic>(
          requestOptions: requests[index],
          statusCode: 403,
          data: {'error': 'Access denied.'},
        ),
      ),
    );
  }

  Future<void> flushRequests(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageShift())),
      ),
    );
    await flushRequests(tester);
  }

  Future<void> select(WidgetTester tester, String status) async {
    final dropdown = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .firstWhere(
          (widget) => widget.items!.any((item) => item.value == 'All'),
        );
    dropdown.onChanged!(status);
    await flushRequests(tester);
  }

  testWidgets('older successes cannot replace the latest filter results', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'Inactive');
    await select(tester, 'All');
    expect(requests.map((r) => r.queryParameters['status']), [
      'Active',
      'Inactive',
      'All',
    ]);
    succeed(2, name: 'Latest shift');
    await tester.pumpAndSettle();
    succeed(1, name: 'Old inactive shift');
    succeed(0, name: 'Old active shift');
    await tester.pumpAndSettle();
    expect(find.text('Latest shift'), findsOneWidget);
    expect(find.text('Old inactive shift'), findsNothing);
    expect(find.text('Old active shift'), findsNothing);
  });

  testWidgets('stale failure cannot stop current loading or show an error', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'All');
    fail(0);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Access denied.'), findsNothing);
    succeed(1, name: 'Current shift');
    await tester.pumpAndSettle();
    expect(find.text('Current shift'), findsOneWidget);
  });

  testWidgets('failure hides old rows and Retry reloads the selected status', (
    tester,
  ) async {
    await mount(tester);
    succeed(0, name: 'Previously loaded');
    await tester.pumpAndSettle();
    await select(tester, 'Inactive');
    fail(1);
    await tester.pumpAndSettle();
    expect(find.text('Access denied.'), findsOneWidget);
    expect(find.text('No shifts'), findsNothing);
    expect(find.text('Previously loaded'), findsNothing);
    await tester.tap(find.text('Retry'));
    await flushRequests(tester);
    expect(requests.last.queryParameters['status'], 'Inactive');
    succeed(2);
    await tester.pumpAndSettle();
    expect(find.text('No shifts'), findsOneWidget);
    expect(find.text('Access denied.'), findsNothing);
  });

  testWidgets('completion after disposal does not update widget state', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    succeed(0, name: 'Late response');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
