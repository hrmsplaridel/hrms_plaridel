import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';

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
  _LocatorSlipStatus? _selectedStatus;
  DateTime? _fromDate;
  DateTime? _toDate;
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
      if (_selectedStatus != null && item.status != _selectedStatus)
        return false;
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
            selectedStatus: _selectedStatus,
            fromDate: _fromDate,
            toDate: _toDate,
            visibleCount: _filteredSlips.length,
            totalCount: _slips.length,
            onStatusChanged: (status) =>
                setState(() => _selectedStatus = status),
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
      builder: (_) => AlertDialog(
        title: const Text('Locator Slip Details'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${_formatDate(item.date)}'),
              const SizedBox(height: 6),
              Text('Office: ${item.office}'),
              const SizedBox(height: 6),
              Text('Status: ${item.status.label}'),
              const SizedBox(height: 10),
              Text('Reason: ${item.remarks}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSlipHistory(BuildContext context, _LocatorSlipDraft item) {
    final history = switch (item.status) {
      _LocatorSlipStatus.approved => const [
        'Submitted',
        'Reviewed by Department Head',
        'Approved by HR',
      ],
      _LocatorSlipStatus.rejected => const [
        'Submitted',
        'Reviewed by Department Head',
        'Rejected',
      ],
      _LocatorSlipStatus.cancelled => const ['Submitted', 'Cancelled'],
      _LocatorSlipStatus.pendingHr => const [
        'Submitted',
        'Reviewed by Department Head',
        'Pending HR Admin',
      ],
      _LocatorSlipStatus.pendingDepartmentHead => const [
        'Submitted',
        'Pending Department Head',
      ],
      _LocatorSlipStatus.draft => const ['Draft'],
    };

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Locator Slip History'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: history
                .map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.circle, size: 8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(step)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
      if (data != null) {
        final inserted = _LocatorSlipDraft.fromApi(data);
        setState(() => _slips.insert(0, inserted));
      }
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
      _selectedStatus = null;
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
    return AlertDialog(
      title: const Text('File Locator Slip'),
      content: SizedBox(
        width: 560,
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
                TextFormField(
                  initialValue: widget.employeeName,
                  enabled: false,
                  decoration: _inputDecoration('Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _officeController,
                  decoration: _inputDecoration('Office'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Office is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: _inputDecoration('Remarks / Reasons'),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _datePicker() {
    return InkWell(
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
        decoration: _inputDecoration('Date'),
        child: Text(_formatDate(_date)),
      ),
    );
  }

  Widget _segmentSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Applicable Time Segment(s)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: _amIn,
              label: const Text('AM IN'),
              onSelected: (v) => setState(() => _amIn = v),
            ),
            FilterChip(
              selected: _amOut,
              label: const Text('AM OUT'),
              onSelected: (v) => setState(() => _amOut = v),
            ),
            FilterChip(
              selected: _pmIn,
              label: const Text('PM IN'),
              onSelected: (v) => setState(() => _pmIn = v),
            ),
            FilterChip(
              selected: _pmOut,
              label: const Text('PM OUT'),
              onSelected: (v) => setState(() => _pmOut = v),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    return _LocatorSlipDraft(
      id: (json['id'] ?? '').toString(),
      date: parsedDate ?? DateTime.now(),
      employeeName: (json['employee_name'] ?? 'Employee').toString(),
      office: (json['office'] ?? '').toString(),
      remarks: (json['reason'] ?? '').toString(),
      amIn: json['am_in'] == true,
      amOut: json['am_out'] == true,
      pmIn: json['pm_in'] == true,
      pmOut: json['pm_out'] == true,
      status: _LocatorSlipStatus.fromApi((json['status'] ?? '').toString()),
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
    required this.selectedStatus,
    required this.fromDate,
    required this.toDate,
    required this.visibleCount,
    required this.totalCount,
    required this.onStatusChanged,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onClearFilters,
  });

  final _LocatorSlipStatus? selectedStatus;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<_LocatorSlipStatus?> onStatusChanged;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Filters',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$visibleCount of $totalCount',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onPickFromDate,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(
                fromDate == null
                    ? 'From date'
                    : 'From: ${_formatDate(fromDate!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickToDate,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                toDate == null ? 'To date' : 'To: ${_formatDate(toDate!)}',
              ),
            ),
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              selected: selectedStatus == null,
              label: const Text('All'),
              onSelected: (_) => onStatusChanged(null),
            ),
            ..._LocatorSlipStatus.values.map(
              (status) => ChoiceChip(
                selected: selectedStatus == status,
                label: Text(status.label),
                onSelected: (_) => onStatusChanged(status),
              ),
            ),
          ],
        ),
      ],
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
