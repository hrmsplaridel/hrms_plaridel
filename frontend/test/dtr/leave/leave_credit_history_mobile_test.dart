import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_balance_history_screen.dart';

class _LedgerRepository extends MockLeaveRepository {
  final queries = <LeaveLedgerQuery>[];
  bool populated = false;

  @override
  Future<LeaveLedgerResult> getLeaveLedger(LeaveLedgerQuery query) async {
    queries.add(query);
    return LeaveLedgerResult(
      total: populated ? 26 : 0,
      limit: query.limit,
      offset: query.offset,
      rows: populated
          ? [
              LeaveBalanceLedgerEntry(
                id: 'entry-${query.offset}',
                userId: 'employee',
                leaveType: 'sickLeave',
                action: 'monthly_accrual',
                affectedBucket: 'earned',
                daysChanged: 1.25,
                actorKind: 'system',
                createdAt: DateTime(2026, 11, 1),
              ),
            ]
          : [],
      summaryEarned: 1250.5,
      summaryAdjusted: -2,
      summaryUsed: 5,
      summaryPending: 1,
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _LedgerRepository repository, {
  required Size size,
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AppRealtimeProvider()),
        ChangeNotifierProvider(
          create: (_) => LeaveProvider(repository: repository),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const LeaveBalanceHistoryScreen(isAdmin: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [
    (size: const Size(360, 740), scale: 1.0),
    (size: const Size(320, 568), scale: 1.0),
    (size: const Size(390, 844), scale: 1.5),
    (size: const Size(568, 320), scale: 1.3),
    (size: const Size(1100, 800), scale: 1.0),
  ]) {
    testWidgets(
      'credit history stays readable at ${scenario.size}, scale ${scenario.scale}',
      (tester) async {
        await _mount(
          tester,
          _LedgerRepository(),
          size: scenario.size,
          scale: scenario.scale,
        );
        expect(tester.takeException(), isNull);
        for (final caption in ['Earned', 'Adjusted', 'Used', 'Pending']) {
          final text = find.text(caption).first;
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(
            paragraph.size.height,
            lessThanOrEqualTo(12 * 1.2 * scenario.scale + 1),
            reason: '$caption must stay on one readable line',
          );
        }
        for (final amount in ['1250.5 Days', '-2 Days', '5 Days', '1 Days']) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(amount))
                .didExceedMaxLines,
            isFalse,
            reason: '$amount must be readable without truncation',
          );
        }
        final earned = tester.getTopLeft(find.text('Earned').first);
        final used = tester.getTopLeft(find.text('Used').first);
        if (scenario.size.width == 360) expect(used.dy, greaterThan(earned.dy));
        if (scenario.size.width == 1100) expect(used.dy, earned.dy);
        await tester.scrollUntilVisible(find.text('No leave activity yet.'), 200);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'mobile filters remain visible and filtering, refresh and pagination still work',
    (tester) async {
      final repository = _LedgerRepository()..populated = true;
      await _mount(
        tester,
        repository,
        size: const Size(360, 740),
        brightness: Brightness.light,
      );
      final adjusted = find.widgetWithText(ChoiceChip, 'Adjusted');
      expect(tester.getRect(adjusted).right, lessThanOrEqualTo(360));
      expect(tester.getRect(adjusted).left, greaterThanOrEqualTo(0));
      await tester.tap(adjusted);
      await tester.pumpAndSettle();
      expect(repository.queries.last.affectedBucket, 'adjusted');
      expect(repository.queries.last.offset, 0);
      expect(find.text('1250.5 Days'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Next'));
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.offset, 25);
      expect(repository.queries.last.affectedBucket, 'adjusted');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.offset, 0);
      expect(repository.queries.last.hideZeroPending, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
