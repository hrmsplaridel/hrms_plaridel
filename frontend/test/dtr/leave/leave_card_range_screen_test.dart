import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/employee_leave_card_view_screen.dart';

class _Repository extends MockLeaveRepository {
  int ledgerCalls = 0;
  bool failHistory = false;
  final offsets = <int>[];
  @override
  Future<LeaveRequestPage> listReviewRequestsPage({
    required LeaveRequestQuery query,
    required bool departmentHead,
  }) async =>
      const LeaveRequestPage(items: [], total: 0, limit: 200, offset: 0);
  @override
  Future<List<LeaveBalance>> getBalancesForUser(String userId) async => [
    LeaveBalance(
      userId: userId,
      leaveType: LeaveType.vacationLeave,
      earnedDays: 13.5,
      usedDays: 2,
    ),
    LeaveBalance(
      userId: userId,
      leaveType: LeaveType.sickLeave,
      earnedDays: 10,
      usedDays: 2,
    ),
  ];
  @override
  Future<LeaveLedgerResult> getLeaveLedger(LeaveLedgerQuery query) async {
    if (failHistory) throw StateError('Credit history is unavailable.');
    ledgerCalls++;
    offsets.add(query.offset);
    final rows = [
      _row('sep', 'earned', 1.25, '2026-10-01', 'monthly_accrual', {
        'target_year_month': '2026-09',
      }),
      _row('used', 'used', 2, '2026-09-15', 'adjustment', {}),
      _row('oct', 'earned', 1.25, '2026-11-01', 'monthly_accrual', {
        'service_month': '2026-10',
      }),
      _row(
        'sick',
        'used',
        2,
        '2026-10-10',
        'adjustment',
        {},
        type: 'sickLeave',
      ),
    ];
    // Deliberately return smaller pages than the requested size.
    return LeaveLedgerResult(
      total: 4,
      limit: 2,
      offset: query.offset,
      rows: rows.skip(query.offset).take(2).toList(),
      summaryEarned: 0,
      summaryUsed: 0,
      summaryPending: 0,
      summaryAdjusted: 0,
    );
  }
}

LeaveBalanceLedgerEntry _row(
  String id,
  String bucket,
  double days,
  String date,
  String action,
  Map<String, dynamic> meta, {
  String type = 'vacationLeave',
}) => LeaveBalanceLedgerEntry(
  id: id,
  userId: 'employee',
  leaveType: type,
  action: action,
  affectedBucket: bucket,
  daysChanged: days,
  actorKind: 'system',
  createdAt: DateTime.parse(date),
  metadataJson: meta,
);

void main() {
  setUpAll(() => ApiClient.instance.init());
  testWidgets('printing is disabled when credit history cannot load', (
    tester,
  ) async {
    final repository = _Repository()..failHistory = true;
    final provider = LeaveProvider(repository: repository);
    addTearDown(provider.dispose);
    LeaveTypeDefinitionCache.instance.invalidate();
    ApiClient.instance.dio.interceptors.clear();
    addTearDown(() => ApiClient.instance.dio.interceptors.clear());
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          h.resolve(
            Response(requestOptions: o, statusCode: 200, data: <dynamic>[]),
          );
        },
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<LeaveProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: EmployeeLeaveCardViewScreen(
            userId: 'employee',
            employeeName: 'Test Employee',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Credit history is unavailable.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.print_rounded),
          )
          .onPressed,
      isNull,
    );
  });
  for (final width in [1200.0, 390.0]) {
    testWidgets(
      'month range filters the complete history, validates dates and resets at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = _Repository();
        final provider = LeaveProvider(repository: repository);
        addTearDown(provider.dispose);
        LeaveTypeDefinitionCache.instance.invalidate();
        ApiClient.instance.dio.interceptors.clear();
        addTearDown(() => ApiClient.instance.dio.interceptors.clear());
        ApiClient.instance.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              expect(o.method, 'GET');
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: o.path.contains('/types')
                      ? <dynamic>[]
                      : {
                          'current_department_name': 'Human Resources',
                          'date_hired': '2026-01-01',
                        },
                ),
              );
            },
          ),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<LeaveProvider>.value(
            value: provider,
            child: const MaterialApp(
              home: EmployeeLeaveCardViewScreen(
                userId: 'employee',
                employeeName: 'Test Employee',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.offsets, [0, 2]);
        Future<void> select(String key, String month) async {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(OutlinedButton, month));
          await tester.pumpAndSettle();
        }

        await select('leave-card-from-month', 'Sep');
        await select('leave-card-to-month', 'Sep');
        expect(find.text('Period: Sep 2026 - Sep 2026'), findsOneWidget);
        expect(find.text('Balance brought forward'), findsOneWidget);
        expect(find.text('Closing balance'), findsOneWidget);
        expect(find.text('2026-10'), findsNothing);
        expect(find.text('10.25'), findsWidgets);
        expect(
          repository.ledgerCalls,
          2,
          reason: 'Changing the range must not write or reload credit data',
        );
        await select('leave-card-from-month', 'Oct');
        expect(
          find.text('From month must not be after To month.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.print_rounded),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('leave-card-all-records')));
        await tester.pumpAndSettle();
        expect(find.text('Period: All records'), findsOneWidget);
        expect(
          find.text('From month must not be after To month.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
