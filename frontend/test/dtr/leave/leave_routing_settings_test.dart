import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_routing_settings.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  setUp(() => ApiClient.instance.dio.interceptors.clear());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  testWidgets('restricted direct Mayor description explains the HR fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LeaveRoutingSettings(
            allowDirectMayor: true,
            initialRoute: 'mayor_direct',
            initialEmploymentTypes: ['job_order'],
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Selected types: Mayor approves in the app; department and HR review are skipped. Other types: Department → Final HR.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Mayor approves in the app for all employment types. Department and HR review are skipped.',
      ),
      findsOneWidget,
    );
  });

  Future<void> mount(WidgetTester tester, {String? typeId = 'type'}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LeaveRoutingSettings(leaveTypeId: typeId)),
        ),
      );

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save routing'),
          )
          .onPressed !=
      null;

  testWidgets(
    'pending routing load blocks edits and saving until saved Mayor route arrives',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      final writes = <RequestOptions>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (o.method == 'POST') writes.add(o);
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: await response.future,
              ),
            );
          },
        ),
      );
      await mount(tester);
      await tester.pump();
      expect(saveEnabled(tester), false);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(find.text('Loading routing…'), findsOneWidget);
      response.complete({
        'approval_route': 'mayor',
        'mayor_employment_types': ['permanent'],
      });
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), true);
      expect(find.text('Permanent selected'), findsOneWidget);
      expect(writes, isEmpty);
    },
  );

  testWidgets(
    'failed load cannot save default HR; retry loads actual route and clears error',
    (tester) async {
      var fail = true;
      final writes = <Map>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'GET' && fail) {
              h.reject(
                DioException(
                  requestOptions: o,
                  response: Response(requestOptions: o, statusCode: 503),
                ),
              );
              return;
            }
            if (o.method == 'POST') writes.add(o.data as Map);
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'approval_route': 'mayor',
                  'mayor_employment_types': null,
                },
              ),
            );
          },
        ),
      );
      await mount(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load routing. Please retry.'),
        findsOneWidget,
      );
      expect(saveEnabled(tester), false);
      await tester.tap(find.text('Save routing'));
      await tester.pump();
      expect(writes, isEmpty);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load routing. Please retry.'), findsNothing);
      expect(saveEnabled(tester), true);
      await tester.tap(find.text('Save routing'));
      await tester.pumpAndSettle();
      expect(writes.single, {
        'approval_route': 'mayor',
        'mayor_employment_types': null,
      });
    },
  );

  testWidgets(
    'malformed routing response stays blocked rather than defaulting to HR',
    (tester) async {
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );
      await mount(tester);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), false);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'stale response from previous type cannot overwrite the current type or edits',
    (tester) async {
      final oldResponse = Completer<Map<String, dynamic>>();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: o.path.endsWith('/old')
                    ? await oldResponse.future
                    : {
                        'approval_route': 'mayor',
                        'mayor_employment_types': null,
                      },
              ),
            );
          },
        ),
      );
      await mount(tester, typeId: 'old');
      await tester.pump();
      // Reuse the widget state intentionally; parents need not rely on new keys for safety.
      await mount(tester, typeId: 'new');
      await tester.pumpAndSettle();
      expect(
        find.text('Department approval → Manual Mayor signing'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Department → Final HR').last);
      await tester.pumpAndSettle();
      oldResponse.complete({
        'approval_route': 'mayor',
        'mayor_employment_types': ['permanent'],
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'hr',
      );
      expect(find.text('Permanent selected'), findsNothing);
    },
  );

  testWidgets('new unsaved type is editable without a routing GET', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add(o);
          h.reject(DioException(requestOptions: o));
        },
      ),
    );
    await mount(tester, typeId: null);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNotNull,
    );
    expect(requests, isEmpty);
  });

  testWidgets(
    'retry after a save failure resends the draft instead of reloading and losing edits',
    (tester) async {
      var failSave = true;
      var loads = 0;
      final writes = <Map>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'GET') loads++;
            if (o.method == 'POST') {
              writes.add(o.data as Map);
              if (failSave) {
                h.reject(
                  DioException(
                    requestOptions: o,
                    response: Response(
                      requestOptions: o,
                      statusCode: 503,
                      data: {'error': 'Try saving again'},
                    ),
                  ),
                );
                return;
              }
            }
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'approval_route': 'mayor',
                  'mayor_employment_types': ['permanent'],
                },
              ),
            );
          },
        ),
      );
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Department → Final HR').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save routing'));
      await tester.pumpAndSettle();
      expect(find.text('Try saving again'), findsOneWidget);
      failSave = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(writes, [
        {'approval_route': 'hr', 'mayor_employment_types': null},
        {'approval_route': 'hr', 'mayor_employment_types': null},
      ]);
      expect(find.text('Try saving again'), findsNothing);
    },
  );
  testWidgets('Mayor route keeps the default HR route for unselected types', (
    tester,
  ) async {
    Map? saved;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (o.method == 'POST') saved = o.data as Map;
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {'approval_route': 'hr', 'mayor_employment_types': null},
            ),
          );
        },
      ),
    );
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LeaveRoutingSettings(leaveTypeId: 'type')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Department approval → Manual Mayor signing').last,
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Limit to employment types'), findsOneWidget);
    expect(find.text('JO, COS selected'), findsOneWidget);
    await tester.tap(find.text('JO, COS selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permanent'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save routing'));
    await tester.pumpAndSettle();
    expect(saved!['approval_route'], 'mayor');
    expect(saved!['mayor_employment_types'], [
      'job_order',
      'contract_of_service',
      'permanent',
    ]);
  });
}
