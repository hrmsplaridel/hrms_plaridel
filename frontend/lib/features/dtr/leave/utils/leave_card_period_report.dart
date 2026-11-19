import '../models/leave_balance_ledger.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';

const leaveCardMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class LeaveCardMonthRange {
  LeaveCardMonthRange(DateTime from, DateTime to)
    : from = DateTime(from.year, from.month),
      to = DateTime(to.year, to.month) {
    if (this.from.isAfter(this.to) || from.year < 1900 || to.year > 9999) {
      throw ArgumentError('From month must not be after To month.');
    }
  }
  final DateTime from;
  final DateTime to;
  DateTime get endExclusive => DateTime(to.year, to.month + 1);
  String get label =>
      '${leaveCardMonthLabel(from)} - ${leaveCardMonthLabel(to)}';
}

String leaveCardMonthLabel(DateTime date) =>
    '${leaveCardMonths[date.month - 1]} ${date.year}';
String leaveCardNumber(double value) => (value.abs() < 0.0005 ? 0.0 : value)
    .toStringAsFixed(3)
    .replaceFirst(RegExp(r'\.?0+$'), '');
String _date(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
String _month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
double _rounded(double value) => double.parse(value.toStringAsFixed(3));

/// A single read-only projection shared by the card preview and PDF.
class LeaveCardPeriodRow {
  const LeaveCardPeriodRow({
    required this.period,
    required this.particulars,
    this.vacEarned = '',
    this.vacWithPay = '',
    this.vacBalance = '',
    this.vacWithoutPay = '',
    this.slEarned = '',
    this.slWithPay = '',
    this.slBalance = '',
    this.slWithoutPay = '',
    this.dateTakenOnApplication = '',
  });
  final String period,
      particulars,
      vacEarned,
      vacWithPay,
      vacBalance,
      vacWithoutPay,
      slEarned,
      slWithPay,
      slBalance,
      slWithoutPay,
      dateTakenOnApplication;
}

class LeaveCardPeriodReport {
  const LeaveCardPeriodReport._({
    required this.range,
    required this.rows,
    required this.openingVacation,
    required this.openingSick,
    required this.closingVacation,
    required this.closingSick,
    required this.activityCount,
  });
  final LeaveCardMonthRange range;
  final List<LeaveCardPeriodRow> rows;
  final double openingVacation, openingSick, closingVacation, closingSick;
  final int activityCount;

  factory LeaveCardPeriodReport.build({
    required LeaveCardMonthRange range,
    required double vacationRemainingDays,
    required double sickRemainingDays,
    required List<LeaveBalanceLedgerEntry> ledger,
    List<LeaveRequest> requests = const [],
    List<LeaveAccrualPosting> accrualPostings = const [],
    Map<String, String> balanceLedgerTypes = const {},
  }) {
    final requestById = {
      for (final r in requests)
        if (r.id != null) r.id!: r,
    };
    final postings = accrualPostings
        .where((p) => _creditTypes.contains(p.leaveType))
        .toList();
    final postedMonths = postings
        .map((p) => '${p.leaveType}|${_month(p.serviceMonth)}')
        .toSet();
    final movements = <_Movement>[];
    final usedRequestIds = <String>{};
    final sorted = [...ledger]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final e in sorted) {
      if (!_creditTypes.contains(e.leaveType) ||
          !['earned', 'used', 'adjusted'].contains(e.affectedBucket)) {
        continue;
      }
      final meta = e.metadataJson ?? const <String, dynamic>{};
      final cutoff = DateTime.tryParse('${meta['cutoff_date']}');
      if (e.action == 'opening_balance' &&
          cutoff != null &&
          !range.from.isAfter(cutoff)) {
        throw StateError(
          'Verified opening credits cover dates through ${_date(cutoff)}. Select a later From month.',
        );
      }
      final accrual =
          e.action == 'monthly_accrual' ||
          e.action == 'monthly_accrual_adjusted';
      final serviceValue =
          '${meta['service_month'] ?? meta['target_year_month']}';
      final service = DateTime.tryParse(
        serviceValue.length == 7 ? '$serviceValue-01' : serviceValue,
      );
      final months = (num.tryParse('${meta['months_credited']}') ?? 1).toInt();
      if (accrual &&
          service != null &&
          months > 0 &&
          List.generate(
            months,
            (i) => DateTime(service.year, service.month - i),
          ).every(
            (m) => postedMonths.contains('${e.leaveType}|${_month(m)}'),
          )) {
        continue;
      }
      if (accrual && months > 1) {
        throw StateError(
          'Detailed monthly accrual history is unavailable for this employee. Historical balances cannot be verified.',
        );
      }
      final request = requestById[e.relatedLeaveRequestId];
      if (e.affectedBucket == 'used' && e.relatedLeaveRequestId != null) {
        usedRequestIds.add(e.relatedLeaveRequestId!);
      }
      final year = int.tryParse('${meta['year'] ?? meta['deduction_year']}');
      final isDtr = e.action.startsWith('attendance_deduction');
      final posted = e.createdAt.isUtc
          ? e.createdAt.add(const Duration(hours: 8))
          : e.createdAt;
      final effective = (accrual || isDtr) && service != null
          ? DateTime(service.year, service.month + 1, 0)
          : e.action == 'forced_leave_deduction' && year != null
          ? DateTime(year, 12, 31)
          : cutoff ??
                (request?.startDate) ??
                DateTime.tryParse('${meta['as_of_date']}') ??
                DateTime(posted.year, posted.month, posted.day);
      final label = accrual
          ? 'Monthly accrual'
          : isDtr
          ? 'DTR Late/Undertime Deduction'
          : e.action == 'opening_balance'
          ? 'Verified opening balance'
          : e.action == 'forced_leave_deduction'
          ? 'Year-end Mandatory Leave Deduction'
          : e.action.contains('revok')
          ? 'Leave approval revoked'
          : request?.leaveTypeLabel ??
                (e.action == 'leave_approved'
                    ? 'Approved leave'
                    : 'Credit adjustment');
      final group = (accrual || isDtr)
          ? '$label|${_month(effective)}'
          : '${e.relatedLeaveRequestId ?? e.id}|${e.action}';
      movements.add(
        _Movement(
          date: effective,
          group: group,
          label: label,
          type: e.leaveType,
          bucket: e.affectedBucket,
          days: e.daysChanged,
          unpaid: isDtr
              ? (num.tryParse('${meta['without_pay_days']}') ?? 0).toDouble()
              : e.action.contains('revok')
              ? 0
              : (request?.approvedDaysWithoutPay ?? 0),
          period: request?.startDate != null
              ? '${_date(request!.startDate!)} - ${_date(request.endDate ?? request.startDate!)}'
              : _month(effective),
          recorded: posted,
        ),
      );
    }
    for (final p in postings) {
      final date = DateTime(p.serviceMonth.year, p.serviceMonth.month + 1, 0);
      movements.add(
        _Movement(
          date: date,
          group: 'Monthly accrual|${_month(date)}',
          label: 'Monthly accrual',
          type: p.leaveType,
          bucket: 'earned',
          days: p.creditedDays,
          period: _month(date),
          recorded: date,
        ),
      );
    }
    // Legacy approved records may predate the ledger. Include each only once.
    for (final r in requests) {
      if (r.status != LeaveRequestStatus.approved ||
          usedRequestIds.contains(r.id)) {
        continue;
      }
      final name = r.effectiveLeaveTypeName;
      final type =
          balanceLedgerTypes[name] ??
          (r.leaveType == LeaveType.mandatoryForcedLeave
              ? 'vacationLeave'
              : name);
      final date = r.startDate ?? r.dateFiled;
      if (!_creditTypes.contains(type) || date == null) continue;
      final unpaid = r.approvedDaysWithoutPay ?? 0;
      final paid =
          r.approvedDaysWithPay ??
          ((r.workingDaysApplied ?? 0) - unpaid)
              .clamp(0, double.infinity)
              .toDouble();
      movements.add(
        _Movement(
          date: date,
          group: 'request|${r.id}',
          label: r.leaveTypeLabel,
          type: type,
          bucket: 'used',
          days: paid,
          unpaid: unpaid,
          period: '${_date(date)} - ${_date(r.endDate ?? date)}',
          recorded: r.reviewedAt ?? date,
        ),
      );
    }
    var vacation = vacationRemainingDays, sick = sickRemainingDays;
    for (final m in movements) {
      if (!m.date.isBefore(range.from)) {
        if (m.type == 'vacationLeave') {
          vacation -= m.delta;
        } else {
          sick -= m.delta;
        }
      }
    }
    final openingVacation = _rounded(vacation), openingSick = _rounded(sick);
    final selected =
        movements
            .where(
              (m) =>
                  !m.date.isBefore(range.from) &&
                  m.date.isBefore(range.endExclusive),
            )
            .toList()
          ..sort((a, b) {
            final d = a.date.compareTo(b.date);
            return d != 0
                ? d
                : a.group != b.group
                ? a.group.compareTo(b.group)
                : a.recorded.compareTo(b.recorded);
          });
    final groups = <String, List<_Movement>>{};
    for (final m in selected) {
      groups.putIfAbsent(m.group, () => []).add(m);
    }
    LeaveCardPeriodRow balanceRow(String label, DateTime date) =>
        LeaveCardPeriodRow(
          period: _date(date),
          particulars: label,
          vacBalance: leaveCardNumber(vacation),
          slBalance: leaveCardNumber(sick),
        );
    final rows = <LeaveCardPeriodRow>[
      balanceRow(
        'Balance brought forward',
        range.from.subtract(const Duration(days: 1)),
      ),
    ];
    for (final group in groups.values) {
      final first = group.first;
      double total(String type, String bucket) => group
          .where((m) => m.type == type && m.bucket == bucket)
          .fold(0.0, (s, m) => s + m.days);
      String amount(String type, String bucket) =>
          group.any((m) => m.type == type && m.bucket == bucket)
          ? bucket == 'earned'
                ? total(type, bucket).toStringAsFixed(3)
                : leaveCardNumber(total(type, bucket))
          : '';
      for (final m in group) {
        if (m.type == 'vacationLeave') {
          vacation += m.delta;
        } else {
          sick += m.delta;
        }
      }
      // Monthly corrections replace the without-pay snapshot, rather than adding it twice.
      final lastByType = <String, _Movement>{for (final m in group) m.type: m};
      final vUnpaid = lastByType['vacationLeave']?.unpaid ?? 0;
      final sUnpaid = lastByType['sickLeave']?.unpaid ?? 0;
      if (first.label.startsWith('DTR') &&
          total('vacationLeave', 'used').abs() < 0.0005 &&
          vUnpaid == 0) {
        continue;
      }
      rows.add(
        LeaveCardPeriodRow(
          period: first.period,
          particulars: first.label,
          vacEarned: amount('vacationLeave', 'earned'),
          vacWithPay: amount('vacationLeave', 'used'),
          vacBalance: leaveCardNumber(vacation),
          vacWithoutPay: vUnpaid == 0 ? '' : leaveCardNumber(vUnpaid),
          slEarned: amount('sickLeave', 'earned'),
          slWithPay: amount('sickLeave', 'used'),
          slBalance: leaveCardNumber(sick),
          slWithoutPay: sUnpaid == 0 ? '' : leaveCardNumber(sUnpaid),
          dateTakenOnApplication: _date(first.recorded),
        ),
      );
    }
    rows.add(
      balanceRow(
        'Closing balance',
        range.endExclusive.subtract(const Duration(days: 1)),
      ),
    );
    return LeaveCardPeriodReport._(
      range: range,
      rows: List.unmodifiable(rows),
      openingVacation: openingVacation,
      openingSick: openingSick,
      closingVacation: _rounded(vacation),
      closingSick: _rounded(sick),
      activityCount: rows.length - 2,
    );
  }
}

const _creditTypes = {'vacationLeave', 'sickLeave'};

class _Movement {
  _Movement({
    required this.date,
    required this.group,
    required this.label,
    required this.type,
    required this.bucket,
    required this.days,
    required this.period,
    required this.recorded,
    this.unpaid = 0,
  });
  final DateTime date, recorded;
  final String group, label, type, bucket, period;
  final double days, unpaid;
  double get delta => bucket == 'used' ? -days : days;
}
