import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'a delayed reviewer lookup cannot expose approvals to the next account',
    (tester) async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      final oldLookup = Completer<void>();
      var oldAccount = true;
      var oldRequests = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            final previousUser = oldAccount;
            if (previousUser) {
              oldRequests++;
              await oldLookup.future;
            }
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: o.path.endsWith('/inbox')
                    ? [
                        if (previousUser)
                          {'id': 'old-request', 'kind': 'leave'},
                      ]
                    : {'can_review': false},
              ),
            );
          },
        ),
      );
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'reviewer',
            email: 'reviewer@example.test',
            role: 'employee',
          ),
        );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        ApiClient.instance.dio.interceptors.clear();
        auth.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: const MaterialApp(
            home: Scaffold(
              body: LeaveMain(
                initialSection: LeaveSection.approvals,
                employeeRequestsContent: Text('Personal requests'),
                adminApprovalsContent: Text('Reviewer queue'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(oldRequests, 2);
      oldAccount = false;
      auth.replaceUser(
        const AppUser(
          id: 'unassigned',
          email: 'unassigned@example.test',
          role: 'employee',
        ),
      );
      await tester.pumpAndSettle();
      oldLookup.complete();
      await tester.pumpAndSettle();
      expect(find.text('Personal requests'), findsOneWidget);
      expect(find.text('Approvals'), findsNothing);
      expect(find.text('Reviewer queue'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final access in [
    'none',
    'failed',
    'final',
    'workflow',
    'history',
    'department',
  ]) {
    testWidgets(
      'leave approval tab requires confirmed reviewer access: $access',
      (tester) async {
        ApiClient.instance.init();
        ApiClient.instance.dio.interceptors.clear();
        final pending = Completer<void>();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) async {
              await pending.future;
              if (access == 'failed') {
                h.reject(DioException(requestOptions: o));
                return;
              }
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: o.path.endsWith('/inbox')
                      ? [
                          if (access == 'workflow' || access == 'history')
                            {
                              'id': 'assigned',
                              'kind': 'leave',
                              'can_review': access == 'workflow',
                            },
                          {'id': 'other-module', 'kind': 'locator'},
                        ]
                      : {'can_review': access == 'final'},
                ),
              );
            },
          ),
        );
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(
              id: 'employee',
              email: 'employee@example.test',
              role: 'employee',
            ),
          );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          ApiClient.instance.dio.interceptors.clear();
          auth.dispose();
        });
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(
              home: Scaffold(
                body: LeaveMain(
                  initialSection: LeaveSection.approvals,
                  isDepartmentHead: access == 'department',
                  employeeRequestsContent: const Text('Personal requests'),
                  adminApprovalsContent: const Text('Reviewer queue'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (access != 'department') {
          expect(
            find.text('Approvals'),
            findsNothing,
            reason: 'Do not expose approvals before access is confirmed.',
          );
          expect(find.text('Reviewer queue'), findsNothing);
        }
        pending.complete();
        await tester.pumpAndSettle();
        final allowed = !['none', 'failed'].contains(access);
        expect(find.text('Approvals'), allowed ? findsOneWidget : findsNothing);
        expect(
          find.text('Reviewer queue'),
          allowed ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Personal requests'),
          allowed ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
