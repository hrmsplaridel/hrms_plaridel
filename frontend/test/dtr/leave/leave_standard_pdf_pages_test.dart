import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final status in [
    LeaveRequestStatus.pendingHr,
    LeaveRequestStatus.approved,
  ]) {
    test(
      'standard CSC form does not append custom answers for $status',
      () async {
        final document = await LeaveRequestPdf.buildPdf(
          request: LeaveRequest(
            userId: 'employee',
            employeeName: 'Test Employee',
            leaveType: LeaveType.others,
            customLeaveTypeText: 'Earl leave',
            startDate: DateTime(2026, 10, 20),
            endDate: DateTime(2026, 10, 20),
            workingDaysApplied: 1,
            status: status,
            customDetails: const {'purpose': 'Family appointment'},
            employeeDetailSchemaSnapshot: const [
              LeaveCustomFieldDefinition(
                key: 'purpose',
                label: 'Purpose',
                type: LeaveCustomFieldType.text,
              ),
            ],
          ),
          balances: const [],
        );
        await document.save();
        expect(
          document.document.pdfPageList.pages.length,
          1,
          reason:
              'Custom answers belong in request details or a designed layout, not an automatic extra page.',
        );
      },
    );
  }
}
