import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/admin_my_leave_entry.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';

class _Repository extends MockLeaveRepository {
  _Repository(this.assigned);
  final bool assigned;
  @override
  Future<Map<String, dynamic>> checkIsDepartmentHead() async => {
    'isDeptHead': assigned,
    'canReviewPending': assigned,
  };
}

void main() {
  for (final assigned in [true, false]) {
    testWidgets('admin department approvals visibility: assigned=$assigned', (
      tester,
    ) async {
      final provider = LeaveProvider(repository: _Repository(assigned));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: AdminMyLeaveEntry(
                requestsContent: Text('Personal requests'),
                approvalsContent: Text('Department queue'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal requests'), findsOneWidget);
      expect(find.text('Approvals'), assigned ? findsOneWidget : findsNothing);
      if (assigned) {
        expect(find.byType(LeaveMain), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNothing);
        await tester.tap(find.text('Approvals'));
        await tester.pumpAndSettle();
        expect(find.text('Department queue'), findsOneWidget);
      }
    });
  }
}
