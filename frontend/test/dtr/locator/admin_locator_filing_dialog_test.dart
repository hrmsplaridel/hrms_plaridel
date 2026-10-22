import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/admin_locator_filing_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  setUp(() {
    requests.clear();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests.add(o);
          final data = o.path.endsWith('/filing-employees')
              ? {
                  'employees': [
                    {
                      'id': '11111111-1111-4111-8111-111111111111',
                      'full_name': 'Alice',
                      'department_name': 'HR',
                    },
                    {
                      'id': '22222222-2222-4222-8222-222222222222',
                      'full_name': 'Bob',
                      'department_name': 'HR',
                    },
                  ],
                  'total': 2,
                }
              : o.path.endsWith('/final-reviewer/me')
              ? {'can_review': false}
              : {
                  'results': [
                    {
                      'employee_id': '11111111-1111-4111-8111-111111111111',
                      'request': {'status': 'pending_department_head'},
                    },
                    {
                      'employee_id': '22222222-2222-4222-8222-222222222222',
                      'error': 'No working shift',
                    },
                  ],
                };
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
  });
  testWidgets(
    'staff filing submits selected employees and keeps only failed employees selected',
    (t) async {
      t.view.physicalSize = const Size(900, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: AdminLocatorFilingDialog(
            requestTypes: [LocatorRequestType.locator.copyWith(employeeDetailSchema:const[
              LeaveCustomFieldDefinition(key:'contact',label:'Contact person',required:true),
            ])],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Cover the full shift'), findsNothing);
      expect(find.text('Covered DTR slots'), findsOneWidget);
      expect(find.text('Locator Date'), findsOneWidget);
      for (final label in ['AM IN', 'AM OUT', 'PM IN', 'PM OUT']) {
        expect(find.widgetWithText(FilterChip, label), findsOneWidget);
      }
      expect(
        find.text(
          'Requests follow the normal department and HR approval route.',
        ),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextFormField).at(0), 'Municipal office');
      await t.enterText(find.byType(TextFormField).at(1), 'No electricity');
      await t.enterText(find.byType(TextFormField).at(2), 'Alice');
      await t.tap(find.text('Select loaded employees (up to 100)'));
      await t.pump();
      await t.tap(find.text('File requests'));
      await t.pumpAndSettle();
      expect(find.text('Select the covered time segments.'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await t.tap(find.widgetWithText(FilterChip, 'AM IN'));
      await t.tap(find.widgetWithText(FilterChip, 'AM OUT'));
      await t.tap(find.text('File requests'));
      await t.pumpAndSettle();
      expect(find.text('Created: pending_department_head'), findsOneWidget);
      expect(find.text('No working shift'), findsOneWidget);
      final summary = find.text('1 request filed successfully · 1 failed');
      expect(summary, findsOneWidget);
      expect(
        t.getRect(summary).bottom,
        lessThan(t.getRect(find.text('File requests')).top),
      );
      expect(
        find.text(
          'Failed employees remain selected. Review Filing results below before retrying.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 selected · 2 of 2 employees'), findsOneWidget);
      final post = requests.singleWhere((r) => r.method == 'POST');
      final fields = (post.data as FormData).fields.toMap();
      expect(jsonDecode(fields['additional_details']!),{'contact':'Alice'});
      expect(fields['employee_ids'], contains('11111111'));
      expect(fields['full_shift'], 'false');
      expect(fields['am_in'], 'true');
      expect(fields['am_out'], 'true');
      expect(fields['pm_in'], 'false');
      expect(fields['pm_out'], 'false');
      expect(fields.containsKey('signature'), isFalse);
    },
  );
  testWidgets('all slots retain full-shift coverage for mixed shifts', (
    t,
  ) async {
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      const MaterialApp(
        home: AdminLocatorFilingDialog(
          requestTypes: [LocatorRequestType.locator],
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), 'Municipal office');
    await t.enterText(find.byType(TextFormField).at(1), 'Power outage');
    await t.tap(find.text('Select loaded employees (up to 100)'));
    for (final label in ['AM IN', 'AM OUT', 'PM IN', 'PM OUT']) {
      await t.tap(find.widgetWithText(FilterChip, label));
      await t.pump();
    }
    await t.tap(find.text('File requests'));
    await t.pumpAndSettle();
    final fields =
        (requests.singleWhere((r) => r.method == 'POST').data as FormData)
            .fields
            .toMap();
    expect(fields['full_shift'], 'true');
    for (final slot in ['am_in', 'am_out', 'pm_in', 'pm_out']) {
      expect(fields[slot], 'true');
    }
  });
}

extension on List<MapEntry<String, String>> {
  Map<String, String> toMap() => Map.fromEntries(this);
}
