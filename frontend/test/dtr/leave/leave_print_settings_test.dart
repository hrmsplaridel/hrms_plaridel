import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  testWidgets(
    'print layout can be saved independently of protected filing rules',
    (tester) async {
      ApiClient.instance.dio.interceptors.clear();
      FormData? sent;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'POST') sent = o.data as FormData;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'layout': sent == null ? 'csc' : 'wellness',
                  'has_background': false,
                },
              ),
            );
          },
        ),
      );
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LeavePrintSettings(leaveTypeId: 'type')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wellness Leave form').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save print settings'));
      await tester.pumpAndSettle();
      expect(
        sent!.fields.firstWhere((f) => f.key == 'layout').value,
        'wellness',
      );
      expect(
        sent!.fields.any(
          (f) => f.key == 'max_days' || f.key == 'eligible_employment_types',
        ),
        isFalse,
      );
    },
  );
}
