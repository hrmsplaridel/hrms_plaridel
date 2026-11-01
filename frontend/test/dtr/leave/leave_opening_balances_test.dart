import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/desktop/pages/admin_leave_desktop_page.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_opening_balances_form.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });
  for (final width in [390.0, 1400.0]) {
    for (final alreadyRecorded in [false, true]) {
      testWidgets(
        'opening setup at $width; already recorded=$alreadyRecorded',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ApiClient.instance.dio.interceptors.clear();
          addTearDown(() => ApiClient.instance.dio.interceptors.clear());
          Map<String, dynamic>? posted;
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                if (o.method == 'POST') {
                  posted = Map<String, dynamic>.from(o.data as Map);
                }
                final dynamic data = o.path == '/api/employees'
                    ? {
                        'employees': [
                          {
                            'id': 'employee',
                            'full_name': 'Test Employee',
                            'current_department_name': 'HR',
                            'employment_type': 'permanent',
                            'leave_credit_eligible': true,
                          },
                        ],
                        'total': 1,
                      }
                    : o.path == '/api/departments'
                    ? [
                        {'name': 'HR'},
                      ]
                    : o.path == '/api/leave/types'
                    ? []
                    : o.path == '/api/leave/final-reviewer/me'
                    ? {'can_review': true}
                    : o.path == '/api/leave/admin/opening-balances'
                    ? {
                        'setups': alreadyRecorded
                            ? [
                                {
                                  'user_id': 'employee',
                                  'cutoff_date': '2026-10-31',
                                },
                              ]
                            : [],
                      }
                    : o.path.startsWith('/api/leave/admin/opening-balances/')
                    ? o.method == 'GET'
                          ? {
                              'setup': alreadyRecorded
                                  ? {'cutoff_date': '2026-10-31','qualifying_leave_days':3}
                                  : null,
                              'balances': [],
                              'official_date': '2026-11-01',
                            }
                          : {
                              'setup': {'cutoff_date': '2026-10-31'},
                            }
                    : {
                        'items': [],
                        'total': 0,
                        'departments': [],
                        'employees': [],
                      };
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: o.method == 'POST' ? 201 : 200,
                    data: data,
                  ),
                );
              },
            ),
          );
          final auth = AuthProvider()
            ..replaceUser(
              const AppUser(id: 'hr', email: 'hr@test.local', role: 'hr'),
            );
          final leave = LeaveProvider(repository: MockLeaveRepository()),
              realtime = AppRealtimeProvider();
          addTearDown(auth.dispose);
          addTearDown(leave.dispose);
          addTearDown(realtime.dispose);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<LeaveProvider>.value(value: leave),
                ChangeNotifierProvider<AppRealtimeProvider>.value(
                  value: realtime,
                ),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(child: AdminLeaveScreen()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More actions'));
          await tester.pumpAndSettle();
          expect(
            find.text('Opening leave balances'),
            findsNothing,
            reason:
                'Opening setup belongs inside the existing adjustment panel.',
          );
          await tester.tap(find.text('Manual balance adjustment'));
          await tester.pumpAndSettle();
          expect(find.text('Leave Balance Adjustment'), findsOneWidget);
          expect(find.text('Adjust existing balance'), findsOneWidget);
          final balanceTabs = tester.widget<TabBar>(
            find.byKey(const ValueKey('leave-balance-tabs')),
          );
          expect(balanceTabs.isScrollable, isTrue);
          expect(
            balanceTabs.indicator,
            const BoxDecoration(color: AppTheme.primaryNavy),
          );
          expect(balanceTabs.labelColor, Colors.white);
          expect(find.byType(ChoiceChip), findsNothing);
          expect(
            DefaultTabController.of(tester.element(find.byType(TabBar))).index,
            0,
          );
          await tester.ensureVisible(find.text('Opening balances'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Opening balances'));
          await tester.pumpAndSettle();
          expect(
            DefaultTabController.of(tester.element(find.byType(TabBar))).index,
            1,
          );
          expect(
            find.byTooltip('Close'),
            findsOneWidget,
            reason: 'The shared panel has one header/close control.',
          );
          await tester.tap(find.text('Test Employee'));
          await tester.pumpAndSettle();
          if (alreadyRecorded) {
            expect(
              find.textContaining('Choose Adjust existing balance'),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Save opening balances'),
                  )
                  .onPressed,
              isNull,
            );
            expect(find.byKey(const ValueKey('opening-sl')), findsNothing);
            expect(posted, isNull);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            return;
          }
          expect(find.text('2026-10-31'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('opening-sl')),
            '25',
          );
          await tester.enterText(
            find.byKey(const ValueKey('opening-vl')),
            '30',
          );
          await tester.enterText(find.byKey(const ValueKey('opening-qualifying-days')), '3');
          await tester.enterText(
            find.byKey(const ValueKey('opening-reason')),
            'Verified against HR leave card',
          );
          await tester.ensureVisible(find.text('Adjust existing balance'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Adjust existing balance'));
          await tester.pumpAndSettle();
          expect(
            DefaultTabController.of(tester.element(find.byType(TabBar))).index,
            0,
          );
          expect(find.text('Apply adjustment'), findsOneWidget);
          await tester.ensureVisible(find.text('Opening balances'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Opening balances'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextFormField>(find.byKey(const ValueKey('opening-sl')))
                .controller!
                .text,
            '25',
          );
          await tester.ensureVisible(find.text('Save opening balances'));
          await tester.tap(find.text('Save opening balances'));
          await tester.pumpAndSettle();
          expect(posted, isNull);
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save opening balances'));
          await tester.pumpAndSettle();
          expect(posted?['sick_leave_days'], 25);
          expect(posted?['vacation_leave_days'], 30);
          expect(posted?['qualifying_leave_days'], 3);
          expect(posted?['cutoff_date'], '2026-10-31');
          expect(posted?['confirmed'], true);
          expect(find.text('Leave balance saved.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final width in [390.0, 1100.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('opening employee filters at $width in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        final rows = [
          {
            'id': 'alice',
            'full_name': 'Alice Cruz',
            'employee_number': 'HR001',
            'current_department_name': 'Human Resources',
            'current_position_name': 'HR Manager',
            'employment_type': 'permanent',
          },
          {
            'id': 'bob',
            'full_name': 'Bob Reyes',
            'employee_number': 'ACC002',
            'current_department_name': 'Accounting',
            'current_position_name': 'Accountant',
            'employment_type': 'regular',
          },
          {
            'id': 'cara',
            'full_name': 'Cara Santos',
            'employee_number': 'HR003',
            'current_department_name': 'Human Resources',
            'current_position_name': 'Payroll Officer',
            'employment_type': 'temporary',
          },
          for (var i = 1; i <= 17; i++)
            {
              'id': 'extra-$i',
              'full_name': 'Employee $i',
              'employee_number': 'EX$i',
              'current_department_name': 'Human Resources',
              'employment_type': 'permanent',
            },
        ];
        var statusLoads = 0;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data;
              if (o.path == '/api/employees') {
                data = {'employees': rows, 'total': rows.length};
              } else if (o.path == '/api/leave/admin/opening-balances') {
                statusLoads++;
                data = {
                  'setups': [
                    {'user_id': 'bob', 'cutoff_date': '2026-10-31'},
                  ],
                };
              } else {
                data = {
                  'setup': {'cutoff_date': '2026-10-31'},
                  'balances': [],
                  'official_date': '2026-11-01',
                };
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: data),
              );
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: AdminLeaveOpeningBalancesForm(onSavingChanged: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 of 20 opening balances recorded'), findsOneWidget);
        expect(find.text('Showing 20 of 20 employees'), findsOneWidget);
        expect(find.text('Human Resources · HR Manager'), findsOneWidget);
        expect(find.text('Permanent'), findsWidgets);
        final department = find.byKey(
          const ValueKey('opening-department-filter'),
        );
        await tester.tap(department);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Human Resources').last);
        await tester.pumpAndSettle();
        expect(find.text('Bob Reyes'), findsNothing);
        expect(find.text('0 of 19 opening balances recorded'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('opening-employee-search')),
          'HR003',
        );
        await tester.pumpAndSettle();
        expect(find.text('Cara Santos'), findsOneWidget);
        expect(find.text('Alice Cruz'), findsNothing);
        expect(find.text('Showing 1 of 20 employees'), findsOneWidget);
        await tester.tap(find.text('Clear filters'));
        await tester.pumpAndSettle();
        final status = find.byKey(const ValueKey('opening-status-filter'));
        await tester.tap(status);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Recorded').last);
        await tester.pumpAndSettle();
        expect(find.text('Bob Reyes'), findsOneWidget);
        expect(find.text('Alice Cruz'), findsNothing);
        await tester.tap(find.text('Bob Reyes'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Choose Adjust existing balance'),
          findsOneWidget,
        );
        await tester.tap(find.text('Change employee'));
        await tester.pumpAndSettle();
        expect(find.text('Bob Reyes'), findsOneWidget);
        expect(find.text('Alice Cruz'), findsNothing);
        await tester.tap(status);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not recorded').last);
        await tester.pumpAndSettle();
        expect(find.text('Bob Reyes'), findsNothing);
        expect(find.text('Alice Cruz'), findsOneWidget);
        await tester.tap(department);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accounting').last);
        await tester.pumpAndSettle();
        expect(find.text('No employees match these filters.'), findsOneWidget);
        await tester.tap(find.text('Clear filters'));
        await tester.pumpAndSettle();
        final filterPosition = tester.getTopLeft(department);
        await tester.drag(
          find.byKey(const ValueKey('opening-employee-list')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(department), filterPosition);
        expect(
          statusLoads,
          1,
          reason:
              'Filtering uses one bulk status lookup, not a request for each row.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'recording status failure has retry and never labels employees as unrecorded',
    (tester) async {
      ApiClient.instance.dio.interceptors.clear();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      var fail = true;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.path == '/api/leave/admin/opening-balances' && fail) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: o,
                    statusCode: 500,
                    data: {
                      'error':
                          'Unable to load opening balance recording status.',
                    },
                  ),
                ),
              );
              return;
            }
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: o.path == '/api/employees'
                    ? {
                        'employees': [
                          {
                            'id': 'employee',
                            'full_name': 'Test Employee',
                            'employment_type': 'permanent',
                          },
                        ],
                        'total': 1,
                      }
                    : {'setups': []},
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminLeaveOpeningBalancesForm(onSavingChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Employee'), findsNothing);
      expect(find.text('Not recorded'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Test Employee'), findsOneWidget);
      expect(find.text('0 of 1 opening balances recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('legacy opening verifies usage without posting credit balances', (tester) async {
    ApiClient.instance.dio.interceptors.clear();
    addTearDown(()=>ApiClient.instance.dio.interceptors.clear());
    Map<String,dynamic>? posted;
    String? path;
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      if(o.method=='POST'){posted=Map<String,dynamic>.from(o.data as Map);path=o.path;}
      h.resolve(Response(requestOptions:o,statusCode:200,data:o.path=='/api/employees'
        ? {'employees':[{'id':'employee','full_name':'Test Employee','employment_type':'permanent'}],'total':1}
        : o.path=='/api/leave/admin/opening-balances' ? {'setups':[{'user_id':'employee','cutoff_date':'2026-10-31'}]}
        : {'setup':{'cutoff_date':'2026-10-31','qualifying_leave_days':null},'balances':[],'official_date':'2026-11-01'}));
    }));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:AdminLeaveOpeningBalancesForm(onSavingChanged:(_) {}))));
    await tester.pumpAndSettle();await tester.tap(find.text('Test Employee'));await tester.pumpAndSettle();
    expect(find.textContaining('Needs history review.'),findsOneWidget);
    expect(find.byKey(const ValueKey('opening-sl')),findsNothing);
    await tester.enterText(find.byKey(const ValueKey('opening-qualifying-days')),'3');
    await tester.enterText(find.byKey(const ValueKey('opening-usage-reference')),'HR card verified');
    await tester.ensureVisible(find.byType(CheckboxListTile));await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save verified usage'));await tester.pumpAndSettle();
    expect(path,'/api/leave/admin/opening-balances/employee/usage');
    expect(posted?['qualifying_leave_days'],3);expect(posted?['cutoff_date'],'2026-10-31');
    expect(posted?.containsKey('sick_leave_days'),false);expect(posted?.containsKey('vacation_leave_days'),false);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
