import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/employee_leave_actions.dart';

import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';

class _TestPrintLeaveProvider extends LeaveProvider {
  _TestPrintLeaveProvider({required super.repository});

  bool failRequestRefresh = false;
  bool failBalanceFetch = false;

  @override
  Future<LeaveRequest?> refreshRequestById(String id) async {
    if (failRequestRefresh) return null;
    return LeaveRequest(
      id: id,
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );
  }

  @override
  Future<List<LeaveBalance>> fetchBalancesForUserStrict(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (failBalanceFetch) throw Exception('Balance fetch failed');
    return [];
  }
}

void main() {
  testWidgets('employee CSC preview embeds the recorded department signature', (
    tester,
  ) async {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    Uint8List? captured;
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQUDAAAACkAGE0Zn1yAAAAAElFTkSuQmCC';
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          dynamic data;
          if (o.path == '/api/leave/signatories') {
            data = {
              'recommendation_officer': {
                'user_id': 'head',
                'name': 'Department Head',
                'position_title': 'Department Head',
              },
            };
          } else if (o.path.contains('/api/docutracker/sources/')) {
            data = {
              'source_module': 'dtr',
              'source_table': 'leave_requests',
              'source_record_id': 'req-1',
              'source_status': 'approved',
              'signatures': [
                {
                  'slot_key': 'department_head',
                  'signature_asset_id': 'asset',
                  'signed_by': 'head',
                  'signed_at': '2026-10-10T00:00:00Z',
                  'signature_image_base64': png,
                },
              ],
            };
          } else if (o.method == 'GET') {
            data = {'id': 'version', 'layout': 'csc', 'has_background': true};
          } else {
            final file = (o.data as FormData).files.single.value;
            final bytes = <int>[];
            await for (final chunk in file.finalize()) {
              bytes.addAll(chunk);
            }
            captured = Uint8List.fromList(bytes);
            data = bytes;
          }
          h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
        },
      ),
    );
    final provider = _TestPrintLeaveProvider(repository: MockLeaveRepository());
    addTearDown(provider.dispose);
    late BuildContext actionContext;
    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                actionContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    final request = LeaveRequest(
      id: 'req-1',
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );
    await tester.runAsync(() async {
      await EmployeeLeaveActions(
        context: actionContext,
        isMounted: () => captured == null,
      ).previewLeaveForm(request);
    });
    expect(captured, isNotNull);
    final unsigned = await tester.runAsync(() async {
      final document = await LeaveRequestPdf.buildPdf(
        request: (await provider.refreshRequestById('req-1'))!,
        balances: const [],
        recommendationOfficerName: 'Department Head',
        recommendationOfficerTitle: 'Department Head',
      );
      return document.save();
    });
    final images = RegExp(r'/Subtype\s*/Image');
    expect(
      images.allMatches(latin1.decode(captured!)).length,
      greaterThan(images.allMatches(latin1.decode(unsigned!)).length),
    );
  });

  testWidgets('Printing stops and shows error if request cannot be refreshed', (
    tester,
  ) async {
    final provider = _TestPrintLeaveProvider(repository: MockLeaveRepository());
    provider.failRequestRefresh = true;

    final request = LeaveRequest(
      id: 'req-1',
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    EmployeeLeaveActions(
                      context: context,
                      isMounted: () => true,
                    ).printLeaveForm(request);
                  },
                  child: const Text('Print'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Print'));
    await tester.pump(); // Start SnackBar animation
    await tester.pump(const Duration(seconds: 1)); // Wait for it to appear

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('request data could not be verified'),
      findsOneWidget,
    );
    expect(find.text('Loading form data...'), findsNothing);
  });

  testWidgets('Printing stops and shows error if balances cannot be fetched', (
    tester,
  ) async {
    final provider = _TestPrintLeaveProvider(repository: MockLeaveRepository());
    provider.failBalanceFetch = true;

    final request = LeaveRequest(
      id: 'req-1',
      userId: 'employee-a',
      leaveType: LeaveType.vacationLeave,
      status: LeaveRequestStatus.approved,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    EmployeeLeaveActions(
                      context: context,
                      isMounted: () => true,
                    ).printLeaveForm(request);
                  },
                  child: const Text('Print'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Print'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('balance or request data'), findsOneWidget);
    expect(find.text('Loading form data...'), findsNothing);
  });
}
