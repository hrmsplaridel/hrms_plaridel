import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/holidays/pages/manage_holiday.dart';

void main() {
  final requests = <RequestOptions>[];
  final handlers = <RequestInterceptorHandler>[];
  final year = DateTime.now().year;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/api/holidays') {
            handler.resolve(
              Response<List<dynamic>>(requestOptions: options, data: []),
            );
            return;
          }
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

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  void respond(int index, int selectedYear) {
    handlers[index].resolve(
      Response<Map<String, dynamic>>(
        requestOptions: requests[index],
        data: {
          'year': selectedYear,
          'supported_years': [year, year + 1],
          'holidays': [
            {
              'name': 'Holiday $selectedYear',
              'date_from': '$selectedYear-01-01',
              'date_to': '$selectedYear-01-01',
              'exists': false,
            },
          ],
        },
      ),
    );
  }

  Finder filledButton(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  FilledButton importButton(WidgetTester tester) =>
      tester.widget<FilledButton>(filledButton('Import 1'));

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ManageHoliday())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import PH Defaults'));
    await flush(tester);
    respond(0, year);
    await tester.pumpAndSettle();
  }

  Future<void> selectYear(WidgetTester tester, int selectedYear) async {
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .onChanged!(selectedYear);
    await flush(tester);
  }

  testWidgets(
    'year switch blocks old import callback and imports only the new preview',
    (tester) async {
      await open(tester);
      final oldImport = importButton(tester).onPressed!;
      await selectYear(tester, year + 1);
      expect(
        tester
            .widget<FilledButton>(filledButton('Nothing to import'))
            .onPressed,
        isNull,
      );
      oldImport();
      await flush(tester);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      respond(1, year + 1);
      await tester.pumpAndSettle();
      final submit = importButton(tester).onPressed!;
      submit();
      submit();
      await flush(tester);
      expect(requests.where((r) => r.method == 'POST').length, 1);
      expect(requests.last.data, {'year': year + 1});
      handlers.last.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: requests.last,
          data: {'created_count': 1, 'skipped_count': 0},
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed replacement preview cannot import the old year', (
    tester,
  ) async {
    await open(tester);
    await selectYear(tester, year + 1);
    handlers[1].reject(
      DioException(requestOptions: requests[1], message: 'Unavailable'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(filledButton('Nothing to import')).onPressed,
      isNull,
    );
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('an older preview response cannot replace the latest year', (
    tester,
  ) async {
    await open(tester);
    final changeYear = tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .onChanged!;
    changeYear(year + 1);
    await flush(tester);
    changeYear(year);
    await flush(tester);
    respond(2, year);
    await tester.pumpAndSettle();
    respond(1, year + 1);
    await tester.pumpAndSettle();
    expect(find.text('Holiday $year'), findsOneWidget);
    expect(find.text('Holiday ${year + 1}'), findsNothing);
    expect(importButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'mismatched response year is rejected instead of resetting selection',
    (tester) async {
      await open(tester);
      await selectYear(tester, year + 1);
      respond(1, year);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not match the selected year'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(filledButton('Nothing to import'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
