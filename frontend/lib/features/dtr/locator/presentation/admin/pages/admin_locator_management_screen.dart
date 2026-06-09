import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/locator_type_management_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

typedef _LocatorHistoryStep = ({
  String title,
  String? actor,
  DateTime? date,
  String? remarks,
  bool completed,
});

enum _LocatorAdminQueue {
  all('All'),
  pendingDeptHead('Pending Dept Head'),
  pendingHrAdmin('Pending HR Admin'),
  approved('Approved'),
  rejected('Rejected'),
  cancelled('Cancelled');

  const _LocatorAdminQueue(this.label);
  final String label;
}

class AdminLocatorManagementScreen extends StatefulWidget {
  const AdminLocatorManagementScreen({super.key});

  @override
  State<AdminLocatorManagementScreen> createState() =>
      _AdminLocatorManagementScreenState();
}

class _AdminLocatorManagementScreenState
    extends State<AdminLocatorManagementScreen> {
  static const int _rowsPerPage = 10;

  _LocatorAdminQueue _queue = _LocatorAdminQueue.all;
  LocatorRequestType? _requestTypeFilter;
  bool _loading = false;
  String? _error;
  List<LocatorRequestType> _locatorTypes = LocatorRequestType.values;
  List<_LocatorAdminRecord> _items = [];
  String? _selectedItemId;
  int _page = 0;
  StreamSubscription<AppRealtimeEvent>? _locatorRealtimeSub;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  @override
  void initState() {
    super.initState();
    _loadLocatorTypes();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locatorRealtimeSub ??= context.read<AppRealtimeProvider>().events.listen((
      event,
    ) {
      if (event.name != 'locator_updated') return;
      unawaited(_load(forceRefresh: true));
    });
  }

  @override
  void dispose() {
    _locatorRealtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clampPage();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxListHeight = screenWidth < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final pageStart = _page * _rowsPerPage;
    final pageEnd = (pageStart + _rowsPerPage).clamp(0, _items.length);
    final pageItems = _items.sublist(pageStart, pageEnd);
    final useScrollableList = pageItems.length > 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Locator Request Management',
          style: TextStyle(
            color: _headingColor(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage locator, pass slip, and work-from-home requests from endorsement to HR approval.',
          style: TextStyle(color: _mutedColor(context), fontSize: 14),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _openTypeManagement,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Manage Types'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _LocatorAdminQueue.values
              .map(
                (queue) => ChoiceChip(
                  selected: _queue == queue,
                  label: Text(queue.label),
                  onSelected: (_) {
                    if (_queue == queue) return;
                    setState(() {
                      _queue = queue;
                      _selectedItemId = null;
                      _page = 0;
                    });
                    _load();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Type',
              style: TextStyle(
                color: _mutedColor(context),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<LocatorRequestType?>(
                initialValue: _requestTypeFilter,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  radius: 10,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<LocatorRequestType?>(
                    value: null,
                    child: Text('All types'),
                  ),
                  ..._locatorTypes.map(
                    (type) => DropdownMenuItem<LocatorRequestType?>(
                      value: type,
                      child: Text(type.shortLabel),
                    ),
                  ),
                ],
                onChanged: (type) {
                  if (_requestTypeFilter == type) return;
                  setState(() {
                    _requestTypeFilter = type;
                    _selectedItemId = null;
                    _page = 0;
                  });
                  _load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.dashSurfaceCard(context, radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inbox_rounded, color: AppTheme.primaryNavy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _queue == _LocatorAdminQueue.all
                          ? 'Locator Request Records'
                          : '${_queue.label} Queue',
                      style: TextStyle(
                        color: _headingColor(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                  ),
                ),
              if (_items.isEmpty && !_loading)
                Text(
                  'No locator request records in this queue.',
                  style: TextStyle(
                    color: _mutedColor(context),
                    fontSize: 13,
                    height: 1.45,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _adminItemsTable(
                        items: pageItems,
                        maxHeight: maxListHeight,
                        useScrollableList: useScrollableList,
                      ),
                      const SizedBox(height: 12),
                      _LocatorPaginationBar(
                        page: _page,
                        pageCount: _pageCount,
                        pageStart: pageStart,
                        pageEnd: pageEnd,
                        total: _items.length,
                        onPrevious: _page > 0
                            ? () => _goToPage(_page - 1)
                            : null,
                        onNext: _page < _pageCount - 1
                            ? () => _goToPage(_page + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminItemsTable({
    required List<_LocatorAdminRecord> items,
    required double maxHeight,
    required bool useScrollableList,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 1040
            ? 1040.0
            : constraints.maxWidth;
        final purposeWidth = tableWidth - 740;
        final content = SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _adminTableHeader(context, purposeWidth),
              for (var index = 0; index < items.length; index++)
                _adminTableRow(
                  context,
                  items[index],
                  purposeWidth: purposeWidth,
                  isLast: index == items.length - 1,
                  isSelected: items[index].id == _selectedItemId,
                  onTap: () => _openItemDetailsFromRow(items[index]),
                ),
            ],
          ),
        );

        final table = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          ),
        );

        if (!useScrollableList) return table;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              primary: false,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: table,
            ),
          ),
        );
      },
    );
  }

  int get _pageCount {
    if (_items.isEmpty) return 1;
    return (_items.length / _rowsPerPage).ceil();
  }

  void _clampPage() {
    final maxPage = _pageCount - 1;
    if (_page > maxPage) _page = maxPage;
    if (_page < 0) _page = 0;
  }

  void _goToPage(int page) {
    final maxPage = _pageCount - 1;
    setState(() => _page = page.clamp(0, maxPage).toInt());
  }

  Widget _adminTableHeader(BuildContext context, double purposeWidth) {
    return Container(
      height: 44,
      color: AppTheme.dashMutedSurfaceOf(context),
      child: Row(
        children: [
          _adminHeaderCell(context, 'Employee', width: 190),
          _adminHeaderCell(context, 'Date', width: 120),
          _adminHeaderCell(context, 'Purpose / Location', width: purposeWidth),
          _adminHeaderCell(context, 'Department', width: 160),
          _adminHeaderCell(context, 'Time', width: 120),
          _adminHeaderCell(context, 'Status', width: 150),
        ],
      ),
    );
  }

  Widget _adminTableRow(
    BuildContext context,
    _LocatorAdminRecord item, {
    required double purposeWidth,
    required bool isLast,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final dark = _isDark(context);
    final borderColor = AppTheme.dashHairlineOf(context);
    final rowColor = isSelected
        ? (dark
              ? AppTheme.primaryNavy.withValues(alpha: 0.35)
              : AppTheme.primaryNavy.withValues(alpha: 0.08))
        : Colors.transparent;
    final leftBorderColor = isSelected
        ? AppTheme.primaryNavy
        : Colors.transparent;

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: leftBorderColor, width: 4),
              bottom: isLast ? BorderSide.none : BorderSide(color: borderColor),
            ),
          ),
          child: Row(
            children: [
              _adminBodyCell(
                width: 186,
                child: _adminCellText(context, item.employeeName, strong: true),
              ),
              _adminBodyCell(
                width: 120,
                child: _adminCellText(context, item.slipDateLabel),
              ),
              _adminBodyCell(
                width: purposeWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _adminCellText(
                      context,
                      '${item.requestType.shortLabel} · ${item.office}',
                      strong: true,
                    ),
                    if (item.reason.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _adminCellText(
                        context,
                        item.reason,
                        color: _mutedColor(context),
                        fontSize: 12,
                      ),
                    ],
                  ],
                ),
              ),
              _adminBodyCell(
                width: 160,
                child: _adminCellText(
                  context,
                  item.departmentName.trim().isEmpty
                      ? '—'
                      : item.departmentName,
                ),
              ),
              _adminBodyCell(
                width: 120,
                child: _adminCellText(context, item.segmentText),
              ),
              _adminBodyCell(width: 150, child: _statusPill(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminHeaderCell(
    BuildContext context,
    String label, {
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _mutedColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminBodyCell({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _adminCellText(
    BuildContext context,
    String text, {
    bool strong = false,
    Color? color,
    double fontSize = 13,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? _headingColor(context),
        fontSize: fontSize,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  void _openItemDetailsFromRow(_LocatorAdminRecord item) {
    setState(() => _selectedItemId = item.id);
    _showDetailsDialog(item);
  }

  void _showDetailsDialog(_LocatorAdminRecord item) {
    final canReview = item.canHrReview;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.dashPanelOf(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Request Details',
                        style: TextStyle(
                          color: _headingColor(dialogContext),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: _mutedColor(dialogContext),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _detailTile('Employee', item.employeeName),
                      _detailTile('Department', item.departmentName),
                      _detailTile('Date', item.slipDate),
                      _detailTile('Type', item.requestType.label),
                      _detailTile(item.requestType.locationLabel, item.office),
                      _detailTile('Status', item.statusLabel),
                      _detailTile('Segments', item.segmentText),
                      _detailTile(
                        'Department Head',
                        item.deptHeadReviewerName ?? '—',
                      ),
                      _detailTile('HR Reviewer', item.hrReviewerName ?? '—'),
                      _detailTile('Attachment', item.attachmentName ?? '—'),
                      _detailTile('Reason/Purpose', item.reason, wide: true),
                      if ((item.deptHeadRemarks ?? '').trim().isNotEmpty)
                        _detailTile(
                          'Department Head Remarks',
                          item.deptHeadRemarks!,
                          wide: true,
                        ),
                      if ((item.hrRemarks ?? '').trim().isNotEmpty)
                        _detailTile('HR Remarks', item.hrRemarks!, wide: true),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _showHistoryDialog(item);
                        },
                        style: _dialogSecondaryButtonStyle(dialogContext),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('History'),
                      ),
                      if (canReview)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _reject(item);
                          },
                          style: _dialogDangerButtonStyle(dialogContext),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reject'),
                        ),
                      if (canReview)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _approve(item);
                          },
                          style: _dialogPrimaryButtonStyle(),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Approve'),
                        ),
                      canReview
                          ? OutlinedButton.icon(
                              onPressed: () => LocatorSlipPrint.printForm(
                                context: dialogContext,
                                id: item.id,
                                employeeName: item.employeeName,
                                dateText: item.slipDateLabel,
                                requestTypeLabel: item.requestType.label,
                                locationLabel: item.requestType.locationLabel,
                                office: item.office,
                                remarks: item.reason,
                                amIn: item.amIn,
                                amOut: item.amOut,
                                pmIn: item.pmIn,
                                pmOut: item.pmOut,
                              ),
                              style: _dialogSecondaryButtonStyle(dialogContext),
                              icon: const Icon(Icons.print_rounded, size: 18),
                              label: const Text('Print Form'),
                            )
                          : FilledButton.icon(
                              onPressed: () => LocatorSlipPrint.printForm(
                                context: dialogContext,
                                id: item.id,
                                employeeName: item.employeeName,
                                dateText: item.slipDateLabel,
                                requestTypeLabel: item.requestType.label,
                                locationLabel: item.requestType.locationLabel,
                                office: item.office,
                                remarks: item.reason,
                                amIn: item.amIn,
                                amOut: item.amOut,
                                pmIn: item.pmIn,
                                pmOut: item.pmOut,
                              ),
                              style: _dialogPrimaryButtonStyle(),
                              icon: const Icon(Icons.print_rounded, size: 18),
                              label: const Text('Print Form'),
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

  void _showHistoryDialog(_LocatorAdminRecord item) {
    final history = _historySteps(item);
    final accent = AppTheme.primaryNavy;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.dashPanelOf(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Request History',
                        style: TextStyle(
                          color: _headingColor(dialogContext),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: _mutedColor(dialogContext),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    children: List.generate(history.length, (index) {
                      final step = history[index];
                      final isFirst = index == 0;
                      final isLast = index == history.length - 1;
                      final actor = step.actor?.trim();
                      String subtitle = step.date == null
                          ? 'Awaiting action'
                          : _formatDateTime(step.date!);
                      if (actor != null && actor.isNotEmpty) {
                        subtitle = '$subtitle by $actor';
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 36,
                            height: isLast ? 58 : 96,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 17,
                                  top: isFirst ? 14 : 0,
                                  bottom: isLast ? 48 : 0,
                                  child: Container(width: 3, color: accent),
                                ),
                                Positioned(
                                  left: 5,
                                  top: 0,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: step.completed
                                          ? accent
                                          : Colors.grey.shade500,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      step.completed
                                          ? Icons.check_rounded
                                          : Icons.hourglass_top_rounded,
                                      size: 17,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: TextStyle(
                                      color: _headingColor(dialogContext),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: _mutedColor(dialogContext),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if ((step.remarks ?? '').trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Text(
                                        step.remarks!.trim(),
                                        style: TextStyle(
                                          color: _mutedColor(dialogContext),
                                          fontSize: 13,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
              Divider(height: 1, color: AppTheme.dashHairlineOf(dialogContext)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _dialogSecondaryButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      foregroundColor: AppTheme.dashTextPrimaryOf(context),
      side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _dialogDangerButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      foregroundColor: Colors.red.shade700,
      side: BorderSide(color: Colors.red.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _dialogPrimaryButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _detailTile(String label, String value, {bool wide = false}) {
    return SizedBox(
      width: wide ? 640 : 205,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _mutedColor(context),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value.trim().isEmpty ? '—' : value.trim(),
              style: TextStyle(color: _headingColor(context), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  List<_LocatorHistoryStep> _historySteps(_LocatorAdminRecord item) {
    return [
      (
        title: 'Submitted',
        actor: item.employeeName,
        date: item.createdAt ?? item.slipDateValue,
        remarks: null,
        completed: true,
      ),
      if (item.status == 'pending_department_head')
        (
          title: 'Pending Department Head',
          actor: item.deptHeadReviewerName,
          date: null,
          remarks: null,
          completed: false,
        ),
      if (item.deptHeadReviewedAt != null ||
          item.status == 'pending_hr' ||
          item.status == 'pending' ||
          item.status == 'approved' ||
          item.status == 'rejected_by_hr' ||
          item.status == 'rejected_by_department_head')
        (
          title: item.status == 'rejected_by_department_head'
              ? 'Rejected by Department Head'
              : 'Reviewed by Department Head',
          actor: item.deptHeadReviewerName,
          date: item.deptHeadReviewedAt,
          remarks: item.deptHeadRemarks,
          completed: true,
        ),
      if (item.canHrReview)
        (
          title: 'Pending HR Admin',
          actor: item.hrReviewerName,
          date: null,
          remarks: null,
          completed: false,
        ),
      if (item.status == 'approved')
        (
          title: 'Approved by HR',
          actor: item.hrReviewerName,
          date: item.hrReviewedAt,
          remarks: item.hrRemarks,
          completed: true,
        ),
      if (item.status == 'rejected_by_hr')
        (
          title: 'Rejected by HR',
          actor: item.hrReviewerName,
          date: item.hrReviewedAt,
          remarks: item.hrRemarks,
          completed: true,
        ),
      if (item.status == 'cancelled')
        (
          title: 'Cancelled',
          actor: null,
          date: item.updatedAt,
          remarks: null,
          completed: true,
        ),
    ];
  }

  void _showLocatorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
  }

  Widget _statusPill(_LocatorAdminRecord item) {
    final lower = item.status.toLowerCase();
    final isApproved = lower == 'approved';
    final isRejected = lower.contains('rejected');
    final isPending = lower.contains('pending');
    final bg = isApproved
        ? Colors.green.shade50
        : isRejected
        ? Colors.red.shade50
        : isPending
        ? Colors.blue.shade50
        : Colors.grey.shade100;
    final bd = isApproved
        ? Colors.green.shade300
        : isRejected
        ? Colors.red.shade300
        : isPending
        ? Colors.blue.shade300
        : Colors.grey.shade300;
    final fg = isApproved
        ? Colors.green.shade900
        : isRejected
        ? Colors.red.shade900
        : isPending
        ? Colors.blue.shade900
        : Colors.grey.shade900;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd),
      ),
      child: Text(
        item.statusLabel,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _loadLocatorTypes({bool forceRefresh = false}) async {
    try {
      final items = await LocatorSlipDataCache.instance.listTypes(
        includeInactive: true,
        forceRefresh: forceRefresh,
      );
      if (!mounted || items.isEmpty) return;
      setState(() => _locatorTypes = items);
    } catch (_) {
      // Keep built-in fallback types when configuration cannot be loaded.
    }
  }

  Future<void> _openTypeManagement() async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: const SizedBox(
          width: 1120,
          height: 720,
          child: LocatorTypeManagementScreen(),
        ),
      ),
    );
    if (!mounted) return;
    LocatorSlipDataCache.instance.invalidateAll();
    await _loadLocatorTypes(forceRefresh: true);
    await _load(forceRefresh: true);
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusParam = switch (_queue) {
        _LocatorAdminQueue.all => null,
        _LocatorAdminQueue.pendingDeptHead => 'pending_department_head',
        _LocatorAdminQueue.pendingHrAdmin => null,
        _LocatorAdminQueue.approved => 'approved',
        _LocatorAdminQueue.rejected => null,
        _LocatorAdminQueue.cancelled => 'cancelled',
      };
      final query = <String, String>{};
      if (statusParam != null) query['status'] = statusParam;
      if (_requestTypeFilter != null) {
        query['request_type'] = _requestTypeFilter!.code;
      }
      final all = (await LocatorSlipDataCache.instance.listAdminRequests(
        query: query,
        forceRefresh: forceRefresh,
      )).map((e) => _LocatorAdminRecord.fromJson(e)).toList();
      final filtered = switch (_queue) {
        _LocatorAdminQueue.pendingHrAdmin =>
          all.where((e) => e.canHrReview).toList(),
        _LocatorAdminQueue.rejected =>
          all
              .where((e) => e.status.toLowerCase().contains('rejected'))
              .toList(),
        _ => all,
      };
      if (!mounted) return;
      setState(() {
        _items = filtered;
        if (_selectedItemId != null &&
            !_items.any((item) => item.id == _selectedItemId)) {
          _selectedItemId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load locator requests: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(_LocatorAdminRecord item) async {
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/approve',
        data: const {},
      );
      LocatorSlipDataCache.instance.invalidateRequests();
      await _load(forceRefresh: true);
      if (!mounted) return;
      _showLocatorSnack('Request approved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Approve failed: $e');
    }
  }

  Future<void> _reject(_LocatorAdminRecord item) async {
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/reject',
        data: const {},
      );
      LocatorSlipDataCache.instance.invalidateRequests();
      await _load(forceRefresh: true);
      if (!mounted) return;
      _showLocatorSnack('Request rejected.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Reject failed: $e');
    }
  }
}

class _LocatorAdminRecord {
  const _LocatorAdminRecord({
    required this.id,
    required this.employeeName,
    required this.departmentName,
    required this.slipDate,
    this.requestType = LocatorRequestType.locator,
    required this.office,
    required this.reason,
    this.attachmentName,
    required this.status,
    this.deptHeadReviewerName,
    this.deptHeadReviewedAt,
    this.deptHeadRemarks,
    this.hrReviewerName,
    this.hrReviewedAt,
    this.hrRemarks,
    this.createdAt,
    this.updatedAt,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
  });

  final String id;
  final String employeeName;
  final String departmentName;
  final String slipDate;
  final LocatorRequestType requestType;
  final String office;
  final String reason;
  final String? attachmentName;
  final String status;
  final String? deptHeadReviewerName;
  final DateTime? deptHeadReviewedAt;
  final String? deptHeadRemarks;
  final String? hrReviewerName;
  final DateTime? hrReviewedAt;
  final String? hrRemarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;

  bool get canHrReview {
    final normalized = status.toLowerCase();
    return normalized == 'pending_hr' || normalized == 'pending';
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'pending_department_head':
        return 'Pending Dept Head';
      case 'pending_hr':
      case 'pending':
        return 'Pending HR Admin';
      case 'approved':
        return 'Approved';
      case 'rejected_by_department_head':
        return 'Rejected by Dept Head';
      case 'rejected_by_hr':
        return 'Rejected by HR';
      case 'cancelled':
        return 'Cancelled';
    }
    return status;
  }

  String get segmentText {
    final parts = <String>[];
    if (amIn) parts.add('AM IN');
    if (amOut) parts.add('AM OUT');
    if (pmIn) parts.add('PM IN');
    if (pmOut) parts.add('PM OUT');
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  DateTime? get slipDateValue => DateTime.tryParse(slipDate);

  String get slipDateLabel {
    final parsed = slipDateValue;
    return parsed == null ? slipDate : _formatDate(parsed);
  }

  factory _LocatorAdminRecord.fromJson(Map<String, dynamic> json) {
    return _LocatorAdminRecord(
      id: (json['id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? 'Employee').toString(),
      departmentName: (json['department_name'] ?? '').toString(),
      slipDate: (json['slip_date'] ?? '').toString(),
      requestType: LocatorRequestType.fromJson({
        'code': json['request_type'],
        'label': json['request_type_label'],
        'short_label': json['request_type_short_label'],
        'location_label': json['request_type_location_label'],
        'location_hint': json['request_type_location_hint'],
        'dtr_slot_label': json['request_type_dtr_slot_label'],
        'dtr_print_label': json['request_type_dtr_print_label'],
        'requires_attachment': json['request_type_requires_attachment'],
        'coverage_mode': json['request_type_coverage_mode'],
      }),
      office: (json['office'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      attachmentName: _trimOrNull(json['attachment_name']),
      status: (json['status'] ?? '').toString(),
      deptHeadReviewerName: _trimOrNull(json['dept_head_reviewer_name']),
      deptHeadReviewedAt: _parseDateTime(json['dept_head_reviewed_at']),
      deptHeadRemarks: _trimOrNull(json['dept_head_remarks']),
      hrReviewerName: _trimOrNull(json['hr_reviewer_name']),
      hrReviewedAt: _parseDateTime(json['hr_reviewed_at']),
      hrRemarks: _trimOrNull(json['hr_remarks']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      amIn: json['am_in'] == true,
      amOut: json['am_out'] == true,
      pmIn: json['pm_in'] == true,
      pmOut: json['pm_out'] == true,
    );
  }
}

class _LocatorPaginationBar extends StatelessWidget {
  const _LocatorPaginationBar({
    required this.page,
    required this.pageCount,
    required this.pageStart,
    required this.pageEnd,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final int pageStart;
  final int pageEnd;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final showingText = total == 0
        ? 'Showing 0 requests'
        : 'Showing ${pageStart + 1}-$pageEnd of $total requests';
    final pageText = 'Page ${page + 1} of $pageCount';
    final textStyle = TextStyle(
      color: AppTheme.dashTextSecondaryOf(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final info = Column(
          crossAxisAlignment: isNarrow
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(showingText, style: textStyle),
            const SizedBox(height: 2),
            Text(pageText, style: textStyle),
          ],
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('Next'),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [info, const SizedBox(height: 10), controls],
          );
        }

        return Row(
          children: [
            Expanded(child: info),
            controls,
          ],
        );
      },
    );
  }
}

String? _trimOrNull(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

DateTime? _parseDateTime(dynamic value) {
  final text = _trimOrNull(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

String _formatDate(DateTime value) {
  const months = [
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${_formatDate(value)} $hour:$minute $meridiem';
}
