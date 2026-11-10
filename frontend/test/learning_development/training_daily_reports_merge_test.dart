import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/sections/ld_training_daily_reports_section.dart';

Map<String, dynamic> report(String id, String name, {bool reviewed = false}) =>
    {
      'id': id,
      'employee_id': 'employee-$id',
      'employee_name': name,
      'title': 'Training $id',
      'submitted_at': '2026-11-10T01:00:00Z',
      'status': reviewed ? 'reviewed' : 'submitted',
      if (reviewed) ...{
        'seen_by_admin': 'admin',
        'reviewed_by': 'admin',
        'seen_at': '2026-11-10T02:00:00Z',
      },
    };

void main() {
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LdTrainingDailyReportsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('review filters and bulk seen update only unreviewed reports', (
    tester,
  ) async {
    final reports = [report('a', 'Alice'), report('b', 'Bob', reviewed: true)];
    final marked = <String>[];
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'PATCH') {
            final id = options.path.split('/').reversed.skip(1).first;
            marked.add(id);
            final index = reports.indexWhere((row) => row['id'] == id);
            reports[index] = report(
              id,
              reports[index]['employee_name'] as String,
              reviewed: true,
            );
            handler.resolve(
              Response(
                requestOptions: options,
                data: reports[index],
                statusCode: 200,
              ),
            );
          } else {
            handler.resolve(
              Response(requestOptions: options, data: reports, statusCode: 200),
            );
          }
        },
      ),
    );
    await mount(tester);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.text('1 Reviewed'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.text('1 Unreviewed'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    await tester.tap(find.text('Mark visible as seen (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark all'));
    await tester.pumpAndSettle();
    expect(marked, ['a']);
    expect(find.text('0 Unreviewed'), findsOneWidget);
    expect(find.text('2 Reviewed'), findsOneWidget);
    expect(find.text('Marked 1 report as seen.'), findsOneWidget);
  });

  testWidgets(
    'a delayed older search cannot replace the latest search results',
    (tester) async {
      final older = Completer<void>();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final search = options.queryParameters['search'];
            if (search == 'Alice') await older.future;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: search == 'Alice'
                    ? [report('a', 'Alice')]
                    : [report('b', 'Bob')],
              ),
            );
          },
        ),
      );
      await mount(tester);
      final search = find.byType(TextField);
      await tester.enterText(search, 'Alice');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(search, 'Bob');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.text('Bob'),
        findsNWidgets(2),
      ); // Search text and employee name.
      older.complete();
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
