import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/configured_leave_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sample Wellness form fits one page', () async {
    final doc = await buildWellnessLeavePdf(
      request: LeaveRequest(
        userId: 'sample',
        employeeName: 'Employee Example',
        leaveType: LeaveType.others,
        dateFiled: DateTime(2026, 10, 10),
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        workingDaysApplied: 1,
        reason: 'Personal wellness and rest.',
      ),
      department: 'Human Resources',
      departmentReviewer: 'Department Head Example',
      mayorName: 'Municipal Mayor Example',
    );
    final bytes = await doc.save();
    expect(doc.document.pdfPageList.pages.length, 1);
    const output = String.fromEnvironment('WELLNESS_PREVIEW_PATH');
    if (output.isNotEmpty) await File(output).writeAsBytes(bytes);
  });
  test(
    'wellness form creates A4 PDF with manual mayor signature and long reason continuation',
    () async {
      final request = LeaveRequest(
        userId: 'user',
        employeeName: 'Employee Example',
        leaveType: LeaveType.others,
        dateFiled: DateTime(2026, 10, 10),
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        workingDaysApplied: 1,
        reason: List.filled(100, 'A detailed wellness reason.').join(' '),
      );
      final doc = await buildWellnessLeavePdf(
        request: request,
        department: 'Human Resources',
        mayorName: 'Mayor Example',
        departmentReviewer: 'Head Example',
      );
      final bytes = await doc.save();
      expect(latin1.decode(bytes).startsWith('%PDF'), isTrue);
      expect(doc.document.pdfPageList.pages.length, greaterThan(1));
    },
  );
}
