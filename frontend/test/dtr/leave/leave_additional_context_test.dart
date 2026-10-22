import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_request_information.dart';

Future<void> openDetails(WidgetTester tester, LeaveRequest request) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LeaveRequestInformation(request: request),
          ),
        ),
      ),
    );

void main() {
  testWidgets('date context belongs only to the selected leave type', (
    tester,
  ) async {
    await openDetails(
      tester,
      LeaveRequest(
        userId: 'employee',
        leaveType: LeaveType.maternityLeave,
        expectedDeliveryDate: DateTime(2026, 10, 20),
        childDeliveryDate: DateTime(2026, 10, 21),
      ),
    );
    expect(find.text('Expected Delivery Date'), findsOneWidget);
    expect(find.text('Oct 20, 2026'), findsOneWidget);
    expect(find.text('Child Delivery Date'), findsNothing);
    expect(find.text('Maternity Classification'), findsNothing);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'custom leave shows only its populated fields at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await openDetails(
          tester,
          const LeaveRequest(
            userId: 'employee',
            leaveType: LeaveType.others,
            leaveTypeName: 'eLeave',
            leaveTypeDisplayName: 'Earl leave',
            customLeaveTypeText: 'Earl leave',
            otherPurpose: LeaveOtherPurpose.terminalLeave,
            otherPurposeDetails: 'Old other purpose',
            sickIllnessDetails: 'Old illness',
            customDetails: {
              'purpose': 'Family appointment',
              'empty': ' ',
              'unknown': 'Undeclared value',
            },
            employeeDetailSchemaSnapshot: [
              LeaveCustomFieldDefinition(key: 'purpose', label: 'Purpose'),
              LeaveCustomFieldDefinition(
                key: 'empty',
                label: 'Empty custom field',
              ),
            ],
          ),
        );
        expect(find.text('Additional Context'), findsOneWidget);
        expect(find.text('Purpose'), findsOneWidget);
        expect(find.text('Family appointment'), findsOneWidget);
        for (final label in [
          'Custom Leave Type',
          'Other Purpose',
          'Other Purpose Details',
          'Sick Illness Details',
          'Empty custom field',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.text('Undeclared value'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'built-in leave hides unrelated stored values and empty relevant fields',
    (tester) async {
      await openDetails(
        tester,
        LeaveRequest(
          userId: 'employee',
          leaveType: LeaveType.sickLeave,
          sickLeaveNature: SickLeaveNature.outPatient,
          sickIllnessDetails: ' ',
          locationDetails: 'Old destination',
          expectedDeliveryDate: DateTime(2026, 10, 20),
        ),
      );
      expect(find.text('Sick Leave Nature'), findsOneWidget);
      expect(find.text('Out Patient'), findsOneWidget);
      for (final label in [
        'Sick Illness Details',
        'Location Details',
        'Expected Delivery Date',
      ]) {
        expect(find.text(label), findsNothing);
      }
    },
  );
  testWidgets(
    'additional context is hidden when the leave has no populated context',
    (tester) async {
      await openDetails(
        tester,
        const LeaveRequest(
          userId: 'employee',
          leaveType: LeaveType.vacationLeave,
        ),
      );
      expect(find.text('Additional Context'), findsNothing);
      expect(find.text('Employee Information'), findsOneWidget);
      expect(find.text('Leave Details'), findsOneWidget);
    },
  );
  testWidgets('generic Others retains its populated purpose fields', (
    tester,
  ) async {
    await openDetails(
      tester,
      const LeaveRequest(
        userId: 'employee',
        leaveType: LeaveType.others,
        otherPurpose: LeaveOtherPurpose.terminalLeave,
        otherPurposeDetails: 'Retirement',
      ),
    );
    expect(find.text('Other Purpose'), findsOneWidget);
    expect(find.text('Terminal Leave'), findsOneWidget);
    expect(find.text('Retirement'), findsOneWidget);
  });
  testWidgets('custom zero and false values remain visible', (tester) async {
    await openDetails(
      tester,
      const LeaveRequest(
        userId: 'employee',
        leaveType: LeaveType.others,
        leaveTypeName: 'custom',
        customDetails: {'count': 0, 'urgent': false},
        employeeDetailSchemaSnapshot: [
          LeaveCustomFieldDefinition(
            key: 'count',
            label: 'Count',
            type: LeaveCustomFieldType.number,
          ),
          LeaveCustomFieldDefinition(
            key: 'urgent',
            label: 'Urgent',
            type: LeaveCustomFieldType.boolean,
          ),
        ],
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
  });
}
