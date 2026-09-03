import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/positions/pages/manage_position.dart';

Map<String, dynamic> positionJson(int number, {String? name}) {
  return <String, dynamic>{
    'id': '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
    'position_number': number,
    'name': name ?? 'Position ${number.toString().padLeft(2, '0')}',
    'description': 'Position description $number',
    'department_id': '11111111-1111-4111-8111-111111111111',
    'department_name': 'Human Resources',
    'is_department_head': false,
    'department_head_periods': const <dynamic>[],
    'is_active': true,
    'can_permanently_delete': true,
    'deactivation_blockers': const <dynamic>[],
  };
}

void main() {
  final positionQueries = <Map<String, dynamic>>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/departments') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <dynamic>[
                  <String, dynamic>{
                    'id': '11111111-1111-4111-8111-111111111111',
                    'name': 'Human Resources',
                    'is_active': true,
                  },
                ],
              ),
            );
            return;
          }

          if (options.path == '/api/positions') {
            final query = Map<String, dynamic>.from(options.queryParameters);
            positionQueries.add(query);
            final search = (query['search']?.toString() ?? '').toLowerCase();
            final page = int.tryParse('${query['page']}') ?? 1;
            final all = search == 'clerk'
                ? <Map<String, dynamic>>[
                    positionJson(99, name: 'Payroll Clerk'),
                  ]
                : List<Map<String, dynamic>>.generate(
                    12,
                    (index) => positionJson(index + 1),
                  );
            final start = (page - 1) * 10;
            final items = start >= all.length
                ? <Map<String, dynamic>>[]
                : all.sublist(
                    start,
                    start + 10 > all.length ? all.length : start + 10,
                  );
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'items': items,
                  'pagination': <String, dynamic>{
                    'page': page,
                    'limit': 10,
                    'page_size': 10,
                    'total': all.length,
                    'page_count': (all.length + 9) ~/ 10,
                  },
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

  setUp(positionQueries.clear);

  testWidgets('uses server pages and debounced server search', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ManagePosition(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Position 01'), findsOneWidget);
    expect(find.text('Position 11'), findsNothing);
    expect(find.text('Showing 1-10 of 12'), findsOneWidget);
    expect(positionQueries.single['page'], '1');
    expect(positionQueries.single['limit'], '10');
    expect(positionQueries.single['paginated'], 'true');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Position 01'), findsNothing);
    expect(find.text('Position 11'), findsOneWidget);
    expect(find.text('Position 12'), findsOneWidget);
    expect(find.text('Showing 11-12 of 12'), findsOneWidget);
    expect(positionQueries.last['page'], '2');

    await tester.enterText(find.byType(TextField).first, 'Clerk');
    await tester.pump(const Duration(milliseconds: 299));
    expect(positionQueries.length, 2);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Payroll Clerk'), findsOneWidget);
    expect(find.text('Position 11'), findsNothing);
    expect(find.text('Showing 1-1 of 1'), findsOneWidget);
    expect(positionQueries.last['page'], '1');
    expect(positionQueries.last['search'], 'Clerk');
    expect(tester.takeException(), isNull);
  });
}
