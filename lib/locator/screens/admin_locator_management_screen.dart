import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

enum _LocatorAdminQueue {
  pendingDeptHead('Pending Dept Head'),
  pendingHrAdmin('Pending HR Admin'),
  approved('Approved'),
  rejected('Rejected');

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
  _LocatorAdminQueue _queue = _LocatorAdminQueue.pendingHrAdmin;
  bool _loading = false;
  bool _acting = false;
  String? _error;
  List<_LocatorAdminRecord> _items = [];
  String? _selectedItemId;

  @override
  void initState() {
    super.initState();
    _load();
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
                      '${_queue.label} Queue',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_queue == _LocatorAdminQueue.pendingHrAdmin) ...[
                    OutlinedButton.icon(
                      onPressed: _acting || selectedItem == null
                          ? null
                          : () => _reject(selectedItem!),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _acting || selectedItem == null
                          ? null
                          : () => _approve(selectedItem!),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                    const SizedBox(width: 12),
                  ],
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
                  _statusPill(item.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${item.slipDate} • ${item.office}',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
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

  Widget _statusPill(String status) {
    final lower = status.toLowerCase();
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
        status,
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
        _LocatorAdminQueue.pendingDeptHead => 'pending_department_head',
        _LocatorAdminQueue.pendingHrAdmin => 'pending_hr',
        _LocatorAdminQueue.approved => 'approved',
        _LocatorAdminQueue.rejected => null,
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
      final filtered = _queue == _LocatorAdminQueue.rejected
          ? all
                .where((e) => e.status.toLowerCase().contains('rejected'))
                .toList()
          : all;
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
    required this.slipDate,
    required this.office,
    required this.reason,
    required this.status,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
  });

  final String id;
  final String employeeName;
  final String slipDate;
  final String office;
  final String reason;
  final String status;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;

  factory _LocatorAdminRecord.fromJson(Map<String, dynamic> json) {
    return _LocatorAdminRecord(
      id: (json['id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? 'Employee').toString(),
      slipDate: (json['slip_date'] ?? '').toString(),
      office: (json['office'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      amIn: json['am_in'] == true,
      amOut: json['am_out'] == true,
      pmIn: json['pm_in'] == true,
      pmOut: json['pm_out'] == true,
    );
  }
}
