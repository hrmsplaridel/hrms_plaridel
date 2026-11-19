import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_card_period_report.dart';

LeaveBalanceLedgerEntry movement(
  String id,
  String bucket,
  double days,
  String date, {
  String type = 'vacationLeave',
  String action = 'adjustment',
  Map<String, dynamic>? meta,
  String? request,
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
  relatedLeaveRequestId: request,
);

void main() {
  test(
    'older single-month ledger accrual is retained alongside newer postings',
    () {
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 8), DateTime(2026, 9)),
        vacationRemainingDays: 2.5,
        sickRemainingDays: 0,
        ledger: [
          movement(
            'legacy',
            'earned',
            1.25,
            '2026-09-01',
            action: 'monthly_accrual',
            meta: {'target_year_month': '2026-08'},
          ),
        ],
        accrualPostings: [
          LeaveAccrualPosting(
            leaveType: 'vacationLeave',
            serviceMonth: DateTime(2026, 9),
            creditedDays: 1.25,
          ),
        ],
      );
      expect(report.openingVacation, 0);
      expect(report.closingVacation, 2.5);
      expect(
        report.rows.where((r) => r.particulars == 'Monthly accrual'),
        hasLength(2),
      );
    },
  );
  test(
    'partially documented catch-up batch is refused instead of dropping credits',
    () {
      expect(
        () => LeaveCardPeriodReport.build(
          range: LeaveCardMonthRange(DateTime(2026, 7), DateTime(2026, 8)),
          vacationRemainingDays: 2.5,
          sickRemainingDays: 0,
          ledger: [
            movement(
              'batch',
              'earned',
              2.5,
              '2026-09-01',
              action: 'monthly_accrual',
              meta: {'target_year_month': '2026-08', 'months_credited': 2},
            ),
          ],
          accrualPostings: [
            LeaveAccrualPosting(
              leaveType: 'vacationLeave',
              serviceMonth: DateTime(2026, 8),
              creditedDays: 1.25,
            ),
          ],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'fully reversed DTR deduction is omitted and ISO service dates are accepted',
    () {
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 9), DateTime(2026, 9)),
        vacationRemainingDays: 10,
        sickRemainingDays: 0,
        ledger: [
          movement(
            'original',
            'used',
            1,
            '2026-10-01',
            action: 'attendance_deduction',
            meta: {'service_month': '2026-09-01'},
          ),
          movement(
            'reversed',
            'used',
            -1,
            '2026-11-01',
            action: 'attendance_deduction_adjusted',
            meta: {'service_month': '2026-09-01'},
          ),
        ],
      );
      expect(report.openingVacation, 10);
      expect(report.closingVacation, 10);
      expect(report.activityCount, 0);
      expect(report.rows, hasLength(2));
    },
  );
  test(
    'month range normalizes dates, includes December and rejects reversed ranges',
    () {
      final range = LeaveCardMonthRange(
        DateTime(2026, 12, 15),
        DateTime(2027, 1, 20),
      );
      expect(range.from, DateTime(2026, 12));
      expect(range.endExclusive, DateTime(2027, 2));
      expect(range.label, 'Dec 2026 - Jan 2027');
      expect(
        () => LeaveCardMonthRange(DateTime(2026, 10), DateTime(2026, 9)),
        throwsArgumentError,
      );
    },
  );
  test(
    'opening and closing exclude future credits and deductions, ignoring pending reservations',
    () {
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 9), DateTime(2026, 9)),
        vacationRemainingDays: 11.5,
        sickRemainingDays: 8,
        ledger: [
          movement(
            'sep',
            'earned',
            1.25,
            '2026-10-01',
            action: 'monthly_accrual',
            meta: {'target_year_month': '2026-09'},
          ),
          movement('used', 'used', 2, '2026-09-15'),
          movement(
            'oct',
            'earned',
            1.25,
            '2026-11-01',
            action: 'monthly_accrual',
            meta: {'service_month': '2026-10'},
          ),
          movement('pending', 'pending', 3, '2026-09-10'),
          movement('sick', 'used', 2, '2026-10-10', type: 'sickLeave'),
        ],
      );
      expect(report.openingVacation, 11);
      expect(report.closingVacation, 10.25);
      expect(report.openingSick, 10);
      expect(report.closingSick, 10);
      expect(report.rows.first.particulars, 'Balance brought forward');
      expect(report.rows.last.particulars, 'Closing balance');
      expect(report.rows.where((r) => r.period == '2026-10'), isEmpty);
      expect(report.rows.any((r) => r.vacEarned == '1.250'), isTrue);
    },
  );
  test(
    'actual postings split catch-up accrual and preserve corrections in the service month',
    () {
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 8), DateTime(2026, 8)),
        vacationRemainingDays: 12.95,
        sickRemainingDays: 0,
        ledger: [
          movement(
            'batch',
            'earned',
            2.5,
            '2026-09-01',
            action: 'monthly_accrual',
            meta: {'months_credited': 2, 'target_year_month': '2026-08'},
          ),
          movement(
            'deduct',
            'used',
            1,
            '2026-09-01',
            action: 'attendance_deduction',
            meta: {'service_month': '2026-08'},
          ),
          movement(
            'reverse',
            'used',
            -0.2,
            '2026-11-01',
            action: 'attendance_deduction_adjusted',
            meta: {'service_month': '2026-08'},
          ),
        ],
        accrualPostings: [
          LeaveAccrualPosting(
            leaveType: 'vacationLeave',
            serviceMonth: DateTime(2026, 7),
            creditedDays: 1.25,
          ),
          LeaveAccrualPosting(
            leaveType: 'vacationLeave',
            serviceMonth: DateTime(2026, 8),
            creditedDays: 1.25,
          ),
        ],
      );
      expect(report.openingVacation, 12.5);
      expect(report.closingVacation, 12.95);
      expect(
        report.rows
            .where((r) => r.particulars.startsWith('DTR'))
            .single
            .vacWithPay,
        '0.8',
      );
      expect(
        report.rows
            .where((r) => r.particulars == 'Monthly accrual')
            .single
            .vacEarned,
        '1.250',
      );
    },
  );
  test(
    'leave requests appear once with no invented accrual and separate paid/unpaid days',
    () {
      final request = LeaveRequest(
        id: 'req',
        userId: 'employee',
        leaveType: LeaveType.sickLeave,
        startDate: DateTime(2026, 9, 30),
        endDate: DateTime(2026, 10, 2),
        status: LeaveRequestStatus.approved,
        approvedDaysWithPay: 2,
        approvedDaysWithoutPay: 1,
      );
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 9), DateTime(2026, 9)),
        vacationRemainingDays: 0,
        sickRemainingDays: 8,
        requests: [request],
        ledger: [
          movement(
            'paid',
            'used',
            2,
            '2026-08-25',
            type: 'sickLeave',
            action: 'leave_approved',
            request: 'req',
          ),
          movement(
            'hold',
            'pending',
            -2,
            '2026-08-25',
            type: 'sickLeave',
            action: 'leave_approved',
            request: 'req',
          ),
        ],
      );
      final rows = report.rows
          .where((r) => r.particulars == 'Sick Leave')
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.slWithPay, '2');
      expect(rows.single.slWithoutPay, '1');
      expect(rows.single.slEarned, isEmpty);
      expect(report.openingSick, 10);
      expect(report.closingSick, 8);
    },
  );
  test(
    'empty month carries balances forward and ranges before verified opening are refused',
    () {
      final report = LeaveCardPeriodReport.build(
        range: LeaveCardMonthRange(DateTime(2026, 9), DateTime(2026, 9)),
        vacationRemainingDays: 15,
        sickRemainingDays: 7,
        ledger: [],
      );
      expect(report.activityCount, 0);
      expect(report.rows, hasLength(2));
      expect(report.closingVacation, 15);
      expect(
        () => LeaveCardPeriodReport.build(
          range: LeaveCardMonthRange(DateTime(2026, 7), DateTime(2026, 8)),
          vacationRemainingDays: 15,
          sickRemainingDays: 7,
          ledger: [
            movement(
              'opening',
              'adjusted',
              15,
              '2026-11-01',
              action: 'opening_balance',
              meta: {'cutoff_date': '2026-08-31'},
            ),
          ],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'ambiguous legacy catch-up history cannot produce a guessed historical balance',
    () {
      expect(
        () => LeaveCardPeriodReport.build(
          range: LeaveCardMonthRange(DateTime(2026, 7), DateTime(2026, 7)),
          vacationRemainingDays: 2.5,
          sickRemainingDays: 0,
          ledger: [
            movement(
              'batch',
              'earned',
              2.5,
              '2026-09-01',
              action: 'monthly_accrual',
              meta: {'months_credited': 2, 'target_year_month': '2026-08'},
            ),
          ],
        ),
        throwsStateError,
      );
    },
  );
}
