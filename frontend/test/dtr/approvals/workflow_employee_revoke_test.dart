import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

void main() {
  for (final kind in ['leave', 'locator']) {
    for (final width in [1400.0, 420.0]) {
      for (final scenario in ['confirm', 'cancel', 'unauthorized', 'own', 'expired', 'permission-changed', 'server-rejected']) {
        testWidgets('$kind employee revokes approved workflow: $scenario at $width', (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ApiClient.instance.init();
          ApiClient.instance.dio.interceptors.clear();
          final auth = AuthProvider()..replaceUser(const AppUser(id:'reviewer',email:'reviewer@test.local',role:'employee'));
          var allowed = scenario != 'unauthorized';
          var writes = 0;
          var changed = false;
          final data = <String,dynamic>{
            'id':'request','user_id':scenario=='own'?'reviewer':'applicant',
            'employee_id':scenario=='own'?'reviewer':'applicant',
            'employee_name':'Applicant','status':'approved','can_revoke_approval':allowed,
            'approved_at':DateTime.now().subtract(Duration(days:scenario=='expired'?4:0)).toIso8601String(),
            'hr_reviewed_at':DateTime.now().subtract(Duration(days:scenario=='expired'?4:0)).toIso8601String(),
            'start_date':'2026-11-02','end_date':'2026-11-02','slip_date':'2026-11-02',
            'leave_type':'sickLeave','request_type':'test','request_type_label':'Test',
            'working_days_applied':1,'reason':'Official business',
            'workflow_snapshot':{'current_step':1,'steps':[{'label':'Records verification','assignee_source':'specific_users','user_ids':['reviewer']}],
              'decisions':[{'step':0,'action':'approve','actor_id':'reviewer','reviewer_name':'Reviewer'}]},
          };
          Map<String,dynamic> request() => {'id':'request','kind':kind,'status':'approved',
            'can_review':false,'allowed_actions':<String>[], 'request_data':{...data,'can_revoke_approval':allowed}};
          ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
            if(o.method=='PATCH') {
              writes++;
              expect(o.path,kind=='leave'?'/api/leave/request/revoke':'/api/locator-slips/request/revoke');
              if(scenario=='server-rejected') {
                h.reject(DioException(requestOptions:o,response:Response(requestOptions:o,statusCode:409,data:{'error':'Approval changed. Refresh and try again.'}),type:DioExceptionType.badResponse));
              } else {
                h.resolve(Response(requestOptions:o,statusCode:200,data:{...data,'status':kind=='leave'?'returned':'revoked'}));
              }
              return;
            }
            h.resolve(Response(requestOptions:o,statusCode:200,data:o.path.endsWith('/inbox')?[request()]:<dynamic>[]));
          }));
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear(); auth.dispose();
          });
          await tester.pumpWidget(ChangeNotifierProvider.value(value:auth,child:MaterialApp(home:Builder(builder:(context)=>Scaffold(
            body:TextButton(onPressed:()async{changed=await reviewAssignedWorkflowRequest(context,request());},child:const Text('Open request')),
          )))));
          await tester.tap(find.text('Open request')); await tester.pumpAndSettle();
          final revoke = find.widgetWithText(OutlinedButton,'Revoke Approval');
          if (scenario=='unauthorized'||scenario=='own') {
            expect(revoke,findsNothing);
          } else if (scenario=='expired') {
            if(revoke.evaluate().isNotEmpty) expect(tester.widget<OutlinedButton>(revoke).onPressed,isNull);
            expect(writes,0);
          } else {
            expect(revoke,findsOneWidget);
            if(scenario=='permission-changed') allowed=false;
            await tester.ensureVisible(revoke); await tester.tap(revoke); await tester.pumpAndSettle();
            if(scenario=='permission-changed') {
              expect(find.byType(AlertDialog),findsNothing);
              expect(writes,0);
            } else if(scenario=='cancel') {
              await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
              expect(writes,0); expect(changed,false);
            } else {
              await tester.tap(find.widgetWithText(FilledButton,'Revoke Approval')); await tester.pumpAndSettle();
              expect(writes,0,reason:'A documented reason is required');
              await tester.enterText(find.byKey(const Key('workflow-revocation-reason')),'Recorded against the wrong date.');
              await tester.tap(find.widgetWithText(FilledButton,'Revoke Approval')); await tester.pumpAndSettle();
              expect(writes,1);
              expect(changed,scenario!='server-rejected');
              expect(find.byType(SnackBar),findsWidgets);
            }
          }
          expect(tester.takeException(),isNull);
        });
      }
    }
  }
}
