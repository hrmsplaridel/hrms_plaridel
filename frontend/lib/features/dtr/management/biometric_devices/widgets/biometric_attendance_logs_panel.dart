import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/data/biometric_attendance_log_repository.dart';
import 'package:hrms_plaridel/features/dtr/management/biometric_devices/models/biometric_attendance_log.dart';

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
