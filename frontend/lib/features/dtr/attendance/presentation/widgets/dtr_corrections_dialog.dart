import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';

Future<void> showDtrCorrections(BuildContext context, {bool review = false}) =>
    openResponsiveRightSidePanel<void>(
      context: context,
      builder: (_) => DtrCorrectionsDialog(review: review),
    );

const _punches = {
  'time_in': 'Shift In',
  'break_out': 'Break Out',
  'break_in': 'Break In',
  'time_out': 'Shift Out',
};
String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _stamp(dynamic value) {
  if (value == null) return '-';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return '-';
  final d = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
  return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class DtrCorrectionsDialog extends StatefulWidget {
  const DtrCorrectionsDialog({super.key, this.review = false});
  final bool review;
  @override
  State<DtrCorrectionsDialog> createState() => _DtrCorrectionsDialogState();
}

class _DtrCorrectionsDialogState extends State<DtrCorrectionsDialog> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  int _offset = 0;
  bool _creating = false;
  Map<String, dynamic>? _selected;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections',
        queryParameters: {'review': widget.review, 'offset': _offset},
      );
      if (mounted) {
        setState(
          () => _rows = (response.data as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = AppTheme.dashPanelOf(context);
    final foreground = AppTheme.dashTextPrimaryOf(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: theme.colorScheme.copyWith(
          surface: background,
          onSurface: foreground,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppTheme.dashMutedSurfaceOf(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
      ),
      child: Builder(
        builder: (context) {
          if (_creating) {
            return _CorrectionForm(
              onClose: (saved) {
                setState(() => _creating = false);
                if (saved) {
                  _offset = 0;
                  _load();
                }
              },
            );
          }
          if (_selected != null) {
            return _CorrectionDetails(
              row: _selected!,
              review: widget.review,
              onClose: () {
                setState(() => _selected = null);
                _load();
              },
            );
          }
          return _buildList(context);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.review
                        ? 'Review DTR Corrections'
                        : 'My DTR Corrections',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (!widget.review)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Request correction'),
                  onPressed: _loading || _error != null
                      ? null
                      : () => setState(() => _creating = true),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    )
                  : _rows.isEmpty
                  ? const Center(child: Text('No correction requests'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final row = _rows[i];
                        return ListTile(
                          title: Text(
                            '${row['attendance_date']} - ${row['employee_name']}',
                          ),
                          subtitle: Text(
                            '${row['status']}\n${row['reason']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => _selected = row),
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _loading || _offset == 0
                      ? null
                      : () {
                          _offset -= 50;
                          _load();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${_offset ~/ 50 + 1}'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _loading || _rows.length < 50
                      ? null
                      : () {
                          _offset += 50;
                          _load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CorrectionForm extends StatefulWidget {
  const _CorrectionForm({required this.onClose});
  final ValueChanged<bool> onClose;
  @override
  State<_CorrectionForm> createState() => _CorrectionFormState();
}

class _CorrectionFormState extends State<_CorrectionForm> {
  DateTime _day = DateTime.now().toUtc().add(const Duration(hours: 8));
  final _reason = TextEditingController();
  final Map<String, TimeOfDay> _times = {};
  final Set<String> _nextDay = {};
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 10 || _times.isEmpty) {
      setState(
        () => _error =
            'Choose at least one punch and enter a reason of at least 10 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'attendance_date': _date(_day),
        'reason': _reason.text.trim(),
      };
      for (final entry in _times.entries) {
        final day = DateTime.utc(
          _day.year,
          _day.month,
          _day.day,
        ).add(Duration(days: _nextDay.contains(entry.key) ? 1 : 0));
        data['requested_${entry.key}'] =
            '${_date(day)}T${entry.value.hour.toString().padLeft(2, '0')}:${entry.value.minute.toString().padLeft(2, '0')}:00+08:00';
      }
      await ApiClient.instance.dio.post('/api/dtr-corrections', data: data);
      if (mounted) widget.onClose(true);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: _CorrectionSurface(
      title: 'Request DTR Correction',
      onBack: _busy ? null : () => widget.onClose(false),
      body: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().toUtc().add(
                            const Duration(hours: 8),
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _day = picked);
                        }
                      },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Attendance date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(_date(_day)),
                ),
              ),
              const SizedBox(height: 24),
              for (final entry in _punches.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: InkWell(
                          onTap: _busy
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime:
                                        _times[entry.key] ??
                                        const TimeOfDay(hour: 8, minute: 0),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => _times[entry.key] = picked);
                                  }
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: entry.value,
                              suffixIcon: const Icon(Icons.schedule),
                            ),
                            child: Text(
                              _times[entry.key]?.format(context) ?? 'Unchanged',
                            ),
                          ),
                        ),
                      ),
                      if (_times.containsKey(entry.key)) ...[
                        Checkbox(
                          value: _nextDay.contains(entry.key),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _nextDay.add(entry.key);
                                  } else {
                                    _nextDay.remove(entry.key);
                                  }
                                }),
                        ),
                        const Text('+1 day'),
                        IconButton(
                          tooltip: 'Clear requested time',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _times.remove(entry.key);
                                  _nextDay.remove(entry.key);
                                }),
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Reason / supporting reference',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => widget.onClose(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Submitting...' : 'Submit request'),
        ),
      ],
    ),
  );
}

class _CorrectionDetails extends StatefulWidget {
  const _CorrectionDetails({
    required this.row,
    required this.review,
    required this.onClose,
  });
  final VoidCallback onClose;
  final Map<String, dynamic> row;
  final bool review;
  @override
  State<_CorrectionDetails> createState() => _CorrectionDetailsState();
}

class _CorrectionDetailsState extends State<_CorrectionDetails> {
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _review(String decision) async {
    if (_notes.text.trim().length < 10) {
      setState(() => _error = 'Enter review notes of at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post(
        '/api/dtr-corrections/${widget.row['id']}/review',
        data: {'decision': decision, 'notes': _notes.text.trim()},
      );
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final original = row['original_record'] as Map?;
    final applied = row['applied_record'] as Map?;
    final canReview = widget.review && row['status'] == 'pending';
    return PopScope(
      canPop: !_busy,
      child: _CorrectionSurface(
        title: '${row['employee_name']} - ${row['attendance_date']}',
        onBack: _busy ? null : widget.onClose,
        body: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Status: ${row['status']}'),
                const SizedBox(height: 12),
                Text('Reason: ${row['reason']}'),
                for (final field in _punches.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${field.value}\nOriginal: ${_stamp(original?[field.key])}\nRequested: ${row['requested_${field.key}'] == null ? 'Unchanged' : _stamp(row['requested_${field.key}'])}'
                      '${applied == null ? '' : '\nApplied: ${_stamp(applied[field.key])}'}',
                    ),
                  ),
                if (row['reviewed_at'] != null)
                  Text(
                    'Reviewed by: ${row['reviewer_name'] ?? '-'}\n${_stamp(row['reviewed_at'])}\n${row['review_notes'] ?? ''}',
                  ),
                if (canReview)
                  TextField(
                    controller: _notes,
                    enabled: !_busy,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Review notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onClose,
            child: const Text('Close'),
          ),
          if (canReview) ...[
            TextButton(
              onPressed: _busy ? null : () => _review('rejected'),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _review('approved'),
              child: Text(_busy ? 'Saving...' : 'Approve correction'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CorrectionSurface extends StatelessWidget {
  const _CorrectionSurface({
    required this.title,
    required this.body,
    required this.actions,
    required this.onBack,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to corrections',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(20), child: body),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}
