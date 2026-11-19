import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_card_period_report.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_card_print_view.dart';

void main() {
  test(
    'PDF contains only the selected period, balances, and every selected page',
    () async {
      final ledger = [
        for (var day = 1; day <= 20; day++)
          LeaveBalanceLedgerEntry(
            id: 'sep$day',
            userId: 'employee',
            leaveType: 'vacationLeave',
            action: 'adjustment',
            affectedBucket: 'adjusted',
            daysChanged: 1,
            actorKind: 'admin',
            createdAt: DateTime(2026, 9, day),
          ),
        LeaveBalanceLedgerEntry(
          id: 'oct',
          userId: 'employee',
          leaveType: 'vacationLeave',
          action: 'adjustment',
          affectedBucket: 'adjusted',
          daysChanged: 50,
          actorKind: 'admin',
          createdAt: DateTime(2026, 10, 1),
        ),
      ];
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 9), DateTime(2026, 9)),
        vacationRemainingDays: 80,
        sickRemainingDays: 5,
        ledger: ledger,
      );
      final bytes = await LeaveCardPrintView.buildPdf(
        employeeName: 'Range Test',
        officeDepartment: 'HR',
        requests: [],
        vacationRemainingDays: 80,
        sickRemainingDays: 5,
        periodReport: report,
      );
      expect(latin1.decode(bytes.take(4).toList()), '%PDF');
      final raw = latin1.decode(bytes);
      final streams = <String>[];
      for (final match in RegExp(
        r'stream\r?\n([\s\S]*?)\r?\nendstream',
      ).allMatches(raw)) {
        try {
          streams.add(
            latin1.decode(zlib.decode(latin1.encode(match.group(1)!))),
          );
        } catch (_) {}
      }
      final content = RegExp(
        r'\(((?:\\.|[^\\)])*)\)',
      ).allMatches(streams.join('\n')).map((m) => m.group(1)!).join(' ');
      expect(content, contains('Sep 2026 - Sep 2026'));
      expect(content, contains('Balance brought forward'));
      expect(content, contains('Closing balance'));
      expect(content, contains('2026-09'));
      expect(content, isNot(contains('2026-10')));
      expect(content.split(' '), isNot(contains('80')));
      expect(content.split(' '), contains('30'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(raw), hasLength(2));
      // Retain a disposable artifact for visual verification outside the test runner.
      await File(
        '${Directory.systemTemp.path}/unity-leave-card-range-test.pdf',
      ).writeAsBytes(bytes);
    },
  );
}
