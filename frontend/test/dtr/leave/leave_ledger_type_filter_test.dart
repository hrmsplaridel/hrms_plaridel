import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_balance_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'ledger includes custom and inactive types and sends their keys',
    (tester) async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      LeaveTypeDefinitionCache.instance.invalidate();
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      addTearDown(LeaveTypeDefinitionCache.instance.invalidate);
      final queries = <Map<String, dynamic>>[];
      var includeInactive = false;
      var addedType = false;
      var failTypes = false;
      var catalogReads = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            dynamic data = <dynamic>[];
            if (o.uri.path == '/api/leave/types') {
              catalogReads++;
              if (failTypes) {
                h.reject(DioException(requestOptions: o));
                return;
              }
              includeInactive = o.queryParameters['include_inactive'] == '1';
              data = [
                {'name': 'Wellness', 'display_name': 'Wellness Leave'},
                {
                  'name': 'legacyCustom',
                  'display_name': 'Legacy Custom Leave',
                  'is_active': false,
                },
                if (addedType)
                  {'name': 'newCustom', 'display_name': 'New Custom Leave'},
              ];
            }
            if (o.uri.path == '/api/leave/ledger') {
              queries.add(Map.from(o.queryParameters));
              data = {
                'total': 114,
                'rows': [
                  {
                    'id': 'movement',
                    'user_id': 'employee',
                    'employee_name': 'Ledger Employee',
                    'leave_type': 'Wellness',
                    'action': 'balance_adjustment',
                    'affected_bucket': 'adjusted',
                    'days_changed': 1,
                    'created_at': '2026-10-11T00:00:00Z',
                  },
                ],
                'summary': {},
              };
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
          },
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => AppRealtimeProvider()),
            ChangeNotifierProvider(
              create: (_) => LeaveProvider(repository: ApiLeaveRepository()),
            ),
          ],
          child: const MaterialApp(
            home: LeaveBalanceHistoryScreen(isAdmin: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Records: 114'), findsOneWidget);
      expect(queries.last['hide_zero_pending'], 'true');
      for (final label in ['Earned:', 'Used:', 'Pending:', 'Adjusted:']) {
        expect(find.textContaining(label), findsNothing);
      }
      expect(find.text('Wellness Leave · Ledger Employee'), findsOneWidget);
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String?> &&
            w.decoration.labelText == 'Leave type',
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Wellness Leave'), findsWidgets);
      expect(find.text('Legacy Custom Leave'), findsOneWidget);
      expect(includeInactive, isTrue);
      await tester.tap(find.text('Wellness Leave').last);
      await tester.pumpAndSettle();
      expect(queries.last['leave_type'], 'Wellness');
      expect(catalogReads, 1, reason: 'Filtering reuses the catalog');
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(catalogReads, 1, reason: 'Pagination reuses the catalog');
      addedType = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(catalogReads, 2);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('New Custom Leave'), findsOneWidget);
      await tester.tap(find.text('New Custom Leave'));
      await tester.pumpAndSettle();
      expect(queries.last['leave_type'], 'newCustom');
      failTypes = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not refresh leave types. Use Refresh to retry.'),
        findsOneWidget,
      );
      expect(find.text('Wellness Leave · Ledger Employee'), findsOneWidget);
      expect(queries.last['leave_type'], 'newCustom');
      expect(tester.takeException(), isNull);
    },
  );
}
