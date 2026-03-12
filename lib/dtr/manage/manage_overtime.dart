import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _OvertimeRecord {
  const _OvertimeRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.otDate,
    required this.timeStart,
    required this.timeEnd,
    required this.totalHours,
    this.reason,
    required this.status,
    this.reviewNotes,
    required this.addedToPayroll,
    required this.createdAt,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime otDate;
  final String timeStart;
  final String timeEnd;
  final double totalHours;
  final String? reason;
  final String status;
  final String? reviewNotes;
  final bool addedToPayroll;
  final DateTime createdAt;
}

class ManageOvertime extends StatefulWidget {
  const ManageOvertime({super.key});

  @override
  State<ManageOvertime> createState() => _ManageOvertimeState();
}

class _ManageOvertimeState extends State<ManageOvertime> {
  String _statusFilter = 'pending';
  List<_OvertimeRecord> _requests = [];
  bool _loading = false;

  final _otDate = ValueNotifier<DateTime?>(null);
  final _timeStart = ValueNotifier<TimeOfDay?>(null);
  final _timeEnd = ValueNotifier<TimeOfDay?>(null);
  final _totalHoursController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _selectedEmployeeIdForSubmit;
  List<Map<String, dynamic>> _employees = [];
  bool _showSubmitForm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRequests();
      _loadEmployees();
    });
  }

  @override
  void dispose() {
    _otDate.dispose();
    _timeStart.dispose();
    _timeEnd.dispose();
    _totalHoursController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: {'status': 'Active'},
      );
      final data = res.data ?? [];
      _employees = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'] as String, 'full_name': m['full_name'] as String? ?? '—'};
      }).toList();
    } catch (_) {}
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/overtime',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _requests = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return _OvertimeRecord(
          id: m['id'] as String,
          employeeId: m['employee_id'] as String,
          employeeName: m['employee_name'] as String? ?? '—',
          otDate: _parseDate(m['ot_date']),
          timeStart: _timeStrFromDynamic(m['time_start']),
          timeEnd: _timeStrFromDynamic(m['time_end']),
          totalHours: (m['total_hours'] as num?)?.toDouble() ?? 0,
          reason: m['reason'] as String?,
          status: m['status'] as String? ?? 'pending',
          reviewNotes: m['review_notes'] as String?,
          addedToPayroll: m['added_to_payroll'] as bool? ?? false,
          createdAt: _parseDateTime(m['created_at']) ?? DateTime.now(),
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load overtime failed: ${e.response?.data ?? e.message}');
      _requests = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    if (s.length >= 10) return DateTime.tryParse(s.substring(0, 10)) ?? DateTime.now();
    return DateTime.now();
  }

  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  String _timeStrFromDynamic(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  Future<void> _submitRequest() async {
    final otDate = _otDate.value;
    final timeStart = _timeStart.value;
    final timeEnd = _timeEnd.value;
    final totalHours = double.tryParse(_totalHoursController.text.trim());
    if (otDate == null || timeStart == null || timeEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set OT date, start time, and end time.')),
      );
      return;
    }
    if (totalHours == null || totalHours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid total hours.')),
      );
      return;
    }
    final timeStartStr = '${timeStart.hour.toString().padLeft(2, '0')}:${timeStart.minute.toString().padLeft(2, '0')}:00';
    final timeEndStr = '${timeEnd.hour.toString().padLeft(2, '0')}:${timeEnd.minute.toString().padLeft(2, '0')}:00';
    try {
      await ApiClient.instance.post(
        '/api/overtime',
        data: {
          if (_selectedEmployeeIdForSubmit != null) 'employee_id': _selectedEmployeeIdForSubmit,
          'ot_date': otDate.toIso8601String().split('T').first,
          'time_start': timeStartStr,
          'time_end': timeEndStr,
          'total_hours': totalHours,
          'reason': _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Overtime request submitted.')));
        _totalHoursController.clear();
        _reasonController.clear();
        _otDate.value = null;
        _timeStart.value = null;
        _timeEnd.value = null;
        _selectedEmployeeIdForSubmit = null;
        setState(() => _showSubmitForm = false);
        _loadRequests();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  Future<void> _review(String id, String status, [String? reviewNotes]) async {
    try {
      await ApiClient.instance.patch(
        '/api/overtime/$id/review',
        data: {'status': status, 'review_notes': reviewNotes?.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Overtime $status.')));
        _loadRequests();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  Future<void> _markAddedToPayroll(String id) async {
    try {
      await ApiClient.instance.patch('/api/overtime/$id/payroll', data: {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as added to payroll.')));
        _loadRequests();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  void _showReviewDialog(_OvertimeRecord r, bool approve) {
    final reviewNotesController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve overtime' : 'Reject overtime'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${r.employeeName} · ${r.otDate.year}-${r.otDate.month.toString().padLeft(2, '0')}-${r.otDate.day.toString().padLeft(2, '0')}'),
            Text('${r.timeStart} – ${r.timeEnd} (${r.totalHours} hrs)'),
            if (r.reason != null && r.reason!.isNotEmpty) Text('Reason: ${r.reason}'),
            const SizedBox(height: 12),
            TextField(
              controller: reviewNotesController,
              decoration: const InputDecoration(labelText: 'Review notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _review(r.id, approve ? 'approved' : 'rejected', reviewNotesController.text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: approve ? const Color(0xFF4CAF50) : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overtime Management',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Submit overtime requests; supervisors approve and add to payroll.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (_showSubmitForm) ...[
          _buildSubmitForm(),
          const SizedBox(height: 24),
        ],
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: [
                      const DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      const DropdownMenuItem(value: 'approved', child: Text('Approved')),
                      const DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      const DropdownMenuItem(value: 'All', child: Text('All')),
                    ],
                    onChanged: (v) {
                      setState(() => _statusFilter = v ?? 'pending');
                      _loadRequests();
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loading ? null : _loadRequests,
                    tooltip: 'Refresh',
                  ),
                  const Spacer(),
                  if (!_showSubmitForm)
                    FilledButton.icon(
                      onPressed: () => setState(() => _showSubmitForm = true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Submit OT Request'),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_requests.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No overtime requests', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: _requests.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _requests[i];
                    final isPending = r.status == 'pending';
                    final isApproved = r.status == 'approved';
                    return ListTile(
                      title: Text(
                        r.employeeName,
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      subtitle: Text(
                        '${r.otDate.year}-${r.otDate.month.toString().padLeft(2, '0')}-${r.otDate.day.toString().padLeft(2, '0')} · '
                        '${r.timeStart} – ${r.timeEnd} · ${r.totalHours} hrs${r.reason != null && r.reason!.isNotEmpty ? '\n${r.reason}' : ''}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPending) ...[
                            TextButton(
                              onPressed: () => _showReviewDialog(r, true),
                              child: const Text('Approve'),
                              style: TextButton.styleFrom(foregroundColor: const Color(0xFF4CAF50)),
                            ),
                            TextButton(
                              onPressed: () => _showReviewDialog(r, false),
                              child: const Text('Reject'),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ] else if (isApproved && !r.addedToPayroll)
                            TextButton(
                              onPressed: () => _markAddedToPayroll(r.id),
                              child: const Text('Add to payroll'),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: r.status == 'approved'
                                    ? const Color(0xFF4CAF50).withOpacity(0.15)
                                    : r.status == 'rejected'
                                        ? Colors.red.withOpacity(0.15)
                                        : AppTheme.lightGray,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                r.addedToPayroll ? 'In payroll' : r.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: r.status == 'approved' ? const Color(0xFF2E7D32) : r.status == 'rejected' ? Colors.red : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Submit overtime request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 16),
          if (_employees.isNotEmpty) ...[
            Text('Employee (optional – leave blank for yourself)', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedEmployeeIdForSubmit,
              decoration: InputDecoration(
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Myself')),
                ..._employees.map((e) => DropdownMenuItem(value: e['id'] as String, child: Text(e['full_name'] as String))),
              ],
              onChanged: (v) => setState(() => _selectedEmployeeIdForSubmit = v),
            ),
            const SizedBox(height: 16),
          ],
          Text('OT date', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          ValueListenableBuilder<DateTime?>(
            valueListenable: _otDate,
            builder: (_, value, __) => InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: value ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) _otDate.value = d;
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(value != null ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}' : 'Select date'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start time', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<TimeOfDay?>(
                      valueListenable: _timeStart,
                      builder: (_, value, __) => InkWell(
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: value ?? TimeOfDay.now());
                          if (t != null) _timeStart.value = t;
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(value != null ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}' : 'Select'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('End time', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<TimeOfDay?>(
                      valueListenable: _timeEnd,
                      builder: (_, value, __) => InkWell(
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: value ?? TimeOfDay.now());
                          if (t != null) _timeEnd.value = t;
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(value != null ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}' : 'Select'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Total hours', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _totalHoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. 2.5',
              filled: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Reason (optional)', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _reasonController,
            decoration: const InputDecoration(
              hintText: 'Reason for overtime',
              filled: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _submitRequest,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Submit'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => setState(() => _showSubmitForm = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
