import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/client_device_header.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/shared/pages/employee_locator_slip_content.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

class _Signatures extends DocuTrackerProvider {
  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async => DocuTrackerSourceSignatureBundle(
    sourceModule: sourceModule,
    sourceTable: sourceTable,
    sourceRecordId: sourceRecordId,
    sourceStatus: 'pending_hr',
    signatures: const [],
  );
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });
  for (final width in [1500.0, 390.0]) {
    for (final stage in [0, 1, 2, -1, 3, 4]) {
      testWidgets(
        'employee locator shows workflow stage $stage at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1300);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LocatorSlipDataCache.instance.invalidateAll();
          ApiClient.instance.dio.interceptors.clear();
          final labels = [
            stage == 4
                ? 'Department Head Review and Verification of Official Travel and Attendance Requests'
                : 'Department Review',
            'HR Review',
            'Mayor Approval',
          ];
          final record = <String, dynamic>{
            'id': 'request',
            'employee_id': 'employee',
            'employee_name': 'Applicant',
            'slip_date': '2026-10-19',
            'request_type': 'test',
            'request_type_label': 'Test',
            'office': 'Target office',
            'reason': 'Official business',
            'am_in': true,
            'status': stage == 3
                ? 'approved'
                : stage == 2
                ? 'pending_mayor'
                : 'pending_hr',
            'final_review_route': 'hr',
            if (stage >= 0)
              'workflow_snapshot': {
                'name': 'Department → HR → Mayor',
                'version': 1,
                'current_step': stage == 4 ? 0 : stage,
                'steps': [
                  for (final label in labels) {'label': label},
                ],
                if (stage == 3) 'outcome': 'approved',
              },
          };
          ApiClient.instance.dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                final path = o.uri.path;
                dynamic data = <dynamic>[];
                if (path.endsWith('/my')) {
                  data = {
                    'items': [record],
                    'pagination': {
                      'page': 1,
                      'page_size': 50,
                      'total': 1,
                      'page_count': 1,
                    },
                  };
                }
                if (path.endsWith('/department-head/check')) {
                  data = {
                    'isDeptHead': false,
                    'canReviewPending': false,
                    'hasReviewHistory': false,
                  };
                }
                if (path.endsWith('/context')) {
                  data = {'official_date': '2026-10-17'};
                }
                if (path.endsWith('/types')) {
                  data = [
                    {'code': 'test', 'label': 'Test', 'is_active': true},
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
                id: 'employee',
                email: 'employee@example.test',
                role: 'employee',
                fullName: 'Applicant',
              ),
            );
          final realtime = AppRealtimeProvider();
          final signatures = _Signatures();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            ApiClient.instance.dio.interceptors.clear();
            LocatorSlipDataCache.instance.invalidateAll();
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
                    child: EmployeeLocatorSlipContent(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expected = stage == -1
              ? 'Pending HR Admin'
              : stage == 3
              ? 'Approved by HR'
              : 'Pending ${labels[stage == 4 ? 0 : stage]}';
          expect(find.text(expected), findsOneWidget);
          await tester.tap(find.textContaining('Target office').first);
          await tester.pumpAndSettle();
          expect(find.text(expected), findsWidgets);
          if (stage == 0) expect(find.text('Pending HR Admin'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
