import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/data/biometric_attendance_log_repository.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/models/biometric_attendance_log.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';

class BiometricAttendanceLogsPanel extends StatefulWidget {
  const BiometricAttendanceLogsPanel({super.key});

  @override
  State<BiometricAttendanceLogsPanel> createState() =>
      _BiometricAttendanceLogsPanelState();
}

class _BiometricAttendanceLogsPanelState
    extends State<BiometricAttendanceLogsPanel> {
  static const _repository = BiometricAttendanceLogRepository();
  static const _pageSize = 25;

  final _searchController = TextEditingController();
  List<BiometricAttendanceLog> _rows = const [];
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetPage = false}) async {
    final generation = ++_loadGeneration;
    if (resetPage) _page = 0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.list(
        limit: _pageSize,
        offset: _page * _pageSize,
        search: _searchController.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _rows = result.rows;
        _total = result.total;
      });
    } on DioException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      final payload = error.response?.data;
      setState(() {
        _error = payload is Map && payload['error'] != null
            ? payload['error'].toString()
            : 'Unable to load biometric attendance logs.';
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
        if (_dateTo != null && _dateTo!.isBefore(picked)) _dateTo = picked;
      } else {
        _dateTo = picked;
        if (_dateFrom != null && _dateFrom!.isAfter(picked)) _dateFrom = picked;
      }
    });
    await _load(resetPage: true);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _load(resetPage: true);
  }

  Future<void> _downloadAttendance() async {
    if (_exporting) return;
    final selection = await showDialog<_AttendanceExportSelection>(
      context: context,
      builder: (_) => const _AttendanceExportDialog(),
    );
    if (selection == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final result = await _repository.export(
        dateFrom: selection.dateFrom,
        dateTo: selection.dateTo,
        format: selection.format,
      );
      if (!mounted) return;
      if (result.rowCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No biometric punches were found for that period.'),
          ),
        );
        return;
      }
      final extension = selection.format == 'dat' ? 'dat' : 'csv';
      final fallbackName = selection.format == 'dat'
          ? 'attlog_${selection.fileRange}.$extension'
          : 'biometric_attendance_${selection.fileRange}.$extension';
      await shareOrDownloadFile(
        result.bytes,
        result.filename ?? fallbackName,
        selection.format == 'dat' ? 'text/plain' : 'text/csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.rowCount} biometric punch${result.rowCount == 1 ? '' : 'es'} downloaded.',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final message = error.response?.statusCode == 413
          ? 'The selected period has too many punches. Choose a shorter range.'
          : 'Unable to download biometric attendance.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _formatDate(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

  String _formatTime(DateTime value, {bool includeSeconds = false}) {
    if (includeSeconds) {
      final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
      final minute = value.minute.toString().padLeft(2, '0');
      final second = value.second.toString().padLeft(2, '0');
      final period = value.hour < 12 ? 'AM' : 'PM';
      return '$hour:$minute:$second $period';
    }
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(value));
    return time;
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = _total == 0 ? 1 : (_total / _pageSize).ceil();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Raw punches synchronized into HRMS. Processed attendance remains available under Time Logs.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 270,
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _load(resetPage: true),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    hintText: 'Search employee or biometric ID',
                    prefixIcon: const Icon(Icons.search_rounded),
                    radius: 10,
                  ),
                ),
              ),
              _DateFilterButton(
                label: _dateFrom == null ? 'From' : _formatDate(_dateFrom!),
                onPressed: () => _pickDate(from: true),
              ),
              _DateFilterButton(
                label: _dateTo == null ? 'To' : _formatDate(_dateTo!),
                onPressed: () => _pickDate(from: false),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _load(resetPage: true),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Apply'),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _clearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Reset'),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _downloadAttendance,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download Attendance'),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh attendance logs',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withValues(alpha: 0.08),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_loading && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No biometric attendance logs found.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              ),
            )
          else ...[
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Employee')),
                  DataColumn(label: Text('Biometric ID')),
                  DataColumn(label: Text('Punch date')),
                  DataColumn(label: Text('Punch time')),
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Imported')),
                ],
                rows: _rows.map(_buildRow).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${_page * _pageSize + 1}-${_page * _pageSize + _rows.length} of $_total',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ),
                Text('Page ${_page + 1} of $pageCount'),
                if (pageCount > 1) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _page > 0 && !_loading
                        ? () {
                            _page--;
                            _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous page',
                  ),
                  IconButton(
                    onPressed: _page + 1 < pageCount && !_loading
                        ? () {
                            _page++;
                            _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next page',
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  DataRow _buildRow(BiometricAttendanceLog row) {
    final localPunch = row.loggedAt.toLocal();
    final localImported = row.importedAt.toLocal();
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 190,
            child: Text(row.employeeName, overflow: TextOverflow.ellipsis),
          ),
        ),
        DataCell(Text(row.biometricUserId)),
        DataCell(Text(_formatDate(localPunch))),
        DataCell(Text(_formatTime(localPunch, includeSeconds: true))),
        DataCell(
          SizedBox(
            width: 170,
            child: Text(
              row.sourceName?.trim().isNotEmpty == true
                  ? row.sourceName!
                  : 'Device sync',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text('${_formatDate(localImported)}, ${_formatTime(localImported)}'),
        ),
      ],
    );
  }
}

enum _AttendanceExportPeriod { daily, weekly, monthly, custom }

extension on _AttendanceExportPeriod {
  String get label => switch (this) {
    _AttendanceExportPeriod.daily => 'Daily',
    _AttendanceExportPeriod.weekly => 'Weekly',
    _AttendanceExportPeriod.monthly => 'Monthly',
    _AttendanceExportPeriod.custom => 'Custom range',
  };
}

class _AttendanceExportSelection {
  const _AttendanceExportSelection({
    required this.dateFrom,
    required this.dateTo,
    required this.format,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final String format;

  String get fileRange => '${_compact(dateFrom)}_${_compact(dateTo)}';

  static String _compact(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';
}

class _AttendanceExportDialog extends StatefulWidget {
  const _AttendanceExportDialog();

  @override
  State<_AttendanceExportDialog> createState() =>
      _AttendanceExportDialogState();
}

class _AttendanceExportDialogState extends State<_AttendanceExportDialog> {
  _AttendanceExportPeriod _period = _AttendanceExportPeriod.monthly;
  String _format = 'dat';
  DateTime _anchor = DateTime.now();
  late DateTime _customFrom = DateTime(_anchor.year, _anchor.month, 1);
  late DateTime _customTo = _anchor;

  DateTimeRange get _range {
    final date = DateUtils.dateOnly(_anchor);
    return switch (_period) {
      _AttendanceExportPeriod.daily => DateTimeRange(start: date, end: date),
      _AttendanceExportPeriod.weekly => DateTimeRange(
        start: date.subtract(Duration(days: date.weekday - 1)),
        end: date.add(Duration(days: 7 - date.weekday)),
      ),
      _AttendanceExportPeriod.monthly => DateTimeRange(
        start: DateTime(date.year, date.month, 1),
        end: DateTime(date.year, date.month + 1, 0),
      ),
      _AttendanceExportPeriod.custom => DateTimeRange(
        start: DateUtils.dateOnly(_customFrom),
        end: DateUtils.dateOnly(_customTo),
      ),
    };
  }

  Future<void> _pickAnchor() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _anchor = picked);
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _customFrom, end: _customTo),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customFrom = picked.start;
      _customTo = picked.end;
    });
  }

  String _date(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.download_rounded),
          SizedBox(width: 12),
          Text('Download Attendance'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<_AttendanceExportPeriod>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Period'),
              items: _AttendanceExportPeriod.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _period = value);
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _period == _AttendanceExportPeriod.custom
                  ? _pickCustomRange
                  : _pickAnchor,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                _period == _AttendanceExportPeriod.custom
                    ? '${_date(range.start)} - ${_date(range.end)}'
                    : _date(_anchor),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Export range: ${_date(range.start)} - ${_date(range.end)}',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _format,
              decoration: const InputDecoration(labelText: 'File format'),
              items: const [
                DropdownMenuItem(
                  value: 'dat',
                  child: Text('DAT (attlog.dat compatible)'),
                ),
                DropdownMenuItem(
                  value: 'csv',
                  child: Text('CSV (spreadsheet)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _format = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _AttendanceExportSelection(
              dateFrom: range.start,
              dateTo: range.end,
              format: _format,
            ),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
      ],
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined, size: 17),
      label: Text(label),
    );
  }
}
