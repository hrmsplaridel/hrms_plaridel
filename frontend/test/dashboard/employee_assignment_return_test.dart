import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/pages/admin_dashboard_desktop.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';
import 'package:hrms_plaridel/features/dtr/management/assignments/pages/manage_assignment.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_provider.dart';
import 'package:hrms_plaridel/features/recruitment/data/recruitment_hire_prefill.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/providers/theme_mode_provider.dart';

class _Documents extends DocuTrackerProvider {
  @override Future<void> loadNotifications({bool forceRefresh=false}) async {}
  @override Future<void> loadSourceSignatureRequests({bool forceRefresh=false}) async {}
}

class _Dtr extends DtrProvider {
  @override void setUserFromApi(String? id) {}
  @override void onAuthUserChanged(String? id) {}
}

Future<void> pump(WidgetTester tester) async {
  for(var i=0;i<12;i++) { await tester.pump(const Duration(milliseconds:50)); }
}

void main() {
  setUpAll(() { FlutterSecureStorage.setMockInitialValues({}); ApiClient.instance.init(); });
  for(final fromEmployee in [true,false]) {
    testWidgets('assignment Back returns to ${fromEmployee?'the employee list':'the DTR hub'}', (tester) async {
      tester.view.physicalSize=const Size(1600,1200);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      ApiClient.instance.dio.interceptors.clear();
      final employee={'id':'employee','full_name':'Test Employee','role':'employee','email':'test@example.local',
        'employee_number':1,'is_active':true,'employment_status':'active','employment_type':'permanent'};
      final assignmentEmployeeIds=<String>[];
      ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
        dynamic data=<dynamic>[];
        if(o.path=='/api/account-creation-access/me')data={'allowed':true};
        if(o.path=='/api/dtr-access/me')data={'manage_allowed':true,'employees_allowed':true};
        if(o.path=='/api/employees')data={'employees':[employee],'total':1};
        if(o.path=='/api/employees/employee')data=employee;
        if(o.path=='/api/assignments/context') {
          final id=o.queryParameters['employee_id']?.toString();
          if(id!=null)assignmentEmployeeIds.add(id);
          data={'official_date':'2026-11-01','first_date':'2020-01-01','last_date':'2030-12-31'};
        }
        if(o.path.contains('unread-count'))data={'count':0};
        h.resolve(Response(requestOptions:o,statusCode:200,data:data));
      }));
      final auth=AuthProvider()..replaceUser(const AppUser(id:'admin',email:'admin@test.local',role:'admin'));
      final realtime=AppRealtimeProvider(), docs=_Documents(), notices=NotificationProvider();
      final leave=LeaveProvider(repository:MockLeaveRepository()),dtr=_Dtr();
      final theme=ThemeModeNotifier(initial:ThemeMode.light), hire=RecruitmentHirePrefill();
      addTearDown(()async {
        await tester.pumpWidget(const SizedBox.shrink());ApiClient.instance.dio.interceptors.clear();
        auth.dispose();realtime.dispose();docs.dispose();notices.dispose();leave.dispose();dtr.dispose();theme.dispose();hire.dispose();
      });
      await tester.pumpWidget(MultiProvider(providers:[
        ChangeNotifierProvider.value(value:auth),ChangeNotifierProvider.value(value:realtime),
        ChangeNotifierProvider<DocuTrackerProvider>.value(value:docs),ChangeNotifierProvider.value(value:notices),
        ChangeNotifierProvider.value(value:leave),ChangeNotifierProvider<DtrProvider>.value(value:dtr),
        ChangeNotifierProvider.value(value:theme),ChangeNotifierProvider.value(value:hire),
      ],child:const MaterialApp(home:AdminDashboard())));
      await pump(tester);
      await tester.tap(find.text('DTR').first); await pump(tester);
      if(!fromEmployee) {
        await tester.tap(find.text('Workforce Setup'));await pump(tester);
        expect(find.text('Back to DTR'),findsOneWidget);
        await tester.tap(find.text('Back to DTR'));await pump(tester);
        expect(find.text('Daily Time Record. Choose a feature below.'),findsOneWidget);
        expect(tester.takeException(),isNull); return;
      }
      await tester.tap(find.text('Employees').first);await pump(tester);
      final search=find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.hintText=='Search name, ID, or email');
      await tester.enterText(search,'Test'); await tester.pump(const Duration(milliseconds:500));await pump(tester);
      await tester.tap(find.text('Test Employee').first);await pump(tester);
      final employeeState=tester.state(find.byType(ManageEmployee));
      await tester.ensureVisible(find.text('View assignment & shift'));await pump(tester);
      final scroll=Scrollable.of(tester.element(find.byType(ManageEmployee))).position;
      final offset=scroll.pixels;
      await tester.tap(find.text('View assignment & shift'));await pump(tester);
      expect(find.byType(ManageAssignment),findsOneWidget);
      expect(assignmentEmployeeIds,contains('employee'));
      expect(find.text('Back to Employees'),findsOneWidget);
      expect(find.text('Back to DTR'),findsNothing);
      // More than five cached features must not evict the originating list.
      for(final tab in ['Departments','Positions','Shifts','Holidays']) {
        await tester.ensureVisible(find.text(tab).first);
        await tester.tap(find.text(tab).first); await pump(tester);
        expect(find.text('Back to Employees'),findsOneWidget);
      }
      await tester.ensureVisible(find.text('Back to Employees'));await tester.tap(find.text('Back to Employees'));await pump(tester);
      expect(identical(tester.state(find.byType(ManageEmployee)),employeeState),isTrue);
      expect(tester.widget<TextField>(search).controller!.text,'Test');
      expect(find.text('View assignment & shift'),findsOneWidget);
      expect(scroll.pixels,closeTo(offset,1));
      expect(tester.takeException(),isNull);
    });
  }
}
