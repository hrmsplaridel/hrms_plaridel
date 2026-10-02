import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_corrections_dialog.dart';

class AdminDtrCorrectionsPage extends StatefulWidget {
  const AdminDtrCorrectionsPage({super.key});

  @override
  State<AdminDtrCorrectionsPage> createState() =>
      _AdminDtrCorrectionsPageState();
}

class _AdminDtrCorrectionsPageState extends State<AdminDtrCorrectionsPage> {
  static const _statuses = ['All', 'Pending', 'Approved', 'Rejected'];
  final _search = TextEditingController();
  Timer? _searchTimer;
  List<Map<String, dynamic>> _rows = [];
  String _status = 'All';
  String? _error;
  bool _loading = true;
  int _offset = 0;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections',
        queryParameters: {
          'review': true,
          'offset': _offset,
          if (_status != 'All') 'status': _status.toLowerCase(),
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        },
      );
      if (mounted && version == _loadVersion) {
        setState(
          () => _rows = (response.data as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() => _error = userFacingApiError(e));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  void _setStatus(String status) {
    if (status == _status) return;
    _searchTimer?.cancel();
    setState(() {
      _status = status;
      _offset = 0;
      _rows = [];
    });
    _load();
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _offset = 0;
        _rows = [];
      });
      _load();
    });
  }

  void _reset() {
    _searchTimer?.cancel();
    _search.clear();
    setState(() {
      _status = 'All';
      _offset = 0;
      _rows = [];
    });
    _load();
  }

  Future<void> _openRequest(Map<String, dynamic> row) async {
    final reviewed = await showDtrCorrectionReview(
      context,
      row['id'].toString(),
    );
    if (mounted && reviewed == true) {
      _offset = 0;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final panel = AppTheme.dashPanelOf(context);
      final hairline = AppTheme.dashHairlineOf(context);
      final primary = AppTheme.dashTextPrimaryOf(context);
      final secondary = AppTheme.dashTextSecondaryOf(context);
      final mobile = constraints.maxWidth < 720;
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: hairline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DTR Corrections',
                        style: TextStyle(
                          color: primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Review attendance correction requests and their supporting records.',
                        style: TextStyle(color: secondary, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_rows.length} requests on this page',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: hairline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: mobile ? double.infinity : 300,
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearchChanged,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search employee name or ID',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  for (final status in _statuses)
                    ChoiceChip(
                      label: Text(status),
                      selected: _status == status,
                      onSelected: (_) => _setStatus(status),
                    ),
                  TextButton.icon(
                    onPressed: _status == 'All' && _search.text.isEmpty
                        ? null
                        : _reset,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Request Queue',
              style: TextStyle(
                color: primary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: hairline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  if (!mobile) _headerRow(secondary, hairline),
                  if (_loading)
                    const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    SizedBox(
                      height: 220,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_rows.isEmpty)
                    const SizedBox(
                      height: 220,
                      child: Center(
                        child: Text(
                          'No correction requests match these filters.',
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 590),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: hairline),
                        itemBuilder: (context, index) => mobile
                            ? _mobileRow(_rows[index], primary, secondary)
                            : _desktopRow(_rows[index], primary, secondary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Page ${_offset ~/ 50 + 1}',
                  style: TextStyle(color: secondary),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _loading || _offset == 0
                      ? null
                      : () {
                          setState(() => _offset -= 50);
                          _load();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _loading || _rows.length < 50
                      ? null
                      : () {
                          setState(() => _offset += 50);
                          _load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _headerRow(Color color, Color border) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: border)),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            'Employee',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Attendance Date',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            'Reason',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Status',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 24),
      ],
    ),
  );

  Widget _desktopRow(
    Map<String, dynamic> row,
    Color primary,
    Color secondary,
  ) => InkWell(
    onTap: () => _openRequest(row),
    child: SizedBox(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                row['employee_name']?.toString() ?? '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                row['attendance_date']?.toString() ?? '-',
                style: TextStyle(color: secondary),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                row['reason']?.toString() ?? '-',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: _statusLabel(context, row['status']?.toString() ?? ''),
            ),
            Icon(Icons.chevron_right, size: 20, color: secondary),
          ],
        ),
      ),
    ),
  );

  Widget _mobileRow(Map<String, dynamic> row, Color primary, Color secondary) =>
      Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          onTap: () => _openRequest(row),
          title: Text(
            row['employee_name']?.toString() ?? '-',
            style: TextStyle(color: primary, fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                row['attendance_date']?.toString() ?? '-',
                style: TextStyle(color: secondary),
              ),
              const SizedBox(height: 4),
              Text(
                row['reason']?.toString() ?? '-',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary),
              ),
              const SizedBox(height: 8),
              _statusLabel(context, row['status']?.toString() ?? ''),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      );

  Widget _statusLabel(BuildContext context, String status) {
    final color = switch (status) {
      'pending' => const Color(0xFFD97706),
      'approved' => const Color(0xFF15803D),
      'rejected' => const Color(0xFFDC2626),
      _ => AppTheme.dashTextSecondaryOf(context),
    };
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status.isEmpty
              ? '-'
              : '${status[0].toUpperCase()}${status.substring(1)}',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
