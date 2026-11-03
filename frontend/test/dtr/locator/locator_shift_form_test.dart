import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/application_review.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_form_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });
  for (final coverage in ['whole_day', 'am_only', 'pm_only']) {
    testWidgets('locator form respects $coverage holiday coverage', (tester) async {
      ApiClient.instance.dio.interceptors.clear();
      LocatorSlipDataCache.instance.invalidateAll();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      final allowed = coverage == 'whole_day' ? <String>[] :
          coverage == 'am_only' ? ['pm_in', 'pm_out'] : ['am_in', 'am_out'];
      ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final dynamic data = switch (o.path) {
          '/api/locator-slips/types' => [
            {'code':'locator', 'label':'Locator / Official Business', 'is_active':true},
            {'code':'work_from_home', 'label':'Work From Home', 'is_active':true, 'coverage_mode':'wfh'},
          ],
          '/api/locator-slips/context' => {'official_date':'2026-10-12'},
          '/api/locator-slips/submission-availability' => {'can_submit':true},
          '/api/locator-slips/shift-coverage' => {
            'single_session':false, 'can_file':allowed.isNotEmpty, 'allowed_slots':allowed,
            'holiday_coverage':coverage,
            'error':allowed.isEmpty ? 'This date is a holiday for your scheduled shift. No locator coverage is required.' : null,
          },
          '/api/locator-slips/department-head/check' => {'isDeptHead':false},
          _ => {'items':<dynamic>[], 'total':0},
        };
        h.resolve(Response(requestOptions:o, statusCode:200, data:data));
      }));
      final auth = AuthProvider()..replaceUser(const AppUser(id:'employee',email:'employee@test.com',role:'employee'));
      final realtime = AppRealtimeProvider();
      addTearDown(auth.dispose);
      addTearDown(realtime.dispose);
      tester.view.physicalSize = const Size(1400,1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(providers:[
        ChangeNotifierProvider<AuthProvider>.value(value:auth),
        ChangeNotifierProvider<AppRealtimeProvider>.value(value:realtime),
      ], child:const MaterialApp(home:Scaffold(body:SingleChildScrollView(child:EmployeeLocatorSlipContent())))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File Request').first);
      for(var i=0;i<30;i++) { await tester.pump(const Duration(milliseconds:50)); }
      EmployeeLocatorMobileSegmentSelector selector() => tester.widget(find.byType(EmployeeLocatorMobileSegmentSelector));
      if (allowed.isEmpty) {
        expect(selector().locked,isTrue);
        expect(find.textContaining('No locator coverage is required.'), findsOneWidget);
      } else {
        final exempt = coverage == 'am_only' ? 'AM IN' : 'PM OUT';
        await tester.tap(find.text(exempt));
        await tester.pump(const Duration(milliseconds:200));
        expect(coverage == 'am_only' ? selector().amIn : selector().pmOut,isFalse);
        await tester.tap(find.text(coverage == 'am_only' ? 'PM OUT' : 'AM IN'));
        await tester.pump(const Duration(milliseconds:200));
        expect(coverage == 'am_only' ? selector().pmOut : selector().amIn,isTrue);
        await tester.tap(find.text('Locator / Official Business').last);
        await tester.pump(const Duration(milliseconds:300));
        await tester.tap(find.text('Work From Home').last);
        await tester.pump(const Duration(milliseconds:300));
        expect(selector().amIn,allowed.contains('am_in'));
        expect(selector().amOut,allowed.contains('am_out'));
        expect(selector().pmIn,allowed.contains('pm_in'));
        expect(selector().pmOut,allowed.contains('pm_out'));
      }
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final single in [true, false]) {
    testWidgets('locator filing loads selected-date shift; single=$single', (
      tester,
    ) async {
      ApiClient.instance.dio.interceptors.clear();
      LocatorSlipDataCache.instance.invalidateAll();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      final dates = <String>[];
      var failLookup = false;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.path == '/api/locator-slips/shift-coverage' && failLookup) {
              failLookup = false;
              h.reject(DioException(requestOptions: o));
              return;
            }
            final dynamic data = switch (o.path) {
              '/api/locator-slips/types' => [
                {
                  'code': 'locator',
                  'label': 'Locator / Official Business',
                  'is_active': true,
                },
                {
                  'code': 'work_from_home',
                  'label': 'Work From Home',
                  'is_active': true,
                  'coverage_mode': 'wfh',
                },
              ],
              '/api/locator-slips/context' => {'official_date': '2026-10-12'},
              '/api/locator-slips/submission-availability' => {
                'can_submit': true,
              },
              '/api/locator-slips/shift-coverage' => {
                'single_session': o.queryParameters['slip_date'] == '2026-10-13'
                    ? !single
                    : single,
                'can_file': true,
              },
              '/api/locator-slips/department-head/check' => {
                'isDeptHead': false,
              },
              _ => {'items': <dynamic>[], 'total': 0},
            };
            if (o.path == '/api/locator-slips/shift-coverage') {
              dates.add(o.queryParameters['slip_date'].toString());
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
          },
        ),
      );
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'employee',
            email: 'employee@test.com',
            role: 'employee',
            fullName: 'Employee',
          ),
        );
      final realtime = AppRealtimeProvider();
      addTearDown(auth.dispose);
      addTearDown(realtime.dispose);
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<AppRealtimeProvider>.value(value: realtime),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: EmployeeLocatorSlipContent()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('File Request').first);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (dates.isNotEmpty &&
              find.text('Applicable Time Segment(s)').evaluate().isNotEmpty) {
          break;
          }
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(dates, ['2026-10-12']);
      expect(ActiveApplicationReview.reply(), contains('Select at least one IN/OUT marker'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Name'), findsNothing);
      if (single) {
        expect(find.text('IN'), findsOneWidget);
        expect(find.text('OUT'), findsOneWidget);
        expect(find.text('AM OUT'), findsNothing);
      } else {
        expect(find.text('AM IN'), findsOneWidget);
        expect(find.text('AM OUT'), findsOneWidget);
        expect(find.text('PM IN'), findsOneWidget);
        await tester.tap(find.text('AM OUT'));
        await tester.tap(find.text('PM IN'));
      }
      failLookup = !single;
      await tester.tap(find.byType(EmployeeLocatorMobileDateField));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('13'));
      await tester.tap(find.text('OK'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (!single) {
        expect(find.text('Retry shift lookup'), findsOneWidget);
        expect(
          tester
              .widget<EmployeeLocatorMobileSegmentSelector>(
                find.byType(EmployeeLocatorMobileSegmentSelector),
              )
              .locked,
          isTrue,
        );
        await tester.tap(find.text('Retry shift lookup'));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      expect(dates.last, '2026-10-13');
      final selector = tester.widget<EmployeeLocatorMobileSegmentSelector>(
        find.byType(EmployeeLocatorMobileSegmentSelector),
      );
      expect(selector.singleSession, !single);
      if (!single) {
        expect(selector.amOut, isFalse);
        expect(selector.pmIn, isFalse);
        await tester.tap(find.text('Locator / Official Business').last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Work From Home').last);
        await tester.pump(const Duration(milliseconds: 300));
        final wfh = tester.widget<EmployeeLocatorMobileSegmentSelector>(
          find.byType(EmployeeLocatorMobileSegmentSelector),
        );
        expect(wfh.amIn, isTrue);
        expect(wfh.pmOut, isTrue);
        expect(wfh.amOut, isFalse);
        expect(wfh.pmIn, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
