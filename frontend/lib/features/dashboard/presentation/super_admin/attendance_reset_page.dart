import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class AttendanceResetPage extends StatefulWidget {
  const AttendanceResetPage({super.key});

  @override
  State<AttendanceResetPage> createState() => _AttendanceResetPageState();
}

class _AttendanceResetPageState extends State<AttendanceResetPage> {
  final _search = TextEditingController();
  final _date = TextEditingController();
  final _reason = TextEditingController();
  final _confirmation = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic>? _employee, _preview;
  String? _error, _success;
  String _today = '', _timeZone = 'Asia/Manila';
  bool _loading = false, _busy = false;
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _date.addListener(_invalidate);
    _reason.addListener(_update);
    _confirmation.addListener(_update);
    _loadEmployees();
  }

  @override
  void dispose() {
    _search.dispose();
    _date.dispose();
    _reason.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  void _invalidate() {
    _preview = null;
    _success = null;
    _confirmation.clear();
    _update();
  }

  Future<void> _loadEmployees() async {
    final request = ++_searchRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/attendance-reset/employees',
        queryParameters: {'search': _search.text.trim()},
      );
      if (!mounted || request != _searchRequest) return;
      final data = response.data!;
      setState(() {
        _employees = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _today = data['official_date'] as String;
        _timeZone = data['time_zone'] as String? ?? 'Asia/Manila';
        if (_date.text.isEmpty) _date.text = _today;
      });
    } catch (error) {
      if (mounted && request == _searchRequest) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic> get _target => {
    'employee_id': _employee!['id'],
    'attendance_date': _date.text.trim(),
  };

  bool get _validDate {
    final text = _date.text.trim();
    final parsed = DateTime.tryParse(text);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
        parsed != null &&
        parsed.toIso8601String().startsWith(text) &&
        _today.isNotEmpty &&
        text.compareTo(_today) <= 0;
  }

  Future<void> _chooseDate() async {
    if (_today.isEmpty) return;
    final last = DateTime.parse(_today);
    final current = DateTime.tryParse(_date.text);
    final selected = await showDatePicker(
      context: context,
      initialDate:
          current != null && !current.isAfter(last) && current.year >= 1900
          ? current
          : last,
      firstDate: DateTime(1900),
      lastDate: last,
    );
    if (mounted && selected != null) {
      _date.text = selected.toIso8601String().split('T').first;
    }
  }

  Future<void> _loadPreview() async {
    if (_employee == null || !_validDate || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _preview = null;
    });
    _confirmation.clear();
    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/attendance-reset/preview',
        data: _target,
      );
      if (mounted) setState(() => _preview = response.data);
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canApply =>
      !_busy &&
      _preview?['can_reset'] == true &&
      _reason.text.trim().length >= 3 &&
      _reason.text.trim().length <= 1000 &&
      _confirmation.text == 'RESET';

  Future<void> _apply() async {
    if (!_canApply) return;
    final payload = {
      ..._target,
      'preview_token': _preview!['preview_token'],
      'reason': _reason.text.trim(),
      'confirmation': _confirmation.text,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/attendance-reset/apply',
        data: payload,
      );
      if (!mounted) return;
      final months = response.data?['reconciliation_months'] as List? ?? [];
      setState(() {
        _preview = null;
        _success =
            'Attendance reset completed. New biometric punches can now be processed.'
            '${months.isNotEmpty ? ' ${months.length} month(s) queued for reconciliation.' : ''}';
      });
      _reason.clear();
      _confirmation.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_success!)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _error =
            '${userFacingApiError(error)} Preview again to check the current records.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _panel({required String title, required Widget child}) => SizedBox(
    width: double.infinity,
    child: Material(
      color: AppTheme.dashPanelOf(context),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ),
  );

  Widget _message(String message, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );

  Widget _previewPanel() {
    final preview = _preview!;
    final punches = preview['punches'] as List? ?? [];
    final months = preview['processed_months'] as List? ?? [];
    return _panel(
      title: '2. Review affected attendance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${preview['employee']['full_name']} · ${preview['attendance_date']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            '${punches.length} raw punch(es) · ${preview['summary'] == null ? 0 : 1} processed DTR · ${preview['deletion_blocks']} deletion block(s)',
          ),
          if (preview['summary'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Processed DTR\n'
                'IN: ${preview['summary']['clock_in_local'] ?? '—'}\n'
                'OUT: ${preview['summary']['clock_out_local'] ?? '—'}\n'
                'Hours: ${preview['summary']['total_hours'] ?? '—'} · Status: ${preview['summary']['status'] ?? '—'}',
              ),
            ),
          if (punches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Raw punch times ($_timeZone)'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: punches.length,
                itemBuilder: (_, index) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fingerprint),
                  title: Text(
                    '${punches[index]['logged_at_local'] ?? punches[index]['logged_at']}',
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Assignments, shifts, leave balances, approved documents and device sync cursors are kept. The physical clock is unchanged. Removed punches stay excluded if the clock or an imported file sends them again.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Missing scheduled attendance may count as absence until fresh punches or a correction are recorded. Past months are queued for reconciliation; this action does not directly change leave credits.',
          ),
          if (months.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'This month already has recorded leave-credit deductions. Review month-end reconciliation after correcting attendance.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (preview['blocked_reason'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _message('${preview['blocked_reason']}', error: true),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance reset',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Super Admin only. Remove confirmed test or erroneous attendance for one employee and date. Removed records and the reason are preserved in the Audit Log.',
                ),
                const SizedBox(height: 20),
                if (_error != null) _message(_error!, error: true),
                if (_success != null) _message(_success!),
                _panel(
                  title: '1. Select employee and date',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _search,
                        enabled: !_busy,
                        maxLength: 100,
                        key: const ValueKey('attendance-reset-search'),
                        onSubmitted: (_) => _loadEmployees(),
                        decoration: InputDecoration(
                          hintText: 'Search employee name or number',
                          counterText: '',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Search employees',
                            onPressed: _busy || _loading
                                ? null
                                : _loadEmployees,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (!_loading) ...[
                        const SizedBox(height: 8),
                        if (_employees.isEmpty)
                          const Text(
                            'No employees found. Try another name or employee number.',
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 230),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _employees.length,
                            itemBuilder: (_, index) {
                              final employee = _employees[index];
                              return ListTile(
                                selected: _employee?['id'] == employee['id'],
                                leading: const Icon(Icons.person_outline),
                                title: Text('${employee['full_name']}'),
                                subtitle: employee['employee_number'] == null
                                    ? null
                                    : Text(
                                        'Employee ${employee['employee_number']}',
                                      ),
                                trailing: _employee?['id'] == employee['id']
                                    ? const Icon(Icons.check_circle_outline)
                                    : null,
                                onTap: _busy
                                    ? null
                                    : () {
                                        setState(() => _employee = employee);
                                        _invalidate();
                                      },
                              );
                            },
                          ),
                        ),
                      ],
                      if (_employee != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Selected: ${_employee!['full_name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(height: 20),
                      const Text('Attendance date'),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('attendance-reset-date'),
                        controller: _date,
                        enabled: !_busy,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          helperText:
                              'The shift start date, including overnight shifts.',
                          suffixIcon: IconButton(
                            tooltip: 'Choose attendance date',
                            onPressed: _busy ? null : _chooseDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const ValueKey('attendance-reset-preview'),
                        onPressed: _busy || _employee == null || !_validDate
                            ? null
                            : _loadPreview,
                        icon: const Icon(Icons.preview_outlined),
                        label: const Text('Preview attendance'),
                      ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 20),
                  _previewPanel(),
                  if (_preview!['can_reset'] == true) ...[
                    const SizedBox(height: 20),
                    _panel(
                      title: '3. Confirm reset',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reason for reset'),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('attendance-reset-reason'),
                            controller: _reason,
                            enabled: !_busy,
                            maxLength: 1000,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText:
                                  'Explain which test or erroneous attendance is being removed',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Type RESET to confirm'),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey(
                              'attendance-reset-confirmation',
                            ),
                            controller: _confirmation,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              hintText: 'RESET',
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('attendance-reset-apply'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              minimumSize: const Size(0, 48),
                            ),
                            onPressed: _canApply ? _apply : null,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Reset attendance'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
