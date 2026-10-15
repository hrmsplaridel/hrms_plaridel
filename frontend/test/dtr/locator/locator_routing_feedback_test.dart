import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:provider/provider.dart';

class _SignedDepartment extends DocuTrackerProvider {
  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async => DocuTrackerSourceSignatureBundle(
    sourceModule: sourceModule,
    sourceTable: sourceTable,
    sourceRecordId: sourceRecordId,
    sourceStatus: 'pending_department_head',
    signatures: [
      DocuTrackerSourceSignature(
        slotKey: 'department_head',
        label: 'Department review',
        assignedSignerId: 'head',
        canSign: true,
        signedBy: 'head',
        signatureAssetId: 'asset',
        signatureImageBytes: Uint8List.fromList([1]),
        signedAt: DateTime(2026, 10, 15),
      ),
    ],
  );
}

Map<String, dynamic> _record(
  String id,
  String route, {
  String status = 'approved',
}) => {
  'id': id,
  'employee_name': 'Employee $id',
  'slip_date': '2026-10-15',
  'request_type': 'locator',
  'request_type_label': 'Locator',
  'office': 'Office $id',
  'reason': 'Official business',
  'am_in': true,
  'status': status,
  'final_review_route': route,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
    await TokenStorage.instance.getToken();
    await ClientDeviceHeader.build();
  });
  setUp(() {
    ApiClient.instance.dio.interceptors.clear();
    LocatorSlipDataCache.instance.invalidateAll();
  });

  Future<void> mount(
    WidgetTester tester,
    List<Map<String, dynamic>> Function() records, {
    Size size = const Size(1500, 1200),
    Map<String, dynamic>? decision,
  }) async {
    await tester.binding.setSurfaceSize(size);
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(
          id: 'head',
          email: 'head@test.local',
          role: 'employee',
          fullName: 'Department Reviewer',
        ),
      );
    final realtime = AppRealtimeProvider();
    final signatures = _SignedDepartment();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.uri.path;
          final dynamic data;
          if (path.endsWith('/department-head-approve')) {
            data = decision;
          } else if (path.endsWith('/types')) {
            // A current type configuration must not override a request's saved route.
            data = [
              {
                'code': 'locator',
                'label': 'Locator',
                'is_active': true,
                'approval_route': 'hr',
              },
            ];
          } else if (path.endsWith('/context')) {
            data = {'official_date': '2026-10-15'};
          } else if (path.endsWith('/department-head/check')) {
            data = {
              'isDeptHead': true,
              'canReviewPending': true,
              'hasReviewHistory': true,
            };
          } else if (path.endsWith('/department-head') ||
              path.endsWith('/my')) {
            final rows = path.endsWith('/my')
                ? <Map<String, dynamic>>[]
                : records();
            data = {
              'items': rows,
              'pagination': {
                'page': 1,
                'page_size': 50,
                'total': rows.length,
                'page_count': 1,
              },
            };
          } else {
            throw StateError('Unexpected API request: ${options.path}');
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ApiClient.instance.dio.interceptors.clear();
      auth.dispose();
      realtime.dispose();
      signatures.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: realtime),
          ChangeNotifierProvider<DocuTrackerProvider>.value(value: signatures),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EmployeeLocatorSlipContent()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approvals / History'));
    await tester.pumpAndSettle();
  }

  for (final width in [1500.0, 480.0]) {
    testWidgets('review history uses saved routes on width $width', (
      tester,
    ) async {
      await mount(
        tester,
        () => [
          _record('manual', 'mayor'),
          _record('direct', 'mayor_direct'),
          _record('hr', 'hr'),
        ],
        size: Size(width, 1200),
      );
      expect(find.text('Approved for manual Mayor signing'), findsOneWidget);
      expect(find.text('Approved by Mayor'), findsOneWidget);
      expect(find.text('Approved by HR'), findsOneWidget);
      // The shared filter describes all approved routes, rather than attributing them to HR.
      expect(find.text('Approved'), findsOneWidget);
      await tester.tap(find.text('Employee manual').first);
      await tester.pumpAndSettle();
      expect(find.text('Approved for manual Mayor signing'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final result in [
    (
      route: 'mayor',
      status: 'approved',
      message:
          'Department approved. Obtain the Mayor’s signature on the printed form.',
    ),
    (
      route: 'hr',
      status: 'pending_hr',
      message: 'Approved and sent to HR for final approval.',
    ),
    (
      route: 'mayor_direct',
      status: 'pending_mayor',
      message: 'Department approved. Awaiting Mayor approval.',
    ),
    (route: '', status: '', message: 'Request updated successfully.'),
  ]) {
    testWidgets(
      'department confirmation follows server result ${result.route}/${result.status}',
      (tester) async {
        await mount(
          tester,
          () => [_record('request', 'hr', status: 'pending_department_head')],
          decision: _record('request', result.route, status: result.status),
        );
        await tester.tap(find.textContaining('Office request').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await tester.pumpAndSettle();
        expect(find.text(result.message), findsOneWidget);
        if (result.route != 'hr') {
          expect(
            find.text('Approved and sent to HR for final approval.'),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
