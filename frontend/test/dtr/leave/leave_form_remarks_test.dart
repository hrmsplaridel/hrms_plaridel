import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_remarks.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'long department and final reasons keep the official PDF on one page',
    () async {
      final reason = List.filled(
        8,
        'The requested dates conflict with required staffing for the scheduled audit.',
      ).join(' ');
      for (final status in [
        LeaveRequestStatus.rejectedByDepartmentHead,
        LeaveRequestStatus.rejectedByHr,
      ]) {
        final document = await LeaveRequestPdf.buildPdf(
          request: LeaveRequest(
            userId: 'employee',
            employeeName: 'Test Employee',
            leaveType: LeaveType.vacationLeave,
            status: status,
            departmentHeadRemarks: reason,
            disapprovalReason: reason,
            startDate: DateTime(2026, 10, 20),
            endDate: DateTime(2026, 10, 20),
          ),
          balances: const [],
        );
        expect(await document.save(), isNotEmpty);
        expect(document.document.pdfPageList.pages.length, 1);
      }
    },
  );
  test(
    '7.B uses department rejection history before HR recommendation text',
    () {
      const request = LeaveRequest(
        userId: 'employee',
        leaveType: LeaveType.vacationLeave,
        status: LeaveRequestStatus.rejectedByDepartmentHead,
        departmentHeadRemarks: 'Department coverage is insufficient.',
        recommendationRemarks: 'Unrelated HR text',
      );
      expect(
        leaveFormRecommendationRemarks(request),
        'Department coverage is insufficient.',
      );
      expect(leaveFormDisapprovalReason(request), isEmpty);
    },
  );
  test(
    'department rejection response can use reviewer remarks before history reload',
    () {
      const request = LeaveRequest(
        userId: 'employee',
        leaveType: LeaveType.vacationLeave,
        status: LeaveRequestStatus.rejectedByDepartmentHead,
        hrRemarks: 'Recorded department reason',
      );
      expect(
        leaveFormRecommendationRemarks(request),
        'Recorded department reason',
      );
    },
  );
  test('7.D prints final reason while 7.B keeps department recommendation', () {
    const request = LeaveRequest(
      userId: 'employee',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.rejectedByHr,
      departmentHeadRemarks: 'Department recommends approval',
      disapprovalReason: 'Final HR disapproval reason',
    );
    expect(
      leaveFormRecommendationRemarks(request),
      'Department recommends approval',
    );
    expect(leaveFormDisapprovalReason(request), 'Final HR disapproval reason');
  });
  test(
    'long remarks use all three lines without losing words or overflowing',
    () {
      const text =
          'Insufficient staffing during the scheduled audit. Please choose alternative dates after the audit is completed.';
      final result = layoutLeaveFormRemarks(
        text,
        width: 100,
        fontSize: 9,
        measure: (text, size) => text.length * size * 0.5,
      );
      expect(result.lines.length, 3);
      expect(result.lines.join(' '), text);
      for (final line in result.lines) {
        expect(line.length * result.fontSize * 0.5, lessThanOrEqualTo(100));
      }
    },
  );
  test('manual line breaks, long unbroken words and blank remarks fit', () {
    final result = layoutLeaveFormRemarks(
      'First line\nSecond line',
      width: 100,
      fontSize: 9,
      measure: (text, size) => text.length * size * 0.5,
    );
    expect(result.lines, ['First line', 'Second line']);
    final long = List.filled(100, 'x').join();
    final wrapped = layoutLeaveFormRemarks(
      long,
      width: 100,
      fontSize: 9,
      measure: (text, size) => text.length * size * 0.5,
    );
    expect(wrapped.lines.length, lessThanOrEqualTo(3));
    expect(wrapped.lines.join(), long);
    expect(
      layoutLeaveFormRemarks(
        '',
        width: 100,
        fontSize: 9,
        measure: (text, size) => text.length * size,
      ).lines,
      isEmpty,
    );
  });
}
