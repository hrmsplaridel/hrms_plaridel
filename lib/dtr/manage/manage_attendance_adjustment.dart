import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _CorrectionRecord {
  const _CorrectionRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.attendanceDate,
    this.requestedTimeIn,
    this.requestedTimeOut,
    required this.reason,
    required this.status,
    this.reviewedAt,
    this.reviewNotes,
    required this.createdAt,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime attendanceDate;
  final DateTime? requestedTimeIn;
  final DateTime? requestedTimeOut;
  final String reason;
  final String status;
  final DateTime? reviewedAt;
  final String? reviewNotes;
  final DateTime createdAt;
}

class ManageAttendanceAdjustment extends StatefulWidget {
  const ManageAttendanceAdjustment({super.key});

  @override
  State<ManageAttendanceAdjustment> createState() => _ManageAttendanceAdjustmentState();
}

class _ManageAttendanceAdjustmentState extends State<ManageAttendanceAdjustment> {
  String _statusFilter = 'pending';
  List<_CorrectionRecord> _corrections = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCorrections());
  }

  Future<void> _loadCorrections() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/dtr-corrections',
        queryParameters: {'status': _statusFilter},
      );
      final data = res.data ?? [];
      _corrections = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return _CorrectionRecord(
          id: m['id'] as String,
          employeeId: m['employee_id'] as String,
          employeeName: m['employee_name'] as String? ?? '—',
          attendanceDate: _parseDate(m['attendance_date']),
          requestedTimeIn: _parseDateTime(m['requested_time_in']),
          requestedTimeOut: _parseDateTime(m['requested_time_out']),
          reason: m['reason'] as String? ?? '',
          status: m['status'] as String? ?? 'pending',
          reviewedAt: _parseDateTime(m['reviewed_at']),
          reviewNotes: m['review_notes'] as String?,
          createdAt: _parseDateTime(m['created_at']) ?? DateTime.now(),
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load corrections failed: ${e.response?.data ?? e.message}');
      _corrections = [];
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

  String _timeStr(DateTime? t) {
    if (t == null) return '—';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _review(String id, String status, [String? reviewNotes]) async {
    try {
      await ApiClient.instance.patch(
        '/api/dtr-corrections/$id/review',
        data: {'status': status, 'review_notes': reviewNotes?.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Correction $status.')),
        );
        _loadCorrections();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = (e.response?.data as Map?)?['error'] ?? e.message ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  void _showReviewDialog(_CorrectionRecord c, bool approve) {
    final reviewNotesController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve correction' : 'Reject correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Employee: ${c.employeeName}'),
            Text('Date: ${c.attendanceDate.year}-${c.attendanceDate.month.toString().padLeft(2, '0')}-${c.attendanceDate.day.toString().padLeft(2, '0')}'),
            Text('Requested: ${_timeStr(c.requestedTimeIn)} – ${_timeStr(c.requestedTimeOut)}'),
            const SizedBox(height: 12),
            TextField(
              controller: reviewNotesController,
              decoration: const InputDecoration(
                labelText: 'Review notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _review(c.id, approve ? 'approved' : 'rejected', reviewNotesController.text);
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
          'Attendance Adjustment',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Review and approve or reject DTR correction requests.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
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
                      _loadCorrections();
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loading ? null : _loadCorrections,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_corrections.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No correction requests',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: _corrections.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _corrections[i];
                    final isPending = c.status == 'pending';
                    return ListTile(
                      title: Text(
                        c.employeeName,
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      subtitle: Text(
                        '${c.attendanceDate.year}-${c.attendanceDate.month.toString().padLeft(2, '0')}-${c.attendanceDate.day.toString().padLeft(2, '0')} · '
                        '${_timeStr(c.requestedTimeIn)} – ${_timeStr(c.requestedTimeOut)}\n'
                        'Reason: ${c.reason}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isPending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _showReviewDialog(c, true),
                                  child: const Text('Approve'),
                                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF4CAF50)),
                                ),
                                TextButton(
                                  onPressed: () => _showReviewDialog(c, false),
                                  child: const Text('Reject'),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                ),
                              ],
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.status == 'approved'
                                    ? const Color(0xFF4CAF50).withOpacity(0.15)
                                    : Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                c.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: c.status == 'approved' ? const Color(0xFF2E7D32) : Colors.red,
                                ),
                              ),
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
}
