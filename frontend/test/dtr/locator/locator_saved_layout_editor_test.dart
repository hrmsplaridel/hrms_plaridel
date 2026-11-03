import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_settings.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  for (final custom in [false, true]) {
    testWidgets(
      'existing Locator opens its current ${custom ? 'custom' : 'built-in'} form and preserves it after saving',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? stored = custom
            ? LocatorPrintLayout(
                orientation: 'landscape',
                elements: const [
                  LocatorPrintElement(
                    id: 'saved-title',
                    kind: 'text',
                    text: 'SAVED LOCATOR',
                    x: 70,
                    y: 80,
                    width: 500,
                    height: 40,
                    fontSize: 20,
                  ),
                ],
              ).toJson()
            : null;
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.method == 'POST') {
                stored = Map<String, dynamic>.from(
                  jsonDecode(
                        (o.data as FormData).fields
                            .singleWhere((f) => f.key == 'print_layout')
                            .value,
                      )
                      as Map,
                );
              }
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'print_layout': stored,
                    'has_background': false,
                    'background_name': null,
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LocatorPrintSettings(
                typeId: 'existing',
                readRequestType: () => LocatorRequestType.locator,
                readWorkflowSteps: () => ['department', 'hr'],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(custom ? 'Edit layout' : 'Design layout'));
        await tester.pumpAndSettle();
        final editor = tester.widget<LocatorPrintLayoutEditor>(
          find.byType(LocatorPrintLayoutEditor),
        );
        final initial = editor.initialLayout;
        expect(
          initial,
          isNotNull,
          reason: 'An existing form must not fall back to the generic starter.',
        );
        expect(initial!.orientation, 'landscape');
        expect(initial.validate(), isNull);
        if (custom) {
          expect(initial.toJson(), stored);
        } else {
          expect(initial.baseForm, 'locator');
          expect(editor.backgroundPdf, isNotEmpty);
          expect(
            initial.elements
                .where((e) => e.kind == 'signature')
                .map((e) => e.source),
            containsAll(['applicant', 'department_head', 'hr_approver']),
          );
        }
        await tester.tap(find.text('Use layout'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save print settings'));
        await tester.pumpAndSettle();
        expect(stored, initial.toJson());
        await tester.tap(find.text('Edit layout'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LocatorPrintLayoutEditor>(
                find.byType(LocatorPrintLayoutEditor),
              )
              .initialLayout!
              .toJson(),
          stored,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
