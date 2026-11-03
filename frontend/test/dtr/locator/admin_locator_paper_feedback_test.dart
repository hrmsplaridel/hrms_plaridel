import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/widgets/admin_locator_filing_dialog.dart';

void main() {
  for (final recorded in [true, false]) {
    testWidgets(
      'paper panel ${recorded ? "confirms saved record before queue refresh finishes" : "cancellation does not show success"}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        LocatorSlipDataCache.instance.invalidateAll();
        final refresh = Completer<void>();
        var queueReads = 0;
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              dynamic data = <dynamic>[];
              if (options.uri.path.contains('/types')) {
                data = [
                  {'code': 'locator', 'label': 'Locator', 'is_active': true},
                ];
              } else if (options.uri.path.endsWith('/final-reviewer/me')) {
                data = {'can_review': true};
              } else if (options.uri.path.endsWith('/context')) {
                data = {'official_date': '2026-10-28'};
              } else if (options.uri.path.endsWith('/filing-employees')) {
                data = {'employees': [], 'total': 0};
              } else if (options.uri.path.endsWith('/admin')) {
                queueReads++;
                if (queueReads > 1) await refresh.future;
              }
              handler.resolve(
                Response(requestOptions: options, statusCode: 200, data: data),
              );
            },
          ),
        );
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(
              id: 'encoder',
              email: 'encoder@test.local',
              role: 'hr',
            ),
          );
        final realtime = AppRealtimeProvider();
        addTearDown(() async {
          if (!refresh.isCompleted) refresh.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          ApiClient.instance.dio.interceptors.clear();
          LocatorSlipDataCache.instance.invalidateAll();
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
                  child: AdminLocatorManagementScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(queueReads, 1);
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record approved paper locator'));
        await tester.pumpAndSettle();
        final panel = find.byType(AdminLocatorFilingDialog);
        expect(panel, findsOneWidget);
        // The full paper-form test verifies this result is returned only after POST succeeds.
        Navigator.of(tester.element(panel)).pop(recorded);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(SnackBar), recorded ? findsOneWidget : findsNothing);
        expect(
          find.text('Approved paper locator recorded successfully.'),
          recorded ? findsOneWidget : findsNothing,
        );
        if (recorded) {
          expect(
            queueReads,
            2,
            reason: 'Saving also refreshes the management queue',
          );
          refresh.complete();
          await tester.pumpAndSettle();
          expect(
            find.text('Approved paper locator recorded successfully.'),
            findsOneWidget,
          );
        } else {
          expect(queueReads, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
