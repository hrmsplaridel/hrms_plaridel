import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/employee_leave_actions.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';

class _TestPrintLeaveProvider extends LeaveProvider {
  _TestPrintLeaveProvider({required super.repository});

  bool failRequestRefresh = false;
  bool failBalanceFetch = false;

  @override
  Future<LeaveRequest?> refreshRequestById(String id) async {
    if (failRequestRefresh) return null;
    return LeaveRequest(
      id: id,
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );
  }

  @override
  Future<List<LeaveBalance>> fetchBalancesForUserStrict(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (failBalanceFetch) throw Exception('Balance fetch failed');
    return [];
  }
}

void main() {
  testWidgets('Printing stops and shows error if request cannot be refreshed', (
    tester,
  ) async {
    final provider = _TestPrintLeaveProvider(
      repository: MockLeaveRepository(),
    );
    provider.failRequestRefresh = true;

    final request = LeaveRequest(
      id: 'req-1',
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    EmployeeLeaveActions(
                      context: context,
                      isMounted: () => true,
                    ).printLeaveForm(request);
                  },
                  child: const Text('Print'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Print'));
    await tester.pump(); // Start SnackBar animation
    await tester.pump(const Duration(seconds: 1)); // Wait for it to appear

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('request data could not be verified'),
      findsOneWidget,
    );
    expect(find.text('Loading form data...'), findsNothing);
  });

  testWidgets('Printing stops and shows error if balances cannot be fetched', (
    tester,
  ) async {
    final provider = _TestPrintLeaveProvider(
      repository: MockLeaveRepository(),
    );
    provider.failBalanceFetch = true;

    final request = LeaveRequest(
      id: 'req-1',
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    EmployeeLeaveActions(
                      context: context,
                      isMounted: () => true,
                    ).printLeaveForm(request);
                  },
                  child: const Text('Print'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Print'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('balance or request data'), findsOneWidget);
    expect(find.text('Loading form data...'), findsNothing);
  });
}
