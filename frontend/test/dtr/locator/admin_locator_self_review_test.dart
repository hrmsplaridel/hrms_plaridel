import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_signature_section.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflow_summary.dart';

class _Signatures extends DocuTrackerProvider {
  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async => null;
}

void main() {
  setUpAll(() => ApiClient.instance.init());
  testWidgets(
    'direct Mayor rejection identifies the Mayor in details and legacy history',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LocatorSlipDataCache.instance.invalidateAll();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            dynamic data = <dynamic>[];
            if (o.uri.path.endsWith('/final-reviewer/me')) {
              data = {'can_review': true};
            }
            if (o.uri.path.endsWith('/admin')) {
              data = [
                {
                  'id': 'mayor-request',
                  'employee_id': 'other',
                  'employee_name': 'Test Applicant',
                  'status': 'rejected_by_hr',
                  'final_review_route': 'mayor_direct',
                  'slip_date': '2026-10-15',
                  'hr_reviewer_name': 'Current Mayor',
                  'hr_remarks': 'Destination not permitted',
                  'hr_reviewed_at': '2026-10-15T08:00:00Z',
                  'am_in': true,
                },
              ];
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
          },
        ),
      );
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'reviewer',
            email: 'reviewer@test.local',
            role: 'admin',
          ),
        );
      final realtime = AppRealtimeProvider();
      final signatures = _Signatures();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        ApiClient.instance.dio.interceptors.clear();
        auth.dispose();
        realtime.dispose();
        signatures.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: realtime),
            ChangeNotifierProvider<DocuTrackerProvider>.value(
              value: signatures,
            ),
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
      expect(find.text('Rejected by Mayor'), findsOneWidget);
      await tester.tap(find.text('Test Applicant').first);
      await tester.pumpAndSettle();
      expect(find.text('Mayor Reviewer'), findsOneWidget);
      expect(find.text('Mayor Remarks'), findsOneWidget);
      expect(find.text('HR Reviewer'), findsNothing);
      expect(find.byType(LocatorSignatureSection), findsNothing);
      expect(find.byType(ApprovalWorkflowSummary), findsNothing);
      expect(find.text('Signatures'), findsNothing);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Rejected by Mayor'), findsWidgets);
      expect(find.text('Rejected by HR'), findsNothing);
    },
  );
  for (final policy in [
    ('employee', true, false),
    ('admin', true, true),
    ('both', true, true),
    ('admin', false, false),
  ]) {
    testWidgets('staff filing action respects type policy $policy', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LocatorSlipDataCache.instance.invalidateRequests();
      LocatorSlipDataCache.instance.invalidateTypes();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            dynamic data = <dynamic>[];
            if (o.path.contains('/types')) {
              data = [
                {
                  'code': 'test_type',
                  'label': 'Test type',
                  'filing_access': policy.$1,
                  'is_active': policy.$2,
                },
              ];
            } else if (o.path.endsWith('/final-reviewer/me')) {
              data = {'can_review': true};
            }
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
          },
        ),
      );
      final auth = AuthProvider()
        ..replaceUser(
          const AppUser(
            id: 'reviewer',
            email: 'reviewer@test.local',
            role: 'admin',
          ),
        );
      final realtime = AppRealtimeProvider();
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
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(
        find.text('File for employees'),
        policy.$3 ? findsOneWidget : findsNothing,
      );
      expect(find.text('Record Correction'), findsOneWidget);
      expect(find.text('Manage Types'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      realtime.dispose();
    });
  }
  for (final own in [true, false]) {
    testWidgets(
      'locator details ${own ? "hide own" : "allow another employee"} review actions',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LocatorSlipDataCache.instance.invalidateRequests();
        LocatorSlipDataCache.instance.invalidateTypes();
        ApiClient.instance.dio.interceptors.clear();
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              dynamic data = <dynamic>[];
              if (o.path.endsWith('/final-reviewer/me')) {
                data = <String, dynamic>{'can_review': true};
              }
              if (o.path.contains('/admin')) {
                data = [
                  {
                    'id': 'request',
                    'employee_id': own ? 'reviewer' : 'other',
                    'employee_name': 'Test Applicant',
                    'status': 'pending_hr',
                    'slip_date': '2027-11-02',
                    'reason': 'Test',
                    'am_in': true,
                  },
                ];
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
              id: 'reviewer',
              email: 'reviewer@test.local',
              role: 'admin',
            ),
          );
        final realtime = AppRealtimeProvider();
        final signatures = _Signatures();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              ChangeNotifierProvider.value(value: realtime),
              ChangeNotifierProvider<DocuTrackerProvider>.value(
                value: signatures,
              ),
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
        await tester.tap(find.text('Test Applicant').first);
        await tester.pumpAndSettle();
        expect(find.text('Approve'), own ? findsNothing : findsOneWidget);
        expect(find.text('Reject'), own ? findsNothing : findsOneWidget);
        if (own) {
          expect(find.text('Return'), findsNothing);
          expect(
            find.text('Another assigned reviewer must review your request.'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        realtime.dispose();
        signatures.dispose();
      },
    );
  }
}
