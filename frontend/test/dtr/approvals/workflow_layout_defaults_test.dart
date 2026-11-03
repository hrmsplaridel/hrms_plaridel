import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/leave_print_settings.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_layout_pdf.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_settings.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/locator_print_layout_editor.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/utils/workflow_print_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oneStep = [
    {
      'label': 'First Step',
      'assignee_source': 'specific_users',
      'user_ids': ['primary', 'backup'],
    },
  ];
  final type = LocatorRequestType.locator;
  const leaveType = LeaveTypeDefinition(
    name: 'customLeave',
    displayName: 'Custom Leave',
  );

  test(
    'one review group yields one approver block, not one per primary/backup',
    () {
      final result = workflowPrintLayoutDefaults(
        LocatorPrintLayout.defaults(type),
        oneStep,
      );
      expect(
        result.elements
            .where((e) => e.kind == 'signature')
            .map((e) => e.source),
        ['applicant', 'hr_approver'],
      );
      expect(workflowPrintCaption(oneStep, 'hr_approver'), 'First Step');
      expect(result.validate(), isNull);
      final leave = workflowPrintLayoutDefaults(
        leavePrintLayoutDefaults(leaveType),
        oneStep,
      );
      expect(
        leave.elements.where((e) => e.kind == 'signature').map((e) => e.source),
        ['applicant', 'hr_approver'],
      );
    },
  );
  test(
    'department-only, Mayor-only and manual signing keep their correct slots',
    () {
      expect(workflowPrintSignatures(['department']).keys, [
        'applicant',
        'department_head',
      ]);
      expect(workflowPrintSignatures(['mayor']).keys, [
        'applicant',
        'hr_approver',
      ]);
      expect(workflowPrintSignatures(['department', 'manual_mayor']).keys, [
        'applicant',
        'department_head',
        'hr_approver',
      ]);
      expect(
        workflowPrintCaption(['department', 'manual_mayor'], 'hr_approver'),
        'Manual Mayor Signing',
      );
    },
  );
  test(
    'middle steps have unique slots and 20-step defaults stay inside either page',
    () {
      final mixed = [
        oneStep.first,
        {'label': 'Second Step', 'assignee_source': 'specific_users'},
        {'label': 'Mayor', 'assignee_source': 'active_mayor'},
      ];
      expect(workflowPrintSignatures(mixed).keys, [
        'applicant',
        'department_head',
        'workflow_step_2',
        'hr_approver',
      ]);
      for (final orientation in ['portrait', 'landscape']) {
        for (final count in [1, 2, 3, 6, 20]) {
          final steps = List.generate(
            count,
            (i) => {
              'label': 'Step ${i + 1}',
              'assignee_source': 'specific_users',
            },
          );
          for (final base in [
            LocatorPrintLayout.defaults(type, orientation: orientation),
            leavePrintLayoutDefaults(leaveType, orientation: orientation),
          ]) {
            final result = workflowPrintLayoutDefaults(base, steps);
            expect(
              result.elements.where((e) => e.kind == 'signature').length,
              count + 1,
            );
            expect(
              result.validate(),
              isNull,
              reason: '$count steps in $orientation',
            );
            final boxes = result.elements
                .where((e) => e.kind == 'signature')
                .toList();
            for (var i = 0; i < boxes.length; i++) {
              for (final other in boxes.skip(i + 1)) {
                final box = boxes[i];
                expect(
                  box.x + box.width <= other.x + .01 ||
                      other.x + other.width <= box.x + .01 ||
                      box.y + box.height <= other.y + .01 ||
                      other.y + other.height <= box.y + .01,
                  isTrue,
                );
              }
            }
          }
        }
      }
    },
  );
  test(
    'maximum workflow and custom-field counts fit without dropping answers',
    () {
      final fields = List.generate(
        20,
        (i) => LeaveCustomFieldDefinition(
          key: 'extra_$i',
          label: 'Extra field $i',
        ),
      );
      final steps = List.generate(
        20,
        (i) => {'label': 'Step ${i + 1}', 'assignee_source': 'specific_users'},
      );
      for (final orientation in ['portrait', 'landscape']) {
        for (final base in [
          LocatorPrintLayout.defaults(
            type.copyWith(employeeDetailSchema: fields),
            orientation: orientation,
          ),
          leavePrintLayoutDefaults(
            leaveType.copyWith(employeeDetailSchema: fields),
            orientation: orientation,
          ),
        ]) {
          final result = workflowPrintLayoutDefaults(base, steps);
          expect(result.validate(), isNull);
          expect(
            result.elements.where((e) => e.kind == 'signature').length,
            21,
          );
          expect(
            result.elements.where((e) => e.source.startsWith('custom:')).length,
            20,
          );
        }
      }
    },
  );
  test(
    'unknown workflow retains legacy defaults and native CSC retains its official fields',
    () {
      final base = LocatorPrintLayout.defaults(type);
      expect(workflowPrintLayoutDefaults(base, null), same(base));
      final native = leavePrintLayoutDefaults(
        leaveType,
      ).copyWith(baseForm: 'csc');
      expect(workflowPrintLayoutDefaults(native, oneStep), same(native));
    },
  );

  Map<String, dynamic> payload({
    String status = 'approved',
    int revision = 2,
    String actor = 'middle',
  }) => {
    'source_status': status,
    'source_revision': revision,
    'print_signatories': {
      'hr_approver': {
        'name': 'Final signer',
        'signature_image_base64': base64Encode([9]),
      },
    },
    'workflow_snapshot': {
      'steps': [
        {'label': 'First Step'},
        {'label': 'Second Step'},
        {'label': 'Final Step'},
      ],
      'decisions': [
        {
          'step': 1,
          'action': 'approve',
          'actor_id': 'middle',
          'reviewer': {
            'name': 'Middle Reviewer',
            'position_title': 'Administrative Officer',
          },
          'signature': {'signature_asset_id': 'middle-ink', 'revision': 2},
        },
      ],
    },
    'signatures': [
      {
        'slot_key': 'workflow_step_2',
        'signed_by': actor,
        'signature_asset_id': 'middle-ink',
        'signature_image_base64': base64Encode([1, 2, 3]),
      },
    ],
  };
  test(
    'middle block prints its own confirmed reviewer and ink; future blocks cannot borrow final ink',
    () {
      final people = LocatorFormSignatories.fromJson(payload());
      expect(people.forSource('workflow_step_2').name, 'Middle Reviewer');
      expect(
        people.forSource('workflow_step_2').positionTitle,
        'Administrative Officer',
      );
      expect(people.forSource('workflow_step_2').signatureBytes, [1, 2, 3]);
      expect(people.forSource('workflow_step_3').signatureBytes, isNull);
      expect(people.forSource('workflow_step_21').signatureBytes, isNull);
      expect(people.finalApprover.signatureBytes, [9]);
      for (final data in [
        payload(status: 'revoked'),
        payload(status: 'returned'),
        payload(revision: 3),
        payload(actor: 'someone-else'),
      ]) {
        expect(
          LocatorFormSignatories.fromJson(
            data,
          ).forSource('workflow_step_2').signatureBytes,
          isNull,
        );
      }
    },
  );
  for (final leave in [false, true]) {
    testWidgets(
      'unloaded selected workflow cannot silently generate legacy defaults; leave=$leave',
      (tester) async {
        ApiClient.instance.init();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: leave
                  ? LeavePrintSettings(readWorkflowSteps: () => null)
                  : LocatorPrintSettings(readWorkflowSteps: () => null),
            ),
          ),
        );
        await tester.tap(find.text('Design layout'));
        await tester.pumpAndSettle();
        expect(find.byType(LocatorPrintLayoutEditor), findsNothing);
        expect(
          find.text(
            'Select a workflow and wait for it to load before designing a new layout.',
          ),
          findsOneWidget,
        );
      },
    );
  }
  for (final keepDraft in [false, true]) {
    testWidgets(
      'Leave custom designer follows routing and preserves saved geometry; saved=$keepDraft',
      (tester) async {
        ApiClient.instance.init();
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final saved = leavePrintLayoutDefaults(leaveType);
        LeavePrintDraft? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LeavePrintSettings(
                readLeaveType: () => leaveType,
                readWorkflowSteps: () => oneStep,
                initialDraft: keepDraft
                    ? LeavePrintDraft(layout: 'custom', printLayout: saved)
                    : null,
                onChanged: (v) => result = v,
              ),
            ),
          ),
        );
        await tester.tap(
          find.text(keepDraft ? 'Edit layout' : 'Design layout'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sample signer'), findsNWidgets(keepDraft ? 4 : 2));
        await tester.tap(find.text('Use layout'));
        await tester.pumpAndSettle();
        if (keepDraft) {
          expect(
            result!.printLayout!.elements.map((e) => e.source),
            saved.elements.map((e) => e.source),
          );
          for (var i = 0; i < saved.elements.length; i++) {
            expect(
              result!.printLayout!.elements[i].x,
              closeTo(saved.elements[i].x, .0001),
            );
            expect(
              result!.printLayout!.elements[i].y,
              closeTo(saved.elements[i].y, .0001),
            );
          }
        } else {
          expect(
            result!.printLayout!.elements
                .where((e) => e.kind == 'signature')
                .length,
            2,
          );
        }
      },
    );
  }
}
