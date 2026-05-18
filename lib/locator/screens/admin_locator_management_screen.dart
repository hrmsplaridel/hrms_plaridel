import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../realtime/app_realtime_provider.dart';
import '../utils/locator_slip_print.dart';

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
  _LocatorAdminQueue _queue = _LocatorAdminQueue.all;
  bool _loading = false;
  bool _acting = false;
  String? _error;
  List<_LocatorAdminRecord> _items = [];
  String? _selectedItemId;
  StreamSubscription<AppRealtimeEvent>? _locatorRealtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locatorRealtimeSub ??=
        context.read<AppRealtimeProvider>().events.listen((event) {
      if (event.name != 'locator_updated') return;
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _locatorRealtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxListHeight = screenWidth < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final useScrollableList = _items.length > 3;
    _LocatorAdminRecord? selectedItem;
    for (final item in _items) {
      if (item.id == _selectedItemId) {
        selectedItem = item;
        break;
      }
    }
    final canReviewSelected = selectedItem?.canHrReview == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Locator Slip Management',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage locator slip workflow from department-head endorsement up to HR final approval.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
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
                    setState(() => _queue = queue);
                    _load();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
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
                          ? 'Locator Slip Records'
                          : '${_queue.label} Queue',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedItem == null
                        ? null
                        : () => _showDetailsDialog(selectedItem!),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('View'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: selectedItem == null
                        ? null
                        : () => _showHistoryDialog(selectedItem!),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('History'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _acting || !canReviewSelected
                        ? null
                        : () => _reject(selectedItem!),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _acting || !canReviewSelected
                        ? null
                        : () => _approve(selectedItem!),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                  const SizedBox(width: 12),
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
                  'No locator slip records in this queue.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                )
              else
                !useScrollableList
                    ? Column(
                        children: List.generate(_items.length, (index) {
                          final item = _items[index];
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _adminItemCard(
                              item,
                              isSelected: item.id == _selectedItemId,
                              onTap: () => _toggleItemSelection(item.id),
                            ),
                          );
                        }),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxListHeight),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: ListView.separated(
                            primary: false,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return _adminItemCard(
                                item,
                                isSelected: item.id == _selectedItemId,
                                onTap: () => _toggleItemSelection(item.id),
                              );
                            },
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminItemCard(
    _LocatorAdminRecord item, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.offWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.employeeName,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _statusPill(item),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${item.slipDate} • ${item.office}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              if (item.departmentName.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.departmentName,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item.amIn) _chip('AM IN'),
                  if (item.amOut) _chip('AM OUT'),
                  if (item.pmIn) _chip('PM IN'),
                  if (item.pmOut) _chip('PM OUT'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.reason,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              if ((item.deptHeadReviewerName ?? item.hrReviewerName) !=
                  null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if ((item.deptHeadReviewerName ?? '').trim().isNotEmpty)
                      _chip('Dept Head: ${item.deptHeadReviewerName}'),
                    if ((item.hrReviewerName ?? '').trim().isNotEmpty)
                      _chip('HR: ${item.hrReviewerName}'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggleItemSelection(String id) {
    setState(() {
      _selectedItemId = _selectedItemId == id ? null : id;
    });
  }

  void _showDetailsDialog(_LocatorAdminRecord item) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
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
                        'Locator Slip Details',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.lightGray),
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
                      _detailTile('Office/Destination', item.office),
                      _detailTile('Status', item.statusLabel),
                      _detailTile('Segments', item.segmentText),
                      _detailTile(
                        'Department Head',
                        item.deptHeadReviewerName ?? '—',
                      ),
                      _detailTile('HR Reviewer', item.hrReviewerName ?? '—'),
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
              Divider(height: 1, color: AppTheme.lightGray),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => LocatorSlipPrint.printForm(
                        context: context,
                        id: item.id,
                        employeeName: item.employeeName,
                        dateText: item.slipDateLabel,
                        office: item.office,
                        remarks: item.reason,
                        amIn: item.amIn,
                        amOut: item.amOut,
                        pmIn: item.pmIn,
                        pmOut: item.pmOut,
                      ),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Print Form'),
                    ),
                  ],
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
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
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
                        'Locator Slip History',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.lightGray),
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
                                      color: AppTheme.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
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
                                          color: AppTheme.textSecondary,
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
              Divider(height: 1, color: AppTheme.lightGray),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
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

  Widget _detailTile(String label, String value, {bool wide = false}) {
    return SizedBox(
      width: wide ? 640 : 205,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.offWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value.trim().isEmpty ? '—' : value.trim(),
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
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

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
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

  Future<void> _load() async {
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
      final path = statusParam == null
          ? '/api/locator-slips/admin'
          : '/api/locator-slips/admin?status=$statusParam';
      final res = await ApiClient.instance.get<List<dynamic>>(path);
      final all = (res.data ?? const [])
          .whereType<Map>()
          .map(
            (e) => _LocatorAdminRecord.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
      final filtered = switch (_queue) {
        _LocatorAdminQueue.pendingHrAdmin => all
            .where((e) => e.canHrReview)
            .toList(),
        _LocatorAdminQueue.rejected => all
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
      setState(() => _error = 'Failed to load locator slips: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(_LocatorAdminRecord item) async {
    setState(() => _acting = true);
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/approve',
        data: const {},
      );
      await _load();
      if (!mounted) return;
      _showLocatorSnack('Locator slip approved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Approve failed: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reject(_LocatorAdminRecord item) async {
    setState(() => _acting = true);
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/reject',
        data: const {},
      );
      await _load();
      if (!mounted) return;
      _showLocatorSnack('Locator slip rejected.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Reject failed: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }
}

class _LocatorAdminRecord {
  const _LocatorAdminRecord({
    required this.id,
    required this.employeeName,
    required this.departmentName,
    required this.slipDate,
    required this.office,
    required this.reason,
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
  final String office;
  final String reason;
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
      office: (json['office'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
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
