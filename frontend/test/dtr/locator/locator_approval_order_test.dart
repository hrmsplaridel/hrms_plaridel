import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

Map<String, dynamic> _record(String id, String name, String filed) => {
  'id': id, 'employee_id': 'applicant-$id', 'employee_name': name,
  // Deliberately different from filing time: movement date must not drive order.
  'slip_date': id == 'old' ? '2026-11-01' : '2026-09-01',
  'created_at': filed, 'updated_at': '2026-10-30T10:00:00Z',
  'request_type': 'locator', 'request_type_label': 'Locator',
  'office': 'Municipal Hall', 'reason': 'Official business',
  'am_in': true, 'status': 'approved',
};
Map<String, dynamic> _assigned(Map<String, dynamic> row) => {
  'kind': 'locator',
  'id': row['id'],
  'request_data': row,
};

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });

  for (final (width, departmentAccess) in [
    (1500.0, true),
    (390.0, true),
    (1500.0, false),
  ]) {
    testWidgets(
      'locator approvals stay newest first across sources, refresh and pages at $width, department access $departmentAccess',
      (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LocatorSlipDataCache.instance.invalidateAll();
        WorkflowInboxCache.instance.invalidate();
        ApiClient.instance.dio.interceptors.clear();
        final old = _record(
          'old',
          'Old history employee',
          '2026-09-23T10:00:00Z',
        );
        final duplicate = _record(
          'duplicate',
          'Duplicate employee',
          '2026-10-25T10:00:00Z',
        );
        final latest = _record(
          'new',
          'Latest employee',
          '2026-10-27T10:00:00Z',
        );
        final olderPage = _record(
          'older',
          'Older page employee',
          '2026-09-10T10:00:00Z',
        );
        final workflowPage = _record(
          'workflow-more',
          'Newest workflow employee',
          '2026-10-28T10:00:00Z',
        );
        var departmentCalls = 0;
        var workflowMoreCalls = 0;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              switch (o.uri.path) {
                case '/api/locator-slips/types':
                  data = [
                    {'code': 'locator', 'label': 'Locator', 'is_active': true},
                  ];
                case '/api/locator-slips/context':
                  data = {'official_date': '2026-10-27'};
                case '/api/locator-slips/department-head/check':
                  data = {
                    'isDeptHead': departmentAccess,
                    'canReviewPending': departmentAccess,
                    'hasReviewHistory': departmentAccess,
                  };
                case '/api/locator-slips/my':
                  data = {
                    'items': [],
                    'pagination': {'page': 1, 'page_count': 1, 'total': 0},
                  };
                case '/api/locator-slips/department-head':
                  departmentCalls++;
                  final page = int.parse(
                    o.uri.queryParameters['page'].toString(),
                  );
                  data = {
                    'items': page == 1 ? [old, duplicate] : [olderPage],
                    'pagination': {
                      'page': page,
                      'page_count': 2,
                      'page_size': 2,
                      'total': 3,
                    },
                  };
                case '/api/approval-workflows/inbox':
                  final more = o.uri.queryParameters['cursor'] != null;
                  if (more) {
                    expect(o.uri.queryParameters['cursor'], 'locator-next');
                    workflowMoreCalls++;
                  }
                  data = {
                    'items': more
                        ? [_assigned(workflowPage)]
                        : [
                            if (!departmentAccess) _assigned(old),
                            _assigned(latest),
                            _assigned(duplicate),
                          ],
                    'has_more': {'locator': !more, 'leave': false},
                    'next_cursor': {
                      'locator': more ? null : 'locator-next',
                      'leave': null,
                    },
                  };
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: data),
              );
            },
          ),
        );
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(
              id: 'head',
              email: 'head@test.local',
              role: 'employee',
            ),
          );
        final realtime = AppRealtimeProvider();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          ApiClient.instance.dio.interceptors.clear();
          LocatorSlipDataCache.instance.invalidateAll();
          WorkflowInboxCache.instance.invalidate();
          auth.dispose();
          realtime.dispose();
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: realtime),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: EmployeeLocatorSlipContent(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Approvals / History'));
        await tester.pumpAndSettle();

        void expectOrder(List<String> names) {
          for (final name in names) {
            expect(find.text(name), findsOneWidget);
          }
          for (var i = 1; i < names.length; i++) {
            expect(
              tester.getTopLeft(find.text(names[i - 1])).dy,
              lessThan(tester.getTopLeft(find.text(names[i])).dy),
              reason: names.join(' → '),
            );
          }
        }

        expectOrder([
          'Latest employee',
          'Duplicate employee',
          'Old history employee',
        ]);
        if (departmentAccess) {
          expect(find.text('Showing 3 of 4 requests'), findsOneWidget);
        }
        await tester.ensureVisible(find.byTooltip('Refresh locator requests'));
        await tester.tap(find.byTooltip('Refresh locator requests'));
        await tester.pumpAndSettle();
        expectOrder([
          'Latest employee',
          'Duplicate employee',
          'Old history employee',
        ]);
        expect(departmentCalls, departmentAccess ? 2 : 0);
        if (departmentAccess) {
          await tester.ensureVisible(find.text('Load More'));
          await tester.tap(find.text('Load More'));
          await tester.pumpAndSettle();
          expectOrder([
            'Latest employee',
            'Duplicate employee',
            'Old history employee',
            'Older page employee',
          ]);
          expect(find.text('4 of 4'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Load more workflow requests'));
        await tester.tap(find.text('Load more workflow requests'));
        await tester.pumpAndSettle();
        expectOrder([
          'Newest workflow employee',
          'Latest employee',
          'Duplicate employee',
          'Old history employee',
          if (departmentAccess) 'Older page employee',
        ]);
        expect(
          find.text(departmentAccess ? '5 of 5' : '4 of 4'),
          findsOneWidget,
        );
        expect(workflowMoreCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
