import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../data/time_record.dart';
import '../../landingpage/constants/app_theme.dart';

/// Dialog for employees to submit a DTR correction request (POST /api/dtr-corrections).
Future<bool> showRequestDtrCorrectionDialog({
  required BuildContext context,
  TimeRecord? existingRecord,
  DateTime? initialDate,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RequestDtrCorrectionDialog(
      existingRecord: existingRecord,
      initialDate: initialDate,
    ),
  );
  return result ?? false;
}

class _RequestDtrCorrectionDialog extends StatefulWidget {
  const _RequestDtrCorrectionDialog({
    this.existingRecord,
    this.initialDate,
  });

  final TimeRecord? existingRecord;
  final DateTime? initialDate;

  @override
  State<_RequestDtrCorrectionDialog> createState() =>
      _RequestDtrCorrectionDialogState();
}

class _RequestDtrCorrectionDialogState extends State<_RequestDtrCorrectionDialog> {
  late DateTime _date;
  TimeOfDay? _timeIn;
  TimeOfDay? _breakOut;
  TimeOfDay? _breakIn;
  TimeOfDay? _timeOut;
  final _reason = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRecord;
    final d = r != null
        ? DateTime(r.recordDate.year, r.recordDate.month, r.recordDate.day)
        : (widget.initialDate != null
              ? DateTime(
                  widget.initialDate!.year,
                  widget.initialDate!.month,
                  widget.initialDate!.day,
                )
              : DateTime.now());
    _date = d;
    if (r != null) {
      if (r.timeIn != null) {
        final l = r.timeIn!.toLocal();
        _timeIn = TimeOfDay(hour: l.hour, minute: l.minute);
      }
      if (r.breakOut != null) {
        final l = r.breakOut!.toLocal();
        _breakOut = TimeOfDay(hour: l.hour, minute: l.minute);
      }
      if (r.breakIn != null) {
        final l = r.breakIn!.toLocal();
        _breakIn = TimeOfDay(hour: l.hour, minute: l.minute);
      }
      if (r.timeOut != null) {
        final l = r.timeOut!.toLocal();
        _timeOut = TimeOfDay(hour: l.hour, minute: l.minute);
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime? _combine(DateTime date, TimeOfDay? t) {
    if (t == null) return null;
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason.')),
      );
      return;
    }
    final hasTime =
        _timeIn != null ||
        _breakOut != null ||
        _breakIn != null ||
        _timeOut != null;
    if (!hasTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one corrected time.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await TimeRecordRepo.instance.submitDtrCorrectionRequest(
        attendanceDate: _date,
        requestedTimeIn: _combine(_date, _timeIn),
        requestedTimeOut: _combine(_date, _timeOut),
        requestedBreakIn: _combine(_date, _breakIn),
        requestedBreakOut: _combine(_date, _breakOut),
        reason: reason,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data as Map)['error'] != null
          ? (e.response!.data as Map)['error'].toString()
          : (e.message ?? 'Request failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request attendance correction'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HR will review your request. Approved changes update your official DTR.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today_rounded),
                  onPressed: _submitting ? null : _pickDate,
                  tooltip: 'Change date',
                ),
              ),
              _timeRow('AM In', _timeIn, (t) => setState(() => _timeIn = t)),
              _timeRow('AM Out', _breakOut, (t) => setState(() => _breakOut = t)),
              _timeRow('PM In', _breakIn, (t) => setState(() => _breakIn = t)),
              _timeRow('PM Out', _timeOut, (t) => setState(() => _timeOut = t)),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                enabled: !_submitting,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit request'),
        ),
      ],
    );
  }

  Widget _timeRow(
    String label,
    TimeOfDay? value,
    void Function(TimeOfDay?) onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        value != null
            ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'
            : '— (optional)',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Clear',
              onPressed: _submitting ? null : () => onChanged(null),
            ),
          IconButton(
            icon: const Icon(Icons.schedule_rounded),
            onPressed: _submitting
                ? null
                : () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: value ?? TimeOfDay.now(),
                    );
                    if (t != null) onChanged(t);
                  },
          ),
        ],
      ),
    );
  }
}
