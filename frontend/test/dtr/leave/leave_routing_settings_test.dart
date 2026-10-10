import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_routing_settings.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
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
    await tester.tap(find.text('Department approval → Manual Mayor signing').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save routing'));
    await tester.pumpAndSettle();
    expect(saved!['approval_route'], 'mayor');
    expect(saved!['mayor_employment_types'], [
      'job_order',
      'contract_of_service',
    ]);
  });
}
