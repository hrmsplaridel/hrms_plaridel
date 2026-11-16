import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';

class ReturnToServiceDialog extends StatefulWidget {
  const ReturnToServiceDialog({
    super.key,
    required this.employeeId,
    required this.name,
    required this.separationDate,
    this.employmentType,
  });
  final String employeeId;
  final String name;
  final DateTime separationDate;
  final String? employmentType;

  @override
  State<ReturnToServiceDialog> createState() => _ReturnToServiceDialogState();
}

class _ReturnToServiceDialogState extends State<ReturnToServiceDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _today = DateUtils.dateOnly(
    DateTime.now().toUtc().add(const Duration(hours: 8)),
  );
  late DateTime _returnedOn;
  List<Map<String, dynamic>> _departments = [],
      _positions = [],
      _shifts = [],
      _policies = [];
  String? _department, _position, _shift;
  String _policy = '';
  String? _error;
  bool _loading = true, _saving = false, _eligible = false;

  @override
  void initState() {
    super.initState();
    _returnedOn = _today;
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait(
        [
          '/api/departments',
          '/api/positions',
          '/api/shifts',
          '/api/attendance-policies',
        ].map(
          (path) => ApiClient.instance.get<List<dynamic>>(
            path,
            queryParameters: {'status': 'Active'},
          ),
        ),
      );
      List<Map<String, dynamic>> rows(int index) => (results[index].data ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['is_active'] != false)
          .toList();
      if (!mounted) return;
      setState(() {
        _departments = rows(0);
        _positions = rows(1);
        _shifts = rows(2);
        _policies = rows(3);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load assignment choices. Please retry.';
          _loading = false;
        });
      }
    }
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post(
        '/api/employees/${widget.employeeId}/return-to-service',
        data: {
          'returned_on': _date(_returnedOn),
          'reason': _reason.text.trim(),
          'leave_credit_eligible': _eligible,
          'assignment': {
            'department_id': _department,
            'position_id': _position,
            'shift_id': _shift,
          },
          'attendance_policy_id': _policy.isEmpty ? null : _policy,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.response?.data is Map
              ? error.response!.data['error']?.toString()
              : null;
          _error ??=
              'Could not return employee to service. Check the connection and retry.';
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not return employee to service.';
          _saving = false;
        });
      }
    }
  }

  Widget _choice(
    String key,
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DropdownButtonFormField<String>(
        key: Key(key),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: rows
            .map(
              (row) => DropdownMenuItem(
                value: row['id'].toString(),
                child: Text(
                  row['name'].toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _saving ? null : onChanged,
        validator: (value) => value == null ? 'Select $label' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noCredits = [
      'job_order',
      'contract_of_service',
    ].contains(widget.employmentType);
    final positions = _positions
        .where((row) => row['department_id']?.toString() == _department)
        .toList();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Return to service'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name),
                const SizedBox(height: 12),
                const Text(
                  'Login will be enabled. Previous employment and assignment history and existing leave balances will remain.',
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (_departments.isEmpty)
                    TextButton(
                      onPressed: _load,
                      child: const Text('Retry loading choices'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final first = DateUtils.dateOnly(
                              widget.separationDate,
                            ).add(const Duration(days: 1));
                            if (first.isAfter(_today)) return;
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _returnedOn,
                              firstDate: first,
                              lastDate: _today,
                            );
                            if (date != null && mounted) {
                              setState(() => _returnedOn = date);
                            }
                          },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Return date: ${_date(_returnedOn)}'),
                  ),
                  _choice(
                    'return_department',
                    'Department',
                    _department,
                    _departments,
                    (value) => setState(() {
                      _department = value;
                      _position = null;
                    }),
                  ),
                  KeyedSubtree(
                    key: ValueKey(_department),
                    child: _choice(
                      'return_position',
                      'Position',
                      _position,
                      positions,
                      (value) => setState(() => _position = value),
                    ),
                  ),
                  _choice(
                    'return_shift',
                    'Shift',
                    _shift,
                    _shifts,
                    (value) => setState(() => _shift = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _policy,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Attendance policy',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text(
                          'Use normal policy routing',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._policies.map(
                        (row) => DropdownMenuItem(
                          value: row['id'].toString(),
                          child: Text(
                            row['name'].toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _policy = value ?? ''),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('return_reason'),
                    controller: _reason,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Reason is required'
                        : value!.trim().length < 5
                        ? 'Enter at least 5 characters'
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Resume leave-credit accrual'),
                    subtitle: Text(
                      noCredits
                          ? 'Not available for JO/COS employment.'
                          : 'Credits follow the applicable rules and service dates. Time away does not earn credits.',
                    ),
                    value: _eligible,
                    onChanged: _saving || noCredits
                        ? null
                        : (value) => setState(() => _eligible = value ?? false),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Confirm return'),
          ),
        ],
      ),
    );
  }
}
