import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance_ledger.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'leave_card_print_view.dart';

class EmployeeLeaveCardOption {
  const EmployeeLeaveCardOption({required this.userId, required this.name});

  final String userId;
  final String name;
}

class EmployeeLeaveCardViewScreen extends StatefulWidget {
  const EmployeeLeaveCardViewScreen({
    super.key,
    required this.userId,
    required this.employeeName,
    this.employeeOptions = const [],
  });

  final String userId;
  final String employeeName;
  final List<EmployeeLeaveCardOption> employeeOptions;

  @override
  State<EmployeeLeaveCardViewScreen> createState() =>
      _EmployeeLeaveCardViewScreenState();
}

class _EmployeeLeaveCardViewScreenState
    extends State<EmployeeLeaveCardViewScreen> {
  static const double _legalPaperAspectRatio = 8.5 / 14.0;
  static const int _rowsPerCardPage = 16;

  bool _loading = true;
  bool _printing = false;
  String? _error;
  List<LeaveRequest> _requests = const [];
  List<LeaveBalanceLedgerEntry> _forcedLeaveDeductions = const [];
  int _pageIndex = 0;

  /// Current VL / SL remaining totals from [leave_balances].
  double _vacationRemainingDays = 0;
  double _sickRemainingDays = 0;
  String? _officeDepartment;
  DateTime? _firstDayOfService;
  Map<String, String> _balanceLedgerTypes = const {};
  late String _selectedUserId;
  late String _selectedEmployeeName;
  late final List<EmployeeLeaveCardOption> _employeeOptions;

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.userId;
    _selectedEmployeeName = widget.employeeName;
    _employeeOptions = [...widget.employeeOptions];
    if (!_employeeOptions.any((option) => option.userId == _selectedUserId)) {
      _employeeOptions.add(
        EmployeeLeaveCardOption(
          userId: _selectedUserId,
          name: _selectedEmployeeName,
        ),
      );
    }
    _loadLeaveCardData();
  }

  Future<void> _loadLeaveCardData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = context.read<LeaveProvider>().repository;
      final definitions = await LeaveTypeDefinitionCache.instance.listAll(
        includeInactive: true,
      );
      final balanceLedgerTypes = {
        for (final item in definitions) item.name: item.balanceLedgerType,
      };
      final rows = await repository.listRequests(
        query: LeaveRequestQuery(
          userId: _selectedUserId,
          status: LeaveRequestStatus.approved,
          limit: 500,
        ),
      );
      final cardRows =
          rows
              .where(
                (request) => _isLeaveCardRequest(request, balanceLedgerTypes),
              )
              .toList()
            ..sort((a, b) {
              final aDate = a.startDate ?? a.dateFiled ?? DateTime(1900);
              final bDate = b.startDate ?? b.dateFiled ?? DateTime(1900);
              return aDate.compareTo(bDate);
            });
      final balances = await repository.getBalancesForUser(_selectedUserId);
      final ledger = await repository.getLeaveLedger(
        LeaveLedgerQuery(
          userId: _selectedUserId,
          leaveType: LeaveType.vacationLeave.value,
          limit: 500,
        ),
      );
      final totals = _vlSlTotalsFromBalances(balances);
      final profile = await _loadEmployeeProfile();
      setState(() {
        _requests = cardRows;
        _forcedLeaveDeductions = ledger.rows;
        _vacationRemainingDays = totals.vacationRemaining;
        _sickRemainingDays = totals.sickRemaining;
        _officeDepartment = profile.officeDepartment;
        _firstDayOfService = profile.firstDayOfService;
        _balanceLedgerTypes = balanceLedgerTypes;
        _pageIndex = 0;
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
    final office = _officeDepartment?.trim().isNotEmpty == true
        ? _officeDepartment!.trim()
        : _requests
              .map((e) => (e.officeDepartment ?? '').trim())
              .firstWhere((e) => e.isNotEmpty, orElse: () => 'N/A');
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: Row(
          children: [
            const Text("Employee's Leave Card"),
            if (_employeeOptions.length > 1) ...[
              const SizedBox(width: 24),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: DropdownMenu<String>(
                      key: ValueKey(_selectedUserId),
                      initialSelection: _selectedUserId,
                      width: 320,
                      menuHeight: 420,
                      enabled: !_loading,
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      leadingIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Search employee',
                      textStyle: AppTheme.dashFieldTextStyle(context),
                      inputDecorationTheme: InputDecorationTheme(
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.dashMutedSurfaceOf(context),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.dashHairlineOf(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.dashHairlineOf(context),
                          ),
                        ),
                      ),
                      menuStyle: MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(
                          AppTheme.dashPanelOf(context),
                        ),
                      ),
                      dropdownMenuEntries: _employeeOptions
                          .map(
                            (option) => DropdownMenuEntry<String>(
                              value: option.userId,
                              label: option.name,
                            ),
                          )
                          .toList(),
                      onSelected: _selectEmployee,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        surfaceTintColor: Colors.transparent,
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

  void _selectEmployee(String? userId) {
    if (userId == null || userId == _selectedUserId) return;
    final selected = _employeeOptions.firstWhere(
      (option) => option.userId == userId,
    );
    setState(() {
      _selectedUserId = selected.userId;
      _selectedEmployeeName = selected.name;
    });
    _loadLeaveCardData();
  }

  Future<void> _printLeaveCard(String office) async {
    if (_printing) return;

    setState(() => _printing = true);
    try {
      await LeaveCardPrintView.print(
        employeeName: _selectedEmployeeName,
        officeDepartment: office,
        firstDayOfService: _firstDayOfService,
        requests: _requests,
        vacationRemainingDays: _vacationRemainingDays,
        sickRemainingDays: _sickRemainingDays,
        balanceLedgerTypes: _balanceLedgerTypes,
        forcedLeaveDeductions: _forcedLeaveDeductions,
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

  Future<_LeaveCardEmployeeProfile> _loadEmployeeProfile() async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/employees/$_selectedUserId',
    );
    return _LeaveCardEmployeeProfile.fromJson(
      res.data ?? const <String, dynamic>{},
    );
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
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
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
    final entries = _buildLeaveCardEntries(
      _requests,
      vacationRemainingDays: _vacationRemainingDays,
      sickRemainingDays: _sickRemainingDays,
      balanceLedgerTypes: _balanceLedgerTypes,
      forcedLeaveDeductions: _forcedLeaveDeductions,
    );
    final pages = _chunkEntries(entries, _rowsPerCardPage);
    final pageCount = pages.length;
    final pageIndex = _pageIndex >= pageCount ? pageCount - 1 : _pageIndex;
    final pageEntries = pages[pageIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LeaveCardPageControls(
                pageIndex: pageIndex,
                pageCount: pageCount,
                onPrevious: pageIndex > 0
                    ? () => setState(() => _pageIndex = pageIndex - 1)
                    : null,
                onNext: pageIndex < pageCount - 1
                    ? () => setState(() => _pageIndex = pageIndex + 1)
                    : null,
              ),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: _legalPaperAspectRatio,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EEB8),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.35),
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
                            child: _LabeledLineField(
                              label: 'NAME',
                              value: _selectedEmployeeName,
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
                          Expanded(
                            flex: 3,
                            child: _LabeledLineField(
                              label: 'FIRST DAY OF SERVICE',
                              value: _firstDayOfService != null
                                  ? _fmtDate(_firstDayOfService!)
                                  : '',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _LeaveCardGrid(
                          entries: pageEntries,
                          rowsPerPage: _rowsPerCardPage,
                        ),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }

  List<List<_LeaveCardEntry>> _chunkEntries(
    List<_LeaveCardEntry> entries,
    int pageSize,
  ) {
    if (entries.isEmpty) return [const <_LeaveCardEntry>[]];
    final pages = <List<_LeaveCardEntry>>[];
    for (var i = 0; i < entries.length; i += pageSize) {
      final end = (i + pageSize) > entries.length
          ? entries.length
          : i + pageSize;
      pages.add(entries.sublist(i, end));
    }
    return pages;
  }
}

class _LeaveCardPageControls extends StatelessWidget {
  const _LeaveCardPageControls({
    required this.pageIndex,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.dashTextPrimaryOf(context);
    final mutedColor = AppTheme.dashTextSecondaryOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Page ${pageIndex + 1} of $pageCount',
          style: TextStyle(
            color: mutedColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: onPrevious,
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: onPrevious == null ? mutedColor : textColor,
                ),
              ),
              SizedBox(
                height: 28,
                child: VerticalDivider(
                  width: 1,
                  color: AppTheme.dashHairlineOf(context),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: onNext,
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: onNext == null ? mutedColor : textColor,
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _LeaveCardGrid({required this.entries, required this.rowsPerPage});

  final List<_LeaveCardEntry> entries;
  final int rowsPerPage;
  static const double _groupHeaderHeight = 30;
  static const double _detailHeaderHeight = 56;
  static const int _periodFlex = 15;
  static const int _particularsFlex = 21;
  static const int _vacationGroupFlex = 44;
  static const int _sickGroupFlex = 44;
  static const int _dateTakenFlex = 16;

  @override
  Widget build(BuildContext context) {
    final targetRows = entries.length > rowsPerPage
        ? entries.length
        : rowsPerPage;
    final filledEntries = [
      ...entries,
      ...List.generate(
        entries.length < targetRows ? targetRows - entries.length : 0,
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
                            _GridCellSpec('EARNED', flex: 9),
                            _GridCellSpec(
                              'ABSENCE UNDER TIME WITH PAY',
                              flex: 12,
                            ),
                            _GridCellSpec('BALANCE', flex: 9),
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
                            _GridCellSpec('EARNED', flex: 9),
                            _GridCellSpec(
                              'ABSENCE UNDER TIME WITH PAY',
                              flex: 12,
                            ),
                            _GridCellSpec('BALANCE', flex: 9),
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
            (entry) => Expanded(
              child: _gridRow(
                cells: [
                  _GridCellSpec(entry.period, flex: _periodFlex),
                  _GridCellSpec(
                    entry.particulars,
                    flex: _particularsFlex,
                    align: TextAlign.left,
                  ),
                  _GridCellSpec(entry.vacEarned, flex: 9),
                  _GridCellSpec(entry.vacAbsWithPay, flex: 12),
                  _GridCellSpec(entry.vacBalance, flex: 9),
                  _GridCellSpec(entry.vacAbsWithoutPay, flex: 14),
                  _GridCellSpec(entry.slEarned, flex: 9),
                  _GridCellSpec(entry.slAbsWithPay, flex: 12),
                  _GridCellSpec(entry.slBalance, flex: 9),
                  _GridCellSpec(entry.slAbsWithoutPay, flex: 14),
                  _GridCellSpec(
                    entry.dateTakenOnApplication,
                    flex: _dateTakenFlex,
                  ),
                ],
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridRow({
    required List<_GridCellSpec> cells,
    double? height,
    double fontSize = 11,
    bool bold = false,
  }) {
    final row = Row(
      children: cells
          .map(
            (cell) => Expanded(
              flex: cell.flex,
              child: Container(
                height: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    );
    return height == null
        ? SizedBox.expand(child: row)
        : SizedBox(height: height, child: row);
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

const double _leaveCardMonthlyEarnedDays = 1.25;

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
    required this.vacBalance,
    required this.vacAbsWithoutPay,
    required this.slEarned,
    required this.slAbsWithPay,
    required this.slBalance,
    required this.slAbsWithoutPay,
    required this.dateTakenOnApplication,
  });

  const _LeaveCardEntry.empty()
    : period = '',
      particulars = '',
      vacEarned = '',
      vacAbsWithPay = '',
      vacBalance = '',
      vacAbsWithoutPay = '',
      slEarned = '',
      slAbsWithPay = '',
      slBalance = '',
      slAbsWithoutPay = '',
      dateTakenOnApplication = '';

  final String period;
  final String particulars;
  final String vacEarned;
  final String vacAbsWithPay;
  final String vacBalance;
  final String vacAbsWithoutPay;
  final String slEarned;
  final String slAbsWithPay;
  final String slBalance;
  final String slAbsWithoutPay;
  final String dateTakenOnApplication;

  factory _LeaveCardEntry.fromRequest(
    LeaveRequest request, {
    required double vacationBalanceDays,
    required double sickBalanceDays,
    required double withPayDays,
    required double withoutPayDays,
    required Map<String, String> balanceLedgerTypes,
  }) {
    final start = request.startDate;
    final end = request.endDate;
    final period = (start != null && end != null)
        ? '${_fmtDate(start)} - ${_fmtDate(end)}'
        : (start != null ? _fmtDate(start) : '—');
    final isSick = _isSickLedgerRequest(request, balanceLedgerTypes);
    final isVacation = _isVacationLedgerRequest(request, balanceLedgerTypes);
    final actionDate = request.reviewedAt ?? request.dateFiled;
    final earnedDays = _fmtEarned(_leaveCardMonthlyEarnedDays);

    return _LeaveCardEntry(
      period: period,
      particulars: request.leaveTypeLabel,
      vacEarned: isVacation ? earnedDays : '',
      vacAbsWithPay: isVacation ? _fmtNum(withPayDays) : '',
      vacBalance: isVacation ? _fmtNum(vacationBalanceDays) : '',
      vacAbsWithoutPay: isVacation ? _fmtNum(withoutPayDays) : '',
      slEarned: isSick ? earnedDays : '',
      slAbsWithPay: isSick ? _fmtNum(withPayDays) : '',
      slBalance: isSick ? _fmtNum(sickBalanceDays) : '',
      slAbsWithoutPay: isSick ? _fmtNum(withoutPayDays) : '',
      dateTakenOnApplication: actionDate != null ? _fmtDate(actionDate) : '',
    );
  }

  factory _LeaveCardEntry.fromForcedDeduction(
    LeaveBalanceLedgerEntry entry, {
    required double vacationBalanceDays,
    required double deductedDays,
    required double earnedDays,
  }) {
    final period = _deductionPeriod(entry);
    final particulars = _forcedDeductionParticulars(entry);
    final withoutPayDays = _attendanceWithoutPayDays(entry);

    return _LeaveCardEntry(
      period: period,
      particulars: particulars,
      vacEarned: _fmtEarned(earnedDays),
      vacAbsWithPay: _fmtNum(deductedDays),
      vacBalance: _fmtNum(vacationBalanceDays),
      vacAbsWithoutPay: withoutPayDays > 0 ? _fmtNum(withoutPayDays) : '',
      slEarned: '',
      slAbsWithPay: '',
      slBalance: '',
      slAbsWithoutPay: '',
      dateTakenOnApplication: _fmtDate(entry.createdAt),
    );
  }
}

List<_LeaveCardEntry> _buildLeaveCardEntries(
  List<LeaveRequest> requests, {
  required double vacationRemainingDays,
  required double sickRemainingDays,
  required Map<String, String> balanceLedgerTypes,
  List<LeaveBalanceLedgerEntry> forcedLeaveDeductions = const [],
}) {
  final cardRequests = requests
      .where((request) => _isLeaveCardRequest(request, balanceLedgerTypes))
      .toList();
  final deductions = forcedLeaveDeductions
      .where(
        (entry) =>
            _isLeaveCardDeduction(entry) &&
            entry.leaveType == LeaveType.vacationLeave.value,
      )
      .toList();
  final monthlyVacationEarned = _monthlyVacationEarnedByPeriod(
    forcedLeaveDeductions,
  );
  if (cardRequests.isEmpty && deductions.isEmpty) {
    return const [];
  }

  final deductionDaysTotal = deductions.fold<double>(
    0,
    (sum, entry) => sum + _forcedDeductionDays(entry),
  );
  final vacationUsedInRows =
      cardRequests
          .where(
            (request) => _isVacationLedgerRequest(request, balanceLedgerTypes),
          )
          .fold<double>(0, (sum, request) => sum + _withPayDays(request)) +
      deductionDaysTotal;
  final sickUsedInRows = cardRequests
      .where((request) => _isSickLedgerRequest(request, balanceLedgerTypes))
      .fold<double>(0, (sum, request) => sum + _withPayDays(request));
  var vacationBalance = vacationRemainingDays + vacationUsedInRows;
  var sickBalance = sickRemainingDays + sickUsedInRows;

  final timeline = <_LeaveCardTimelineItem>[
    for (final request in cardRequests)
      _LeaveCardTimelineItem.request(
        request,
        request.startDate ?? request.dateFiled ?? DateTime(1900),
      ),
    for (final entry in deductions)
      _LeaveCardTimelineItem.deduction(entry, entry.createdAt),
  ]..sort((a, b) => a.sortDate.compareTo(b.sortDate));

  return timeline.map((item) {
    return item.when(
      request: (request) {
        final withPayDays = _withPayDays(request);
        final withoutPayDays = _withoutPayDays(request);
        if (_isVacationLedgerRequest(request, balanceLedgerTypes)) {
          vacationBalance -= withPayDays;
        }
        if (_isSickLedgerRequest(request, balanceLedgerTypes)) {
          sickBalance -= withPayDays;
        }
        return _LeaveCardEntry.fromRequest(
          request,
          vacationBalanceDays: vacationBalance,
          sickBalanceDays: sickBalance,
          withPayDays: withPayDays,
          withoutPayDays: withoutPayDays,
          balanceLedgerTypes: balanceLedgerTypes,
        );
      },
      deduction: (entry) {
        final deductedDays = _forcedDeductionDays(entry);
        vacationBalance -= deductedDays;
        return _LeaveCardEntry.fromForcedDeduction(
          entry,
          vacationBalanceDays: vacationBalance,
          deductedDays: deductedDays,
          earnedDays: _earnedDaysForDeduction(entry, monthlyVacationEarned),
        );
      },
    );
  }).toList();
}

class _LeaveCardTimelineItem {
  const _LeaveCardTimelineItem._({
    required this.sortDate,
    this.request,
    this.deduction,
  });

  factory _LeaveCardTimelineItem.request(
    LeaveRequest request,
    DateTime sortDate,
  ) {
    return _LeaveCardTimelineItem._(sortDate: sortDate, request: request);
  }

  factory _LeaveCardTimelineItem.deduction(
    LeaveBalanceLedgerEntry entry,
    DateTime sortDate,
  ) {
    return _LeaveCardTimelineItem._(sortDate: sortDate, deduction: entry);
  }

  final DateTime sortDate;
  final LeaveRequest? request;
  final LeaveBalanceLedgerEntry? deduction;

  T when<T>({
    required T Function(LeaveRequest request) request,
    required T Function(LeaveBalanceLedgerEntry entry) deduction,
  }) {
    final r = this.request;
    if (r != null) return request(r);
    final d = this.deduction;
    if (d != null) return deduction(d);
    throw StateError('Invalid leave card timeline item');
  }
}

double _forcedDeductionDays(LeaveBalanceLedgerEntry entry) {
  if (_isAttendanceDeduction(entry)) {
    return entry.daysChanged;
  }
  final meta = entry.metadataJson?['deducted_days'];
  if (meta is num && meta > 0) return meta.toDouble();
  if (entry.affectedBucket.toLowerCase() == 'used' && entry.daysChanged > 0) {
    return entry.daysChanged;
  }
  return entry.daysChanged.abs();
}

String _forcedDeductionParticulars(LeaveBalanceLedgerEntry entry) {
  if (_isAttendanceDeduction(entry)) {
    final serviceMonth = entry.metadataJson?['service_month']?.toString();
    final label = entry.action == 'attendance_deduction_adjusted'
        ? 'DTR Deduction Correction'
        : 'DTR Late/Undertime Deduction';
    return serviceMonth == null || serviceMonth.isEmpty
        ? label
        : '$label ($serviceMonth)';
  }
  final year =
      entry.metadataJson?['year'] ?? entry.metadataJson?['deduction_year'];
  if (year != null) {
    return 'Year-end Mandatory Leave Deduction ($year)';
  }
  final remarks = entry.remarks?.trim();
  if (remarks != null && remarks.isNotEmpty) return remarks;
  return 'Year-end Mandatory Leave Deduction';
}

bool _isLeaveCardDeduction(LeaveBalanceLedgerEntry entry) {
  return entry.action == 'forced_leave_deduction' ||
      _isAttendanceDeduction(entry);
}

bool _isAttendanceDeduction(LeaveBalanceLedgerEntry entry) {
  return entry.action == 'attendance_deduction' ||
      entry.action == 'attendance_deduction_adjusted';
}

Map<String, double> _monthlyVacationEarnedByPeriod(
  List<LeaveBalanceLedgerEntry> entries,
) {
  final earnedByPeriod = <String, double>{};
  for (final entry in entries) {
    final isAccrual =
        entry.action == 'monthly_accrual' ||
        entry.action == 'monthly_accrual_adjusted';
    if (!isAccrual ||
        entry.leaveType != LeaveType.vacationLeave.value ||
        entry.affectedBucket.toLowerCase() != 'earned') {
      continue;
    }
    final period =
        entry.metadataJson?['target_year_month']?.toString() ??
        entry.metadataJson?['service_month']?.toString();
    if (period == null || period.isEmpty) continue;
    earnedByPeriod.update(
      period,
      (value) => value + entry.daysChanged,
      ifAbsent: () => entry.daysChanged,
    );
  }
  return earnedByPeriod;
}

double _earnedDaysForDeduction(
  LeaveBalanceLedgerEntry entry,
  Map<String, double> monthlyVacationEarned,
) {
  if (!_isAttendanceDeduction(entry)) return _leaveCardMonthlyEarnedDays;
  final period = entry.metadataJson?['service_month']?.toString();
  final earned = period == null ? null : monthlyVacationEarned[period];
  return earned == null
      ? _leaveCardMonthlyEarnedDays
      : earned.clamp(0, double.infinity).toDouble();
}

double _attendanceWithoutPayDays(LeaveBalanceLedgerEntry entry) {
  if (entry.action != 'attendance_deduction') return 0;
  final value = entry.metadataJson?['without_pay_days'];
  if (value is num && value > 0) return value.toDouble();
  return 0;
}

String _deductionPeriod(LeaveBalanceLedgerEntry entry) {
  final serviceMonth = entry.metadataJson?['service_month']?.toString();
  if (serviceMonth != null && serviceMonth.isNotEmpty) return serviceMonth;
  final year =
      entry.metadataJson?['year'] ?? entry.metadataJson?['deduction_year'];
  return year != null ? 'CY $year' : _fmtDate(entry.createdAt);
}

bool _isLeaveCardRequest(
  LeaveRequest request,
  Map<String, String> balanceLedgerTypes,
) {
  return request.status == LeaveRequestStatus.approved &&
      (_isVacationLedgerRequest(request, balanceLedgerTypes) ||
          _isSickLedgerRequest(request, balanceLedgerTypes));
}

bool _isVacationLedgerRequest(
  LeaveRequest request,
  Map<String, String> balanceLedgerTypes,
) {
  return _leaveCardLedgerType(request, balanceLedgerTypes) ==
      LeaveType.vacationLeave.value;
}

bool _isSickLedgerRequest(
  LeaveRequest request,
  Map<String, String> balanceLedgerTypes,
) {
  return _leaveCardLedgerType(request, balanceLedgerTypes) ==
      LeaveType.sickLeave.value;
}

String _leaveCardLedgerType(
  LeaveRequest request,
  Map<String, String> balanceLedgerTypes,
) {
  final name = request.effectiveLeaveTypeName;
  final configured = balanceLedgerTypes[name]?.trim();
  final policy = configured == null || configured.isEmpty
      ? switch (request.leaveType) {
          LeaveType.vacationLeave => LeaveType.vacationLeave.value,
          LeaveType.sickLeave => LeaveType.sickLeave.value,
          LeaveType.mandatoryForcedLeave => LeaveType.vacationLeave.value,
          _ => 'none',
        }
      : configured;
  return policy == 'ownBalance' ? name : policy;
}

double _withPayDays(LeaveRequest request) {
  final approvedWithPay = request.approvedDaysWithPay;
  if (approvedWithPay != null) {
    return approvedWithPay.isFinite && approvedWithPay > 0
        ? approvedWithPay
        : 0;
  }
  final applied = request.workingDaysApplied ?? 0;
  final withoutPay = request.approvedDaysWithoutPay;
  if (withoutPay != null && withoutPay > 0) {
    final paid = applied - withoutPay;
    return paid.isFinite && paid > 0 ? paid : 0;
  }
  final value = applied;
  return value.isFinite && value > 0 ? value : 0;
}

double _withoutPayDays(LeaveRequest request) {
  final value = request.approvedDaysWithoutPay ?? 0;
  return value.isFinite && value > 0 ? value : 0;
}

_LeaveCardTotals _vlSlTotalsFromBalances(List<LeaveBalance> balances) {
  var vacationRemaining = 0.0;
  var sickRemaining = 0.0;
  for (final b in balances) {
    if (b.effectiveLeaveTypeName == LeaveType.vacationLeave.value) {
      vacationRemaining = b.remainingDays;
    }
    if (b.effectiveLeaveTypeName == LeaveType.sickLeave.value) {
      sickRemaining = b.remainingDays;
    }
  }
  return _LeaveCardTotals(
    vacationRemaining: vacationRemaining,
    sickRemaining: sickRemaining,
  );
}

class _LeaveCardTotals {
  const _LeaveCardTotals({
    required this.vacationRemaining,
    required this.sickRemaining,
  });

  final double vacationRemaining;
  final double sickRemaining;
}

class _LeaveCardEmployeeProfile {
  const _LeaveCardEmployeeProfile({
    this.officeDepartment,
    this.firstDayOfService,
  });

  final String? officeDepartment;
  final DateTime? firstDayOfService;

  factory _LeaveCardEmployeeProfile.fromJson(Map<String, dynamic> json) {
    return _LeaveCardEmployeeProfile(
      officeDepartment: _cleanProfileText(json['current_department_name']),
      firstDayOfService: _parseProfileDate(json['date_hired']),
    );
  }
}

String? _cleanProfileText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _parseProfileDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _fmtNum(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _fmtEarned(double value) => value.toStringAsFixed(3);

String _fmtDate(DateTime value) {
  final mm = value.month.toString().padLeft(2, '0');
  final dd = value.day.toString().padLeft(2, '0');
  return '$mm/$dd/${value.year}';
}
