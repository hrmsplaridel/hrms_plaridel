import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../utils/locator_slip_print.dart';

class EmployeeLocatorSlipScreen extends StatefulWidget {
  const EmployeeLocatorSlipScreen({super.key});

  @override
  State<EmployeeLocatorSlipScreen> createState() =>
      _EmployeeLocatorSlipScreenState();
}

class _EmployeeLocatorSlipScreenState extends State<EmployeeLocatorSlipScreen> {
  final List<_LocatorSlipDraft> _slips = [];
  final List<_LocatorSlipDraft> _deptHeadQueue = [];
  Future<bool>? _isDeptHeadFuture;
  _LocatorSection _currentSection = _LocatorSection.requests;
  bool _appliedDeptHeadDefaultSection = false;
  bool _loadingMy = false;
  bool _loadingApprovals = false;
  String? _error;
  String? _selectedStatusFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';
  String? _selectedSlipId;
  String? _selectedApprovalSlipId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDeptHeadFuture ??= _checkIsDepartmentHead();
    if (!_loadingMy && _slips.isEmpty) {
      _loadMyRequests();
    }
  }

  List<_LocatorSlipDraft> get _filteredSlips {
    return _slips.where((item) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final searchable =
            '${item.employeeName} ${item.office} ${item.remarks} ${item.status.label}'
                .toLowerCase();
        if (!searchable.contains(q)) return false;
      }
      if (_selectedStatusFilter != null) {
        if (_selectedStatusFilter == 'pending') {
          if (item.status != _LocatorSlipStatus.pendingDepartmentHead &&
              item.status != _LocatorSlipStatus.pendingHr) {
            return false;
          }
        } else if (_selectedStatusFilter == 'approved') {
          if (item.status != _LocatorSlipStatus.approved) return false;
        } else if (_selectedStatusFilter == 'rejected') {
          if (item.status != _LocatorSlipStatus.rejected) return false;
        } else if (_selectedStatusFilter == 'cancelled') {
          if (item.status != _LocatorSlipStatus.cancelled) return false;
        }
      }
      if (_fromDate != null &&
          _dateOnly(item.date).isBefore(_dateOnly(_fromDate!))) {
        return false;
      }
      if (_toDate != null &&
          _dateOnly(item.date).isAfter(_dateOnly(_toDate!))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName.trim().isEmpty
        ? 'Employee'
        : auth.displayName.trim();
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 860;

    return FutureBuilder<bool>(
      future: _isDeptHeadFuture,
      builder: (context, snapshot) {
        final isDepartmentHead = snapshot.data == true;
        if (isDepartmentHead && !_appliedDeptHeadDefaultSection) {
          _appliedDeptHeadDefaultSection = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _currentSection = _LocatorSection.approvals;
            });
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LocatorHeader(
              employeeName: displayName,
              onCreatePressed: () => _openCreateForm(context, displayName),
            ),
            if (isDepartmentHead) ...[
              const SizedBox(height: 16),
              _LocatorSectionTabs(
                current: _currentSection,
                onChanged: (section) {
                  setState(() => _currentSection = section);
                  if (section == _LocatorSection.approvals) {
                    _loadDepartmentHeadRequests();
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            if (_currentSection == _LocatorSection.requests)
              _buildMyRequests(width: width, compact: compact),
            if (_currentSection == _LocatorSection.approvals)
              _buildApprovalsView(),
          ],
        );
      },
    );
  }

  Widget _buildMyRequests({required double width, required bool compact}) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = width < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : width < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final visibleSlips = _filteredSlips;
    _LocatorSlipDraft? selectedSlip;
    for (final item in visibleSlips) {
      if (_slipSelectionKey(item) == _selectedSlipId) {
        selectedSlip = item;
        break;
      }
    }
    final useScrollableList = visibleSlips.length > 3;

    return _SectionCard(
      title: 'My Locator Slip Requests',
      subtitle:
          'Use filters to quickly find slips by status, date, office, or reason.',
      icon: Icons.receipt_long_rounded,
      headerTrailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: selectedSlip == null
                ? null
                : () => _showSlipDetails(context, selectedSlip!),
            child: const Text('View Details'),
          ),
          OutlinedButton(
            onPressed: selectedSlip == null
                ? null
                : () => _showSlipHistory(context, selectedSlip!),
            child: const Text('View History'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LocatorFiltersCard(
            selectedStatusFilter: _selectedStatusFilter,
            fromDate: _fromDate,
            toDate: _toDate,
            searchQuery: _searchQuery,
            visibleCount: _filteredSlips.length,
            totalCount: _slips.length,
            onStatusChanged: (status) =>
                setState(() => _selectedStatusFilter = status),
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            onPickFromDate: () => _pickFilterDate(isFrom: true),
            onPickToDate: () => _pickFilterDate(isFrom: false),
            onClearFilters: _clearFilters,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ErrorState(message: _error!),
            ),
          _loadingMy
              ? const _CenteredLoading(message: 'Loading locator slips...')
              : _slips.isEmpty
              ? const _EmptyState(
                  message:
                      'No locator slip requests yet. Click "File Locator Slip" to create one.',
                )
              : _filteredSlips.isEmpty
              ? const _EmptyState(
                  message: 'No locator slips match the current filters.',
                )
              : !useScrollableList
              ? Column(
                  children: List.generate(visibleSlips.length, (index) {
                    final item = visibleSlips[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == visibleSlips.length - 1 ? 0 : 10,
                      ),
                      child: _LocatorSlipCard(
                        item: item,
                        isSelected: item.id == _selectedSlipId,
                        onTap: () => _toggleSlipSelection(item),
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
                      itemCount: visibleSlips.length,
                      itemBuilder: (context, index) {
                        final item = visibleSlips[index];
                        return _LocatorSlipCard(
                          item: item,
                          isSelected:
                              _slipSelectionKey(item) == _selectedSlipId,
                          onTap: () => _toggleSlipSelection(item),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  void _toggleSlipSelection(_LocatorSlipDraft item) {
    final id = _slipSelectionKey(item);
    setState(() {
      _selectedSlipId = _selectedSlipId == id ? null : id;
    });
  }

  String _slipSelectionKey(_LocatorSlipDraft item) {
    return item.id ??
        '${item.date.toIso8601String()}-${item.office}-${item.employeeName}-${item.remarks}';
  }

  void _showSlipDetails(BuildContext context, _LocatorSlipDraft item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _LocatorSlipDetailsDialog(item: item),
    );
  }

  void _showSlipHistory(BuildContext context, _LocatorSlipDraft item) {
    final history = switch (item.status) {
      _LocatorSlipStatus.approved => [
        (title: 'Submitted', actor: null),
        (title: 'Reviewed by Department Head', actor: item.departmentHeadName),
        (title: 'Approved by HR', actor: item.hrReviewerName),
      ],
      _LocatorSlipStatus.rejected => [
        (title: 'Submitted', actor: null),
        (title: 'Reviewed by Department Head', actor: item.departmentHeadName),
        (
          title: 'Rejected',
          actor: item.hrReviewerName ?? item.departmentHeadName,
        ),
      ],
      _LocatorSlipStatus.cancelled => [
        (title: 'Submitted', actor: null),
        (title: 'Cancelled', actor: null),
      ],
      _LocatorSlipStatus.pendingHr => [
        (title: 'Submitted', actor: null),
        (title: 'Reviewed by Department Head', actor: item.departmentHeadName),
        (title: 'Pending HR Admin', actor: item.hrReviewerName),
      ],
      _LocatorSlipStatus.pendingDepartmentHead => [
        (title: 'Submitted', actor: null),
        (title: 'Pending Department Head', actor: item.departmentHeadName),
      ],
      _LocatorSlipStatus.draft => [(title: 'Draft', actor: null)],
    };
    final eventDate = _formatDate(item.date);
    final accent = AppTheme.primaryNavy;

    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Locator Slip History',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 40 * 0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: AppTheme.textSecondary),
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
                      String subtitle = eventDate;
                      if (actor != null && actor.isNotEmpty) {
                        subtitle = '$eventDate by $actor';
                      } else if (step.title.contains('Department Head') &&
                          step.title != 'Pending Department Head') {
                        subtitle = '$eventDate by Department Head';
                      } else if (step.title.contains('HR')) {
                        subtitle = '$eventDate by HR Admin';
                      }
                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              height: 96,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 20,
                                    top: isFirst ? 14 : 0,
                                    bottom: isLast ? 82 : 0,
                                    child: Container(width: 4, color: accent),
                                  ),
                                  Positioned(
                                    left: 8,
                                    top: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        size: 18,
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
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Divider(height: 1, color: AppTheme.lightGray),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 16),
                child: Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.15),
                        foregroundColor: accent,
                      ),
                      child: const Text('Close'),
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

  Widget _buildApprovalsView() {
    final pending = _deptHeadQueue;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = screenWidth < 600
        ? (screenHeight * 0.38).clamp(260.0, 420.0)
        : screenWidth < 1024
        ? (screenHeight * 0.5).clamp(320.0, 560.0)
        : (screenHeight * 0.58).clamp(380.0, 700.0);
    final useScrollableList = pending.length > 3;
    _LocatorSlipDraft? selectedApproval;
    for (final item in pending) {
      if (_slipSelectionKey(item) == _selectedApprovalSlipId) {
        selectedApproval = item;
        break;
      }
    }

    return _SectionCard(
      title: 'Locator Slip Approvals',
      subtitle: 'Department-head review queue for your office/department.',
      icon: Icons.fact_check_rounded,
      headerTrailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: selectedApproval == null
                ? null
                : () => _departmentHeadReject(selectedApproval!),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Reject'),
          ),
          FilledButton.icon(
            onPressed: selectedApproval == null
                ? null
                : () => _departmentHeadApprove(selectedApproval!),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Approve'),
          ),
        ],
      ),
      child: _loadingApprovals
          ? const _CenteredLoading(message: 'Loading approval queue...')
          : pending.isEmpty
          ? const _EmptyState(
              message: 'No pending locator slip requests for approval.',
            )
          : !useScrollableList
          ? Column(
              children: List.generate(pending.length, (index) {
                final item = pending[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == pending.length - 1 ? 0 : 10,
                  ),
                  child: _LocatorApprovalCard(
                    item: item,
                    isSelected:
                        _slipSelectionKey(item) == _selectedApprovalSlipId,
                    onTap: () => _toggleApprovalSelection(item),
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
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final item = pending[index];
                    return _LocatorApprovalCard(
                      item: item,
                      isSelected:
                          _slipSelectionKey(item) == _selectedApprovalSlipId,
                      onTap: () => _toggleApprovalSelection(item),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                ),
              ),
            ),
    );
  }

  void _toggleApprovalSelection(_LocatorSlipDraft item) {
    final id = _slipSelectionKey(item);
    setState(() {
      _selectedApprovalSlipId = _selectedApprovalSlipId == id ? null : id;
    });
  }

  Future<void> _openCreateForm(
    BuildContext context,
    String employeeName,
  ) async {
    final created = await showDialog<_LocatorSlipDraft>(
      context: context,
      builder: (_) => _LocatorSlipFormDialog(employeeName: employeeName),
    );
    if (!mounted || created == null) return;
    setState(() {
      _error = null;
      _loadingMy = true;
    });
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/locator-slips/submit',
        data: {
          'slip_date': _toIsoDate(created.date),
          'am_in': created.amIn,
          'am_out': created.amOut,
          'pm_in': created.pmIn,
          'pm_out': created.pmOut,
          'office': created.office,
          'reason': created.remarks,
        },
      );
      final data = res.data;
      _LocatorSlipDraft? inserted;
      if (data != null) {
        inserted = _LocatorSlipDraft.fromApi(data);
        setState(() => _slips.insert(0, inserted!));
      }
      if (!mounted) return;
      final msg = inserted != null
          ? (inserted.status == _LocatorSlipStatus.pendingHr
                ? 'Locator slip submitted. Awaiting HR approval.'
                : 'Locator slip submitted. Awaiting department head approval.')
          : 'Locator slip submitted successfully.';
      _showLocatorSnack(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to submit locator slip: $e');
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<bool> _checkIsDepartmentHead() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/department-head/check',
      );
      final isDeptHead = res.data?['isDeptHead'] == true;
      if (isDeptHead) {
        _loadDepartmentHeadRequests();
      }
      return isDeptHead;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadMyRequests() async {
    setState(() {
      _loadingMy = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/locator-slips/my',
      );
      final items = (res.data ?? const [])
          .whereType<Map>()
          .map((e) => _LocatorSlipDraft.fromApi(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _slips
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load locator slips: $e');
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _loadDepartmentHeadRequests() async {
    setState(() => _loadingApprovals = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/locator-slips/department-head',
      );
      final items = (res.data ?? const [])
          .whereType<Map>()
          .map((e) => _LocatorSlipDraft.fromApi(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _deptHeadQueue
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deptHeadQueue.clear();
      });
    } finally {
      if (mounted) setState(() => _loadingApprovals = false);
    }
  }

  Future<void> _departmentHeadApprove(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-approve',
        data: const {},
      );
      await _loadDepartmentHeadRequests();
      await _loadMyRequests();
      if (!mounted) return;
      _showLocatorSnack('Approved and sent to HR for final approval.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Approve failed: $e');
    }
  }

  Future<void> _departmentHeadReject(_LocatorSlipDraft item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      await ApiClient.instance.patch<Map<String, dynamic>>(
        '/api/locator-slips/${item.id}/department-head-reject',
        data: const {},
      );
      await _loadDepartmentHeadRequests();
      await _loadMyRequests();
      if (!mounted) return;
      _showLocatorSnack('Locator slip rejected.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Reject failed: $e');
    }
  }

  Future<void> _pickFilterDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? _fromDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
          _toDate = _fromDate;
        }
      } else {
        _toDate = picked;
        if (_fromDate != null && _fromDate!.isAfter(_toDate!)) {
          _fromDate = _toDate;
        }
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedStatusFilter = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _toIsoDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
}

/// Locator slip details — layout/positioning (theme borders and typography only).
class _LocatorSlipDetailsDialog extends StatelessWidget {
  const _LocatorSlipDetailsDialog({required this.item});

  final _LocatorSlipDraft item;

  String _segmentsLine() {
    final parts = <String>[];
    if (item.amIn) parts.add('AM IN');
    if (item.amOut) parts.add('AM OUT');
    if (item.pmIn) parts.add('PM IN');
    if (item.pmOut) parts.add('PM OUT');
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor;
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    Widget slipInformation() {
      return _LocatorDetailPanel(
        title: 'Slip Information',
        borderColor: borderColor,
        children: [
          _LocatorDetailLabeledBlock(
            label: 'Date',
            value: _formatDate(item.date),
          ),
          Divider(height: 1, thickness: 1, color: borderColor),
          _LocatorDetailLabeledBlock(
            label: 'Office/Destination',
            value: item.office,
          ),
          Divider(height: 1, thickness: 1, color: borderColor),
          _LocatorDetailLabeledBlock(
            label: 'Applicable Time Segment(s)',
            value: _segmentsLine(),
          ),
        ],
      );
    }

    Widget statusFiling() {
      return _LocatorDetailPanel(
        title: 'Status & Filing',
        borderColor: borderColor,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                _LocatorStatusBadgeOutline(status: item.status),
              ],
            ),
          ),
        ],
      );
    }

    Widget reasonPurpose() {
      return _LocatorDetailPanel(
        title: 'Reason/Purpose',
        borderColor: borderColor,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(item.remarks, style: theme.textTheme.bodyMedium),
          ),
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Locator Slip Details',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: borderColor),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 520;
                    final top = wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: slipInformation()),
                              const SizedBox(width: 12),
                              Expanded(child: statusFiling()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              slipInformation(),
                              const SizedBox(height: 12),
                              statusFiling(),
                            ],
                          );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        top,
                        const SizedBox(height: 12),
                        reasonPurpose(),
                      ],
                    );
                  },
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 40,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => LocatorSlipPrint.printForm(
                        context: context,
                        id: item.id,
                        employeeName: item.employeeName,
                        dateText: _formatDate(item.date),
                        office: item.office,
                        remarks: item.remarks,
                        amIn: item.amIn,
                        amOut: item.amOut,
                        pmIn: item.pmIn,
                        pmOut: item.pmOut,
                      ),
                      child: const Text('Print Form'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocatorDetailPanel extends StatelessWidget {
  const _LocatorDetailPanel({
    required this.title,
    required this.borderColor,
    required this.children,
  });

  final String title;
  final Color borderColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LocatorDetailLabeledBlock extends StatelessWidget {
  const _LocatorDetailLabeledBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _LocatorStatusBadgeOutline extends StatelessWidget {
  const _LocatorStatusBadgeOutline({required this.status});

  final _LocatorSlipStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = status == _LocatorSlipStatus.approved
        ? Icons.check
        : Icons.flag_outlined;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(status.label),
          ],
        ),
      ),
    );
  }
}

class _LocatorHeader extends StatelessWidget {
  const _LocatorHeader({
    required this.employeeName,
    required this.onCreatePressed,
  });

  final String employeeName;
  final VoidCallback onCreatePressed;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      child: Wrap(
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Locator Slip',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'File your movement log when you will be away from your workstation during office hours, $employeeName.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onCreatePressed,
            icon: const Icon(Icons.add_rounded),
            label: const Text('File Locator Slip'),
          ),
        ],
      ),
    );
  }
}

class _LocatorSlipFormDialog extends StatefulWidget {
  const _LocatorSlipFormDialog({required this.employeeName});

  final String employeeName;

  @override
  State<_LocatorSlipFormDialog> createState() => _LocatorSlipFormDialogState();
}

class _LocatorSlipFormDialogState extends State<_LocatorSlipFormDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _officeController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _amIn = false;
  bool _amOut = false;
  bool _pmIn = false;
  bool _pmOut = false;

  @override
  void dispose() {
    _officeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF57C00);
    return AlertDialog(
      backgroundColor: const Color(0xFFFFFDF7),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: const Text(
        'File Locator Slip',
        style: TextStyle(
          color: Color(0xFF111111),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _datePicker(),
                const SizedBox(height: 14),
                _segmentSelector(),
                const SizedBox(height: 14),
                _fieldLabel('Name'),
                TextFormField(
                  initialValue: widget.employeeName,
                  enabled: false,
                  decoration: _inputDecoration().copyWith(
                    hintText: widget.employeeName,
                  ),
                ),
                const SizedBox(height: 12),
                _fieldLabel('Office'),
                TextFormField(
                  controller: _officeController,
                  decoration: _inputDecoration(),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Office is required'
                      : null,
                ),
                const SizedBox(height: 12),
                _fieldLabel('Remarks / Reasons'),
                TextFormField(
                  controller: _remarksController,
                  minLines: 4,
                  maxLines: 4,
                  decoration: _inputDecoration().copyWith(
                    hintText: 'Enter remarks...',
                    alignLabelWithHint: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Remarks/Reasons is required'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 40,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Cancel'),
            ),
            SizedBox(width: 12),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(72, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _datePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date'),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _date = picked);
            }
          },
          child: InputDecorator(
            decoration: _inputDecoration().copyWith(
              suffixIcon: const Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: Color(0xFF7A7A7A),
              ),
            ),
            child: Text(_formatDate(_date)),
          ),
        ),
      ],
    );
  }

  Widget _segmentSelector() {
    const accent = Color(0xFFF57C00);
    const border = Color(0xFFBEBEBE);
    const divider = Color(0xFFC9C9C9);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Applicable Time Segment(s)'),
        const SizedBox(height: 8),
        Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              _segmentCell(
                label: 'AM IN',
                selected: _amIn,
                onTap: () => setState(() => _amIn = !_amIn),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'AM OUT',
                selected: _amOut,
                onTap: () => setState(() => _amOut = !_amOut),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'PM IN',
                selected: _pmIn,
                onTap: () => setState(() => _pmIn = !_pmIn),
                accent: accent,
              ),
              _segmentDivider(divider),
              _segmentCell(
                label: 'PM OUT',
                selected: _pmOut,
                onTap: () => setState(() => _pmOut = !_pmOut),
                accent: accent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentDivider(Color color) => Container(width: 1, color: color);

  Widget _segmentCell({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? accent : Colors.white),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF2F2F2F),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F1F1F),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      isDense: true,
      hintStyle: const TextStyle(color: Color(0xFFA7A7A7), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCFCFCF), width: 1.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCFCFCF), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFF57C00), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  void _save() {
    final hasTimeSegment = _amIn || _amOut || _pmIn || _pmOut;
    if (!hasTimeSegment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one AM/PM IN/OUT marker'),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      _LocatorSlipDraft(
        date: _date,
        employeeName: widget.employeeName,
        office: _officeController.text.trim(),
        remarks: _remarksController.text.trim(),
        amIn: _amIn,
        amOut: _amOut,
        pmIn: _pmIn,
        pmOut: _pmOut,
        status: _LocatorSlipStatus.pendingDepartmentHead,
      ),
    );
  }
}

class _LocatorSlipDraft {
  const _LocatorSlipDraft({
    this.id,
    required this.date,
    required this.employeeName,
    required this.office,
    required this.remarks,
    this.departmentHeadName,
    this.hrReviewerName,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.status,
  });

  final String? id;
  final DateTime date;
  final String employeeName;
  final String office;
  final String remarks;
  final String? departmentHeadName;
  final String? hrReviewerName;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;
  final _LocatorSlipStatus status;

  _LocatorSlipDraft copyWith({
    String? id,
    DateTime? date,
    String? employeeName,
    String? office,
    String? remarks,
    String? departmentHeadName,
    String? hrReviewerName,
    bool? amIn,
    bool? amOut,
    bool? pmIn,
    bool? pmOut,
    _LocatorSlipStatus? status,
  }) {
    return _LocatorSlipDraft(
      id: id ?? this.id,
      date: date ?? this.date,
      employeeName: employeeName ?? this.employeeName,
      office: office ?? this.office,
      remarks: remarks ?? this.remarks,
      departmentHeadName: departmentHeadName ?? this.departmentHeadName,
      hrReviewerName: hrReviewerName ?? this.hrReviewerName,
      amIn: amIn ?? this.amIn,
      amOut: amOut ?? this.amOut,
      pmIn: pmIn ?? this.pmIn,
      pmOut: pmOut ?? this.pmOut,
      status: status ?? this.status,
    );
  }

  factory _LocatorSlipDraft.fromApi(Map<String, dynamic> json) {
    final rawDate = (json['slip_date'] ?? '').toString();
    final parsedDate = DateTime.tryParse(rawDate);
    String? readName(List<String> keys) {
      for (final key in keys) {
        final value = (json[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      return null;
    }

    final status = _LocatorSlipStatus.fromApi(
      (json['status'] ?? '').toString(),
    );
    final genericReviewer = readName(['reviewer_name', 'approver_name']);
    return _LocatorSlipDraft(
      id: (json['id'] ?? '').toString(),
      date: parsedDate ?? DateTime.now(),
      employeeName: (json['employee_name'] ?? 'Employee').toString(),
      office: (json['office'] ?? '').toString(),
      remarks: (json['reason'] ?? '').toString(),
      departmentHeadName:
          readName([
            'dept_head_reviewer_name',
            'department_head_name',
            'dept_head_name',
            'reviewed_by_department_head_name',
            'department_head_reviewer_name',
          ]) ??
          (status == _LocatorSlipStatus.pendingHr ? genericReviewer : null),
      hrReviewerName:
          readName([
            'hr_name',
            'hr_reviewer_name',
            'reviewed_by_hr_name',
            'approved_by_hr_name',
          ]) ??
          ((status == _LocatorSlipStatus.approved ||
                  status == _LocatorSlipStatus.rejected)
              ? genericReviewer
              : null),
      amIn: json['am_in'] == true,
      amOut: json['am_out'] == true,
      pmIn: json['pm_in'] == true,
      pmOut: json['pm_out'] == true,
      status: status,
    );
  }
}

enum _LocatorSlipStatus {
  draft('Draft'),
  pendingDepartmentHead('Pending Dept Head'),
  pendingHr('Pending HR Admin'),
  approved('Approved'),
  rejected('Rejected'),
  cancelled('Cancelled');

  const _LocatorSlipStatus(this.label);
  final String label;

  static _LocatorSlipStatus fromApi(String status) {
    switch (status) {
      case 'draft':
        return _LocatorSlipStatus.draft;
      case 'pending_department_head':
        return _LocatorSlipStatus.pendingDepartmentHead;
      case 'pending_hr':
      case 'pending':
        return _LocatorSlipStatus.pendingHr;
      case 'approved':
        return _LocatorSlipStatus.approved;
      case 'cancelled':
        return _LocatorSlipStatus.cancelled;
      case 'rejected_by_department_head':
      case 'rejected_by_hr':
        return _LocatorSlipStatus.rejected;
      default:
        return _LocatorSlipStatus.draft;
    }
  }
}

enum _LocatorSection { requests, approvals }

class _LocatorSlipCard extends StatelessWidget {
  const _LocatorSlipCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _LocatorSlipDraft item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: AppTheme.primaryNavy,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatDate(item.date),
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _statusPill(item.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Office: ${item.office}',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item.amIn) _timeChip('AM IN'),
                  if (item.amOut) _timeChip('AM OUT'),
                  if (item.pmIn) _timeChip('PM IN'),
                  if (item.pmOut) _timeChip('PM OUT'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.remarks,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(_LocatorSlipStatus status) {
    final (bg, border, textColor) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _timeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LocatorApprovalCard extends StatelessWidget {
  const _LocatorApprovalCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _LocatorSlipDraft item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryNavy.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.employeeName,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatDate(item.date)} • ${item.office}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 10),
              Text(
                item.remarks,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _LocatorSectionTabs extends StatelessWidget {
  const _LocatorSectionTabs({required this.current, required this.onChanged});

  final _LocatorSection current;
  final ValueChanged<_LocatorSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _tab(
          label: 'My Requests',
          icon: Icons.event_note_rounded,
          selected: current == _LocatorSection.requests,
          onTap: () => onChanged(_LocatorSection.requests),
        ),
        _tab(
          label: 'Approvals',
          icon: Icons.fact_check_rounded,
          selected: current == _LocatorSection.approvals,
          onTap: () => onChanged(_LocatorSection.approvals),
        ),
      ],
    );
  }

  Widget _tab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppTheme.primaryNavy.withValues(alpha: 0.12)
          : AppTheme.lightGray.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppTheme.primaryNavy : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primaryNavy : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocatorFiltersCard extends StatelessWidget {
  const _LocatorFiltersCard({
    required this.selectedStatusFilter,
    required this.fromDate,
    required this.toDate,
    required this.searchQuery,
    required this.visibleCount,
    required this.totalCount,
    required this.onStatusChanged,
    required this.onSearchChanged,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onClearFilters,
  });

  final String? selectedStatusFilter;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String searchQuery;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFD7DCE2);
    const activePill = Color(0xFF123B6D);
    const inactiveText = Color(0xFF2D3640);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              height: 36,
              child: TextFormField(
                key: ValueKey(searchQuery),
                initialValue: searchQuery,
                onChanged: onSearchChanged,
                style: const TextStyle(
                  color: Color(0xFF2D3640),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _filterDecoration(
                  hintText: 'Search',
                  borderColor: border,
                  suffixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Color(0xFF8792A0),
                  ),
                ),
              ),
            ),
            _dateButton(
              label: fromDate == null ? 'From' : _formatDate(fromDate!),
              onPressed: onPickFromDate,
              borderColor: border,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '-',
                style: TextStyle(
                  color: Color(0xFF7F8895),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            _dateButton(
              label: toDate == null ? 'To' : _formatDate(toDate!),
              onPressed: onPickToDate,
              borderColor: border,
            ),
            _statusChip(
              label: 'All',
              selected: selectedStatusFilter == null,
              onTap: () => onStatusChanged(null),
              selectedColor: activePill,
              unselectedTextColor: inactiveText,
            ),
            ...const ['pending', 'approved', 'rejected', 'cancelled'].map(
              (statusKey) => _statusChip(
                label: _statusFilterLabel(statusKey),
                selected: selectedStatusFilter == statusKey,
                onTap: () => onStatusChanged(statusKey),
                selectedColor: activePill,
                unselectedTextColor: inactiveText,
              ),
            ),
            TextButton(
              onPressed: onClearFilters,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1A568B),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$visibleCount of $totalCount',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _dateButton({
    required String label,
    required VoidCallback onPressed,
    required Color borderColor,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF556070),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        icon: const Icon(
          Icons.calendar_today_rounded,
          size: 16,
          color: Color(0xFF8A95A3),
        ),
        label: Text(label),
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color selectedColor,
    required Color unselectedTextColor,
  }) {
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? selectedColor : const Color(0xFFF7F8FA),
          foregroundColor: selected ? Colors.white : unselectedTextColor,
          side: const BorderSide(color: Color(0xFFDDE2E8)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }

  static String _statusFilterLabel(String key) {
    switch (key) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return key;
    }
  }

  InputDecoration _filterDecoration({
    required String hintText,
    required Color borderColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF8D96A3),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF123B6D), width: 1.2),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.headerTrailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primaryNavy, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: headerTrailing!,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.red.shade900, fontSize: 12),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
      ),
    );
  }
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

(Color, Color, Color) _statusColors(_LocatorSlipStatus status) {
  return switch (status) {
    _LocatorSlipStatus.draft => (
      Colors.amber.shade50,
      Colors.amber.shade300,
      Colors.amber.shade900,
    ),
    _LocatorSlipStatus.pendingDepartmentHead || _LocatorSlipStatus.pendingHr =>
      (Colors.blue.shade50, Colors.blue.shade300, Colors.blue.shade900),
    _LocatorSlipStatus.approved => (
      Colors.green.shade50,
      Colors.green.shade300,
      Colors.green.shade900,
    ),
    _LocatorSlipStatus.rejected => (
      Colors.red.shade50,
      Colors.red.shade300,
      Colors.red.shade900,
    ),
    _LocatorSlipStatus.cancelled => (
      Colors.grey.shade100,
      Colors.grey.shade400,
      Colors.grey.shade800,
    ),
  };
}
