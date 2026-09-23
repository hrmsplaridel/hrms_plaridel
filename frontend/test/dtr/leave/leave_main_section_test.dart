import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';

void main() {
  testWidgets('mobile filing action follows the active leave section', (
    tester,
  ) async {
    LeaveSection? activeSection;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaveMain(
            isDepartmentHead: true,
            employeeRequestsContent: const Text('Requests content'),
            adminApprovalsContent: const Text('Approvals content'),
            onSectionChanged: (section) => activeSection = section,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(activeSection, LeaveSection.approvals);
    expect(find.text('Approvals content'), findsOneWidget);

    await tester.tap(find.text('My Requests'));
    await tester.pump();

    expect(activeSection, LeaveSection.requests);
    expect(find.text('Requests content'), findsOneWidget);
  });
}
