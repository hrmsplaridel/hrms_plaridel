import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

LeaveBalance summary(String name, double used) => LeaveBalance.fromJson({
  'user_id':'employee','leave_type':name,'leave_type_display_name':name=='mandatoryForcedLeave'?'Mandatory/Forced Leave':'Wellness Leave',
  'record_kind':name=='mandatoryForcedLeave'?'compliance_progress':'annual_entitlement',
  'entitlement_basis':name=='mandatoryForcedLeave'?'compliance':'annual',
  'entitlement_year':2026,'earned_days':5,'used_days':used,'pending_days':2,
});
class _Repository extends MockLeaveRepository {
  _Repository(this.rows);
  final List<LeaveBalance> rows;
  @override Future<List<LeaveBalance>> getBalancesForUser(String id) async => rows;
}
void main() {
  for (final width in [390.0,1600.0]) {
  testWidgets('unverified opening history at $width never claims the requirement is met', (tester) async {
    tester.view.physicalSize=Size(width,1200);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final balance=LeaveBalance.fromJson({...summary('mandatoryForcedLeave',5).toJson(),'history_verification_required':true});
    final auth=AuthProvider()..replaceUser(const AppUser(id:'employee',email:'employee@test.local',role:'employee',employmentType:'permanent'));
    final realtime=AppRealtimeProvider(),leave=LeaveProvider(repository:_Repository([balance]));
    addTearDown(auth.dispose);addTearDown(realtime.dispose);addTearDown(leave.dispose);
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthProvider>.value(value:auth),ChangeNotifierProvider<AppRealtimeProvider>.value(value:realtime),
      ChangeNotifierProvider<LeaveProvider>.value(value:leave),
    ],child:MaterialApp(home:Scaffold(body:SingleChildScrollView(child:width<600?EmployeeLeaveMobileBalancesPanel(
      showCredits:false,balances:[balance],loading:false,error:null,onRetry:(){},onBalanceHistory:(){},
    ):const EmployeeLeaveScreen())))));
    await tester.pump();await tester.pump(const Duration(milliseconds:300));
    expect(find.text('Requirement met'),findsNothing);
    expect(find.text('History verification required'),findsOneWidget);
    expect(find.text('—'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  }
  for(final width in [390.0,1600.0]) {
    for(final complete in [false,true]) {
      testWidgets('usage and compliance summaries at $width; complete=$complete',(tester) async {
        tester.view.physicalSize=Size(width,1200);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final rows=[summary('wellnessLeave',complete?5:1),summary('mandatoryForcedLeave',complete?6:2)];
        final auth=AuthProvider()..replaceUser(const AppUser(id:'employee',email:'employee@test.local',role:'employee',employmentType:'permanent'));
        final realtime=AppRealtimeProvider(),leave=LeaveProvider(repository:_Repository(rows));
        addTearDown(auth.dispose);addTearDown(realtime.dispose);addTearDown(leave.dispose);
        await tester.pumpWidget(MultiProvider(providers:[
          ChangeNotifierProvider<AuthProvider>.value(value:auth),ChangeNotifierProvider<AppRealtimeProvider>.value(value:realtime),
          ChangeNotifierProvider<LeaveProvider>.value(value:leave),
        ],child:MaterialApp(home:Scaffold(body:SingleChildScrollView(child:width<600
          ? EmployeeLeaveMobileBalancesPanel(showCredits:false,balances:rows,loading:false,error:null,onRetry:(){},onBalanceHistory:(){})
          : const EmployeeLeaveScreen())))));
        await tester.pump();await tester.pump(const Duration(milliseconds:300));
        expect(find.text('Leave Usage & Limits'),findsOneWidget);
        expect(find.text('Mandatory/Forced Leave'),findsOneWidget);
        final forced=find.byKey(const ValueKey('leave-balance-row-mandatoryForcedLeave'));
        final wellness=find.byKey(const ValueKey('leave-balance-row-wellnessLeave'));
        expect(forced,findsOneWidget);expect(wellness,findsOneWidget);
        expect(find.descendant(of:forced,matching:find.text('Pending')),findsNothing);
        expect(find.descendant(of:wellness,matching:find.text('Pending')),findsNothing);
        if(complete) {
          expect(find.text('Requirement met'),findsOneWidget);
          expect(find.text('Limit reached'),findsOneWidget);
        } else {
          expect(find.descendant(of:forced,matching:find.text('3')),findsOneWidget);
          expect(find.descendant(of:wellness,matching:find.text('4')),findsOneWidget);
        }
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
