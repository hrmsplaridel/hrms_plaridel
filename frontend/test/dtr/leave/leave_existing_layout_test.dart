import 'dart:convert';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test('leave field menu includes only common and selected-type details', () {
    final study = leaveLayoutFields(
      const LeaveTypeDefinition(name: 'studyLeave', displayName: 'Study Leave'),
    );
    expect(study, contains('study_purpose'));
    expect(study, contains('study_purpose_details'));
    expect(study, isNot(contains('sick_illness_details')));
    expect(study, isNot(contains('maternity_delivery_type')));
    final custom = leaveLayoutFields(
      const LeaveTypeDefinition(
        name: 'eLeave',
        displayName: 'Earl leave',
        employeeDetailSchema: [
          LeaveCustomFieldDefinition(key: 'destination', label: 'Destination'),
        ],
      ),
    );
    expect(custom, contains('custom:destination'));
    expect(custom, isNot(contains('adoption_parent_role')));
    expect(custom, isNot(contains('sick_leave_nature')));
    expect(
      leaveLayoutFields(
        const LeaveTypeDefinition(
          name: 'paternityLeave',
          displayName: 'Paternity',
        ),
      ),
      contains('child_delivery_date'),
    );
    expect(
      leaveLayoutFields(
        const LeaveTypeDefinition(
          name: 'specialPrivilegeLeave',
          displayName: 'Privilege',
        ),
      ),
      contains('location_details'),
    );
    expect(
      leaveLayoutFields(
        const LeaveTypeDefinition(
          name: 'maternityLeave',
          displayName: 'Maternity',
        ),
      ),
      isNot(contains('child_delivery_date')),
    );
  });
  test(
    'native forms retain structure, live data, signatures and moved fields after conversion',
    () async {
      const type = LeaveTypeDefinition(
        name: 'vacationLeave',
        displayName: 'Vacation Leave',
      );
      final request = leaveLayoutSampleRequest(type).copyWith(
        employeeName: 'Maria Test Santos',
        officeDepartment: 'Finance',
        workingDaysApplied: 3,
      );
      for (final form in ['csc', 'wellness']) {
        final imported = await importLeaveNativeLayout(type, form);
        expect(imported.layout.validate(), isNull);
        expect(imported.layout.baseForm, form);
        final fitted = imported.layout.withPageSettings();
        for (final item in imported.layout.elements.where(
          (e) => e.kind == 'signature',
        )) {
          expect(
            fitted.elements.firstWhere((e) => e.id == item.id).height,
            closeTo(item.height, .001),
          );
        }
        expect(
          imported.layout.elements.where((e) => e.kind == 'signature').length,
          form == 'csc' ? 4 : 3,
        );
        final roundtrip = LocatorPrintLayout.fromJson(imported.layout.toJson());
        expect(roundtrip.toJson(), imported.layout.toJson());
        final name = roundtrip.elements.firstWhere(
          (e) =>
              e.source ==
              (form == 'csc' ? 'employee_last_name' : 'employee_name'),
        );
        final moved = roundtrip.copyWith(
          elements: [
            for (final e in roundtrip.elements)
              e.id == name.id ? e.copyWith(x: e.x + 12) : e,
          ],
        );
        final bytes = await buildLeaveLayoutPdf(
          layout: moved,
          request: request,
          balances: const [
            LeaveBalance(
              userId: 'sample',
              leaveType: LeaveType.vacationLeave,
              earnedDays: 12,
            ),
          ],
          signatories: const LocatorFormSignatories(
            applicant: LocatorPrintedSignatory(name: 'Maria Test Santos'),
            departmentHead: LocatorPrintedSignatory(
              name: 'Department Reviewer',
            ),
            finalApprover: LocatorPrintedSignatory(name: 'Final Reviewer'),
          ),
          certificationOfficer: const LocatorPrintedSignatory(
            name: 'Credit Certifier',
          ),
        );
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length,
          1,
        );
      }
      final letterhead = await importLeaveNativeLayout(
        type,
        'csc',
        letterhead: true,
      );
      expect(letterhead.layout.paperSize, 'a4');
      expect(letterhead.layout.validate(), isNull);
      final a4 = await buildLeaveLayoutPdf(
        layout: letterhead.layout,
        request: request,
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(a4)).length,
        1,
      );
    },
  );
  for (final form in ['csc', 'wellness', 'custom']) {
    testWidgets(
      'existing $form starts from its current layout without saving on open',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1500, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const saved = LocatorPrintLayout(
          elements: [
            LocatorPrintElement(
              id: 'saved',
              kind: 'field',
              source: 'employee_name',
              label: 'Name',
              x: 85,
              y: 215,
              width: 320,
              height: 70,
              fontSize: 18,
            ),
          ],
        );
        final writes = <RequestOptions>[];
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.method != 'GET') writes.add(o);
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'layout': form,
                    'print_layout': form == 'custom' ? saved.toJson() : null,
                    'has_background': false,
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LeavePrintSettings(
                leaveTypeId: 'existing',
                readLeaveType: () => const LeaveTypeDefinition(
                  name: 'eLeave',
                  displayName: 'Earl leave',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(form == 'custom' ? 'Edit layout' : 'Design layout'),
        );
        await tester.pumpAndSettle();
        final editor = tester.widget<LocatorPrintLayoutEditor>(
          find.byType(LocatorPrintLayoutEditor),
        );
        expect(editor.initialLayout, isNotNull);
        if (form == 'custom') {
          expect(editor.initialLayout!.toJson(), saved.toJson());
        } else {
          expect(
            editor.initialLayout!.paperSize,
            form == 'csc' ? 'legal' : 'a4',
          );
          expect(
            editor.initialLayout!.elements.any((e) => e.source == 'applicant'),
            true,
          );
          expect(
            editor.initialLayout!.elements.any(
              (e) => e.source == 'department_head',
            ),
            true,
          );
          expect(
            editor.initialLayout!.elements.any(
              (e) => e.source == 'certification_officer',
            ),
            form == 'csc',
          );
          expect(editor.backgroundPdf, isNotNull);
        }
        expect(writes, isEmpty);
      },
    );
  }
  testWidgets(
    'failed metadata load cannot replace an existing design with defaults',
    (tester) async {
      ApiClient.instance.dio.interceptors.clear();
      var fail = true;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (fail) {
              h.reject(DioException(requestOptions: o));
            } else {
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {'layout': 'csc', 'has_background': false},
                ),
              );
            }
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LeavePrintSettings(leaveTypeId: 'existing')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Design layout'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save print settings'),
            )
            .onPressed,
        isNull,
      );
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Design layout'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
