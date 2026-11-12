import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/desktop/pages/employee_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart' as admin;
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/mobile/widgets/employee_leave_mobile_balances_panel.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_balance_card.dart';

class _CustomRepository extends MockLeaveRepository {
  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => [
    LeaveBalance.fromJson({'user_id':userId,'leave_type':'wellness',
      'leave_type_display_name':'Wellness Leave','earned_days':2.5,'record_kind':'credit_balance'}),
  ];
}

void main() {
  testWidgets('HR can select a custom wallet and safely change department', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400,1100));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors..clear()..add(InterceptorsWrapper(onRequest:(o,h){
      final dynamic data=o.path=='/api/employees' ? {'employees':[{'id':'employee','full_name':'Test Employee',
        'current_department_name':'HR','employment_type':'permanent','leave_credit_eligible':true}],'total':1}
        : o.path=='/api/departments' ? [{'name':'HR'},{'name':'Finance'}]
        : o.path=='/api/leave/types' ? [] : {'can_review':true,'items':[],'total':0,'setups':[]};
      h.resolve(Response(requestOptions:o,statusCode:200,data:data));
    }));
    addTearDown(()=>ApiClient.instance.dio.interceptors.clear());
    final auth=AuthProvider()..replaceUser(const AppUser(id:'hr',email:'hr@test',role:'hr'));
    final leave=LeaveProvider(repository:_CustomRepository()),realtime=AppRealtimeProvider();
    addTearDown(auth.dispose);addTearDown(leave.dispose);addTearDown(realtime.dispose);
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthProvider>.value(value:auth),ChangeNotifierProvider<LeaveProvider>.value(value:leave),
      ChangeNotifierProvider<AppRealtimeProvider>.value(value:realtime),
    ],child:const MaterialApp(home:Scaffold(body:SingleChildScrollView(child:admin.AdminLeaveScreen())))));
    await tester.pumpAndSettle();await tester.tap(find.byTooltip('More actions'));await tester.pumpAndSettle();
    await tester.tap(find.text('Manual balance adjustment'));await tester.pumpAndSettle();
    Finder dropdown(String label)=>find.byWidgetPredicate((w)=>w is DropdownButtonFormField<String> && w.decoration.labelText==label);
    await tester.tap(dropdown('Department'));await tester.pumpAndSettle();
    await tester.tap(find.text('HR').last);await tester.pumpAndSettle();
    await tester.tap(dropdown('Employee'));await tester.pumpAndSettle();
    await tester.tap(find.text('Test Employee').last);await tester.pumpAndSettle();
    await tester.ensureVisible(dropdown('Leave type'));await tester.tap(dropdown('Leave type'));await tester.pumpAndSettle();
    await tester.tap(find.text('Wellness Leave').last);await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<String>>(dropdown('Leave type')).initialValue,'wellness');
    await tester.ensureVisible(dropdown('Department'));await tester.tap(dropdown('Department'));await tester.pumpAndSettle();
    await tester.tap(find.text('Finance').last);await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
  testWidgets('desktop displays a custom credit wallet alongside the credit summary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600,1100));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final auth=AuthProvider()..replaceUser(const AppUser(id:'employee',email:'employee@test',role:'employee'));
    final leave=LeaveProvider(repository:_CustomRepository()),realtime=AppRealtimeProvider();
    addTearDown(auth.dispose);addTearDown(leave.dispose);addTearDown(realtime.dispose);
    await tester.pumpWidget(MultiProvider(providers:[
      ChangeNotifierProvider<AuthProvider>.value(value:auth),
      ChangeNotifierProvider<LeaveProvider>.value(value:leave),
      ChangeNotifierProvider<AppRealtimeProvider>.value(value:realtime),
    ],child:const MaterialApp(home:Scaffold(body:SingleChildScrollView(child:EmployeeLeaveScreen())))));
    await tester.pump();await tester.pump(const Duration(milliseconds:300));
    expect(find.byType(LeaveBalanceCard),findsOneWidget);
    expect(find.text('Wellness Leave'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  test('manual adjustment sends a custom wallet key without mapping it to others', () async {
    ApiClient.instance.init();
    final requests=<RequestOptions>[];
    ApiClient.instance.dio.interceptors..clear()..add(InterceptorsWrapper(onRequest:(o,h){
      requests.add(o);h.resolve(Response(requestOptions:o,statusCode:200,
        data:{'user_id':'test','leave_type':'wellness','adjusted_days':3}));
    }));
    addTearDown(()=>ApiClient.instance.dio.interceptors.clear());
    final result=await ApiLeaveRepository().applyBalanceAdjustment(userId:'test',
      leaveType:LeaveType.others,leaveTypeName:'wellness',adjustmentDays:3,remarks:'Approved opening credits');
    expect(requests.single.data['leave_type'],'wellness');expect(result.effectiveLeaveTypeName,'wellness');
  });
  test('monthly accrual settings survive a leave type round trip', () {
    final data = {'name':'wellness','display_name':'Wellness Leave',
      'balance_ledger_type':'ownBalance','accrues_monthly':true,
      'accrual_monthly_rate':1.25,'accrual_start_date':'2026-12-01','accrual_annual_cap':15};
    final saved=LeaveTypeDefinition.fromJson(data).toJson();
    for(final key in data.keys) { expect(saved[key],data[key],reason:key); }
  });
  testWidgets('a custom wallet displays a credit card with its own name and credits', (tester) async {
    final balance=LeaveBalance.fromJson({'user_id':'test','leave_type':'wellness',
      'leave_type_display_name':'Wellness Leave','record_kind':'credit_balance',
      'earned_days':2.5,'used_days':1,'pending_days':0.5});
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:EmployeeLeaveMobileBalancesPanel(balances:[balance],loading:false,error:null,
        onRetry:(){},onBalanceHistory:(){})))));
    expect(find.byType(LeaveBalanceCard),findsOneWidget);
    expect(find.text('Wellness Leave'),findsOneWidget);
    expect(tester.widget<LeaveBalanceCard>(find.byType(LeaveBalanceCard)).balance.availableDays,1);
  });
}
