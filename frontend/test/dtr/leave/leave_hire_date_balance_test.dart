import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_days_card.dart';

void main() {
  testWidgets('mobile annual card explains service eligibility and rounded first-year days', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final balance = LeaveBalance.fromJson({
      'user_id':'employee','leave_type':'wellnessLeave','leave_type_display_name':'Wellness Leave',
      'record_kind':'annual_entitlement','entitlement_basis':'annual','earned_days':1,
      'eligible':false,'eligibility_message':'You become eligible on 2027-04-01.',
      'prorated':true,'calculated_days':1.25,'entitlement_year':2026,
    });
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:LeaveDaysCard(balance:balance))));
    expect(find.text('You become eligible on 2027-04-01.'),findsOneWidget);
    expect(find.textContaining('rounded down'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
