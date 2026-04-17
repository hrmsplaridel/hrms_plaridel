import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../leave_provider.dart';
import '../leave_repository.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'leave_card_print_view.dart';

class EmployeeLeaveCardViewScreen extends StatefulWidget {
  const EmployeeLeaveCardViewScreen({
    super.key,
    required this.userId,
    required this.employeeName,
  });

  final String userId;
  final String employeeName;

  @override
  State<EmployeeLeaveCardViewScreen> createState() =>
      _EmployeeLeaveCardViewScreenState();
}

class _EmployeeLeaveCardViewScreenState
    extends State<EmployeeLeaveCardViewScreen> {
  static const double _legalPaperAspectRatio = 8.5 / 14.0;

  bool _loading = true;
  bool _printing = false;
  String? _error;
  List<LeaveRequest> _requests = const [];

  /// Current VL / SL earned totals from [leave_balances] (same on each ledger row).
  double _vacationEarnedDays = 0;
  double _sickEarnedDays = 0;

  @override
  void initState() {
    super.initState();
    _loadLeaveCardData();
  }

  Future<void> _loadLeaveCardData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = context.read<LeaveProvider>().repository;
      final rows = await repository.listRequests(
        query: LeaveRequestQuery(userId: widget.userId, limit: 1000),
      );
      rows.sort((a, b) {
        final aDate = a.startDate ?? a.dateFiled ?? DateTime(1900);
        final bDate = b.startDate ?? b.dateFiled ?? DateTime(1900);
        return aDate.compareTo(bDate);
      });
      final balances = await repository.getBalancesForUser(widget.userId);
      final earned = _vlSlEarnedFromBalances(balances);
      setState(() {
        _requests = rows;
        _vacationEarnedDays = earned.$1;
        _sickEarnedDays = earned.$2;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final office = _requests
        .map((e) => (e.officeDepartment ?? '').trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => 'N/A');
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text("Employee's Leave Card"),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Print Leave Card',
            onPressed: _loading || _printing
                ? null
                : () => _printLeaveCard(office),
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : _buildCardLayout(office),
    );
  }

  Future<void> _printLeaveCard(String office) async {
    if (_printing) return;
    final firstDayOfService = _requests
        .map((e) => e.createdAt ?? e.dateFiled)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (prev, next) {
          if (prev == null) return next;
          return next.isBefore(prev) ? next : prev;
        });

    setState(() => _printing = true);
    try {
      await LeaveCardPrintView.print(
        employeeName: widget.employeeName,
        officeDepartment: office,
        firstDayOfService: firstDayOfService,
        requests: _requests,
        vacationEarnedDays: _vacationEarnedDays,
        sickEarnedDays: _sickEarnedDays,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load leave card data.',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadLeaveCardData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardLayout(String office) {
    final entries = _requests
        .map(
          (r) => _LeaveCardEntry.fromRequest(
            r,
            vacationEarnedDays: _vacationEarnedDays,
            sickEarnedDays: _sickEarnedDays,
          ),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: AspectRatio(
            aspectRatio: _legalPaperAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE9EEB8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.black.withOpacity(0.35),
                  width: 1.1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Text(
                      'MUNICIPAL GOVERNMENT OF PLARIDEL',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Center(
                    child: Text(
                      "EMPLOYEE'S LEAVE CARD",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _LabeledLineField(
                              label: 'NAME',
                              value: widget.employeeName,
                            ),
                            const SizedBox(height: 2),
                            const _LabeledLineField(
                              label: 'SERVICE',
                              value: '',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: _LabeledLineField(
                          label: 'DIVISION / OFFICE',
                          value: office,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        flex: 2,
                        child: _LabeledLineField(
                          label: 'FIRST DAY OF',
                          value: '',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _LeaveCardGrid(entries: entries)),
                  const SizedBox(height: 26),
                  Row(
                    children: const [
                      Spacer(),
                      SizedBox(
                        width: 300,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Prepared by:',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 34),
                            Divider(height: 1, color: Colors.black87),
                            SizedBox(height: 6),
                            Text(
                              '(In-Charge)',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledLineField extends StatelessWidget {
  const _LabeledLineField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(bottom: 1),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.black87, width: 0.8),
              ),
            ),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaveCardGrid extends StatelessWidget {
  const _LeaveCardGrid({required this.entries});

  final List<_LeaveCardEntry> entries;
  static const double _groupHeaderHeight = 30;
  static const double _detailHeaderHeight = 56;
  static const double _rowHeight = 34;
  static const int _periodFlex = 17;
  static const int _particularsFlex = 22;
  static const int _vacationGroupFlex = 36;
  static const int _sickGroupFlex = 36;
  static const int _dateTakenFlex = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final overflowSafetyPx = (2.0 / dpr).clamp(0.5, 2.0);
        final availableHeight = constraints.maxHeight;
        final headerHeight = _groupHeaderHeight + _detailHeaderHeight;
        final bodyHeight = (availableHeight - headerHeight - overflowSafetyPx)
            .clamp(0.0, double.infinity);
        final bodyRows = bodyHeight > 0 ? (bodyHeight / _rowHeight).ceil() : 0;
        final minimumRows = 16;
        final targetRows = [
          entries.length,
          minimumRows,
          bodyRows,
        ].reduce((a, b) => a > b ? a : b);
        final dynamicRowHeight = (bodyHeight > 0 && targetRows > 0)
            ? (bodyHeight / targetRows).clamp(0.0, _rowHeight)
            : _rowHeight;
        final filledEntries = [
          ...entries,
          ...List.generate(
            (entries.length < targetRows) ? targetRows - entries.length : 0,
            (_) => const _LeaveCardEntry.empty(),
          ),
        ];

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black87, width: 1),
          ),
          child: Column(
            children: [
              SizedBox(
                height: _groupHeaderHeight + _detailHeaderHeight,
                child: Row(
                  children: [
                    Expanded(
                      flex: _periodFlex,
                      child: _mergedHeaderCell(
                        text: 'PERIOD',
                        showRightBorder: true,
                      ),
                    ),
                    Expanded(
                      flex: _particularsFlex,
                      child: _mergedHeaderCell(
                        text: 'PARTICULARS',
                        showRightBorder: true,
                      ),
                    ),
                    Expanded(
                      flex: _vacationGroupFlex,
                      child: Column(
                        children: [
                          _headerGroupTitleCell(
                            text: 'VACATION LEAVE',
                            height: _groupHeaderHeight,
                          ),
                          Expanded(
                            child: _gridRow(
                              cells: const [
                                _GridCellSpec('EARNED', flex: 10),
                                _GridCellSpec(
                                  'ABSENCE UNDER TIME WITH PAY',
                                  flex: 12,
                                ),
                                _GridCellSpec(
                                  'ABSENCE UNDER TIME WITHOUT PAY',
                                  flex: 14,
                                ),
                              ],
                              height: _detailHeaderHeight,
                              fontSize: 9,
                              bold: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: _sickGroupFlex,
                      child: Column(
                        children: [
                          _headerGroupTitleCell(
                            text: 'SICK LEAVE',
                            height: _groupHeaderHeight,
                          ),
                          Expanded(
                            child: _gridRow(
                              cells: const [
                                _GridCellSpec('EARNED', flex: 10),
                                _GridCellSpec(
                                  'ABSENCE UNDER TIME WITH PAY',
                                  flex: 12,
                                ),
                                _GridCellSpec(
                                  'ABSENCE UNDER TIME WITHOUT PAY',
                                  flex: 14,
                                ),
                              ],
                              height: _detailHeaderHeight,
                              fontSize: 9,
                              bold: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: _dateTakenFlex,
                      child: _mergedHeaderCell(
                        text: 'DATE TAKEN ON\nAPPLICATION',
                        showRightBorder: false,
                        showLeftBorder: true,
                      ),
                    ),
                  ],
                ),
              ),
              ...filledEntries.map(
                (entry) => _gridRow(
                  cells: [
                    _GridCellSpec(entry.period, flex: 17),
                    _GridCellSpec(
                      entry.particulars,
                      flex: 22,
                      align: TextAlign.left,
                    ),
                    _GridCellSpec(entry.vacEarned, flex: 10),
                    _GridCellSpec(entry.vacAbsWithPay, flex: 12),
                    _GridCellSpec(entry.vacAbsWithoutPay, flex: 14),
                    _GridCellSpec(entry.slEarned, flex: 10),
                    _GridCellSpec(entry.slAbsWithPay, flex: 12),
                    _GridCellSpec(entry.slAbsWithoutPay, flex: 14),
                    _GridCellSpec(entry.dateTakenOnApplication, flex: 16),
                  ],
                  height: dynamicRowHeight,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gridRow({
    required List<_GridCellSpec> cells,
    required double height,
    double fontSize = 11,
    bool bold = false,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        children: cells
            .map(
              (cell) => Expanded(
                flex: cell.flex,
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.black87, width: 0.8),
                      top: BorderSide(color: Colors.black87, width: 0.8),
                    ),
                  ),
                  child: Text(
                    cell.text,
                    textAlign: cell.align,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.1,
                      color: Colors.black87,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _mergedHeaderCell({
    required String text,
    required bool showRightBorder,
    bool showLeftBorder = false,
  }) {
    return Container(
      height: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          left: showLeftBorder
              ? const BorderSide(color: Colors.black87, width: 0.8)
              : BorderSide.none,
          right: showRightBorder
              ? const BorderSide(color: Colors.black87, width: 0.8)
              : BorderSide.none,
          top: const BorderSide(color: Colors.black87, width: 0.8),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.1,
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _headerGroupTitleCell({required String text, required double height}) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.black87, width: 0.8),
          top: BorderSide(color: Colors.black87, width: 0.8),
          bottom: BorderSide(color: Colors.black87, width: 0.8),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.1,
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GridCellSpec {
  const _GridCellSpec(
    this.text, {
    required this.flex,
    this.align = TextAlign.center,
  });

  final String text;
  final int flex;
  final TextAlign align;
}

class _LeaveCardEntry {
  const _LeaveCardEntry({
    required this.period,
    required this.particulars,
    required this.vacEarned,
    required this.vacAbsWithPay,
    required this.vacAbsWithoutPay,
    required this.slEarned,
    required this.slAbsWithPay,
    required this.slAbsWithoutPay,
    required this.dateTakenOnApplication,
  });

  const _LeaveCardEntry.empty()
    : period = '',
      particulars = '',
      vacEarned = '',
      vacAbsWithPay = '',
      vacAbsWithoutPay = '',
      slEarned = '',
      slAbsWithPay = '',
      slAbsWithoutPay = '',
      dateTakenOnApplication = '';

  final String period;
  final String particulars;
  final String vacEarned;
  final String vacAbsWithPay;
  final String vacAbsWithoutPay;
  final String slEarned;
  final String slAbsWithPay;
  final String slAbsWithoutPay;
  final String dateTakenOnApplication;

  factory _LeaveCardEntry.fromRequest(
    LeaveRequest request, {
    required double vacationEarnedDays,
    required double sickEarnedDays,
  }) {
    final start = request.startDate;
    final end = request.endDate;
    final period = (start != null && end != null)
        ? '${_fmtDate(start)} - ${_fmtDate(end)}'
        : (start != null ? _fmtDate(start) : '—');
    final withPay =
        request.approvedDaysWithPay ?? request.workingDaysApplied ?? 0;
    final withoutPay = request.approvedDaysWithoutPay ?? 0;
    final isSick = request.leaveType == LeaveType.sickLeave;
    final isVacation =
        request.leaveType == LeaveType.vacationLeave ||
        request.leaveType == LeaveType.mandatoryForcedLeave;

    return _LeaveCardEntry(
      period: period,
      particulars: request.leaveType.displayName,
      vacEarned: _fmtNum(vacationEarnedDays),
      vacAbsWithPay: isVacation ? _fmtNum(withPay) : '',
      vacAbsWithoutPay: isVacation ? _fmtNum(withoutPay) : '',
      slEarned: _fmtNum(sickEarnedDays),
      slAbsWithPay: isSick ? _fmtNum(withPay) : '',
      slAbsWithoutPay: isSick ? _fmtNum(withoutPay) : '',
      dateTakenOnApplication: request.dateFiled != null
          ? _fmtDate(request.dateFiled!)
          : '',
    );
  }
}

/// Vacation / sick earned days from API balances (`leave_balances.earned_days`).
(double, double) _vlSlEarnedFromBalances(List<LeaveBalance> balances) {
  var vl = 0.0;
  var sl = 0.0;
  for (final b in balances) {
    if (b.leaveType == LeaveType.vacationLeave) vl = b.earnedDays;
    if (b.leaveType == LeaveType.sickLeave) sl = b.earnedDays;
  }
  return (vl, sl);
}

String _fmtNum(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _fmtDate(DateTime value) {
  final mm = value.month.toString().padLeft(2, '0');
  final dd = value.day.toString().padLeft(2, '0');
  return '$mm/$dd/${value.year}';
}
