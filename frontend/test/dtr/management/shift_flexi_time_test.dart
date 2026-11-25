import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/shifts/pages/manage_shift.dart';

void main() {
  final mutations = <RequestOptions>[];
  var shifts = <Map<String, dynamic>>[];

  const flexiShift = {
    'id': 'flexi-shift',
    'name': 'Flexi shift',
    'start_time': '07:00:00',
    'end_time': '16:00:00',
    'break_start': '12:00:00',
    'break_end': '13:00:00',
    'punch_mode': 'full_day',
    'grace_period_minutes': 0,
    'flexi_latest_start': '09:30:00',
    'working_days': [1, 2, 3, 4, 5],
    'is_active': true,
  };
  final fixedShift = <String, dynamic>{
    ...flexiShift,
    'id': 'fixed-shift',
    'name': 'Fixed shift',
    'flexi_latest_start': null,
  };

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET' && options.path == '/api/shifts') {
            handler.resolve(
              Response<List<dynamic>>(requestOptions: options, data: shifts),
            );
          } else if (options.method == 'POST' || options.method == 'PUT') {
            mutations.add(options);
            handler.resolve(
              Response<Map<String, dynamic>>(requestOptions: options, data: {}),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
  });

  setUp(() {
    mutations.clear();
    shifts = [flexiShift, fixedShift];
  });

  final toggle = find.byKey(const ValueKey('shift-flexi-toggle'));

  Future<void> openShift(WidgetTester tester, String name) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageShift())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.ensureVisible(toggle);
  }

  Future<Map<String, dynamic>> update(WidgetTester tester) async {
    await tester.tap(find.text('Update').last);
    await tester.pumpAndSettle();
    expect(mutations, hasLength(1));
    return Map<String, dynamic>.from(mutations.single.data as Map);
  }

  testWidgets('list shows the arrival window of a flexi shift', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageShift())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Flexi until 9:30 AM'), findsOneWidget);
  });

  testWidgets('editing a flexi shift keeps its latest arrival', (tester) async {
    await openShift(tester, 'Flexi shift');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('Latest Arrival'), findsOneWidget);
    final body = await update(tester);
    expect(body['flexi_latest_start'], '09:30:00');
  });

  testWidgets('turning flexi time off clears the latest arrival', (
    tester,
  ) async {
    await openShift(tester, 'Flexi shift');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Latest Arrival'), findsNothing);
    final body = await update(tester);
    expect(body.containsKey('flexi_latest_start'), isTrue);
    expect(body['flexi_latest_start'], isNull);
  });

  testWidgets('enabling flexi time requires a latest arrival', (tester) async {
    await openShift(tester, 'Fixed shift');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Latest Arrival'), findsOneWidget);
    await tester.tap(find.text('Update').last);
    await tester.pumpAndSettle();
    expect(mutations, isEmpty);
    expect(find.text('Set the Latest Arrival time.'), findsOneWidget);
  });
}
