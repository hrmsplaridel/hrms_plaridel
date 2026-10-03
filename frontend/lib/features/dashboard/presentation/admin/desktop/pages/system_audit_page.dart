import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'system_audit_description.dart';

class SystemAuditPage extends StatefulWidget {
  const SystemAuditPage({super.key, this.load, this.pickDateRange});

  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? load;
  final Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)?
  pickDateRange;

  @override
  State<SystemAuditPage> createState() => _SystemAuditPageState();
}

class _SystemAuditPageState extends State<SystemAuditPage> {
  static const _pageSize = 50;
  final _actor = TextEditingController();
  final _action = TextEditingController();
  final _entity = TextEditingController();
  List<Map<String, dynamic>> _entries = [];
  int _page = 1;
  final List<String?> _pageCursors = [];
  String? _nextCursor;
  Map<String, dynamic>? _appliedQuery;
  int _total = 0;
  int _loadVersion = 0;
  bool _loading = true;
  bool _hideViews = true;
  DateTimeRange? _dateRange;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actor.dispose();
    _action.dispose();
    _entity.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1, String? cursor}) async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filters = cursor != null && _appliedQuery != null
          ? _appliedQuery!
          : <String, dynamic>{
              'pagination': 'cursor',
              'limit': _pageSize,
              if (_hideViews) 'hide_views': '1',
              if (_dateRange != null) ...{
                'date_from': DateTime(
                  _dateRange!.start.year,
                  _dateRange!.start.month,
                  _dateRange!.start.day,
                ).toUtc().toIso8601String(),
                'date_before': DateTime(
                  _dateRange!.end.year,
                  _dateRange!.end.month,
                  _dateRange!.end.day + 1,
                ).toUtc().toIso8601String(),
              },
              if (_actor.text.trim().isNotEmpty) 'actor': _actor.text.trim(),
              if (_action.text.trim().isNotEmpty) 'action': _action.text.trim(),
              if (_entity.text.trim().isNotEmpty)
                'entity_type': _entity.text.trim(),
            };
      final query = {
        ...filters,
        'page': page,
        if (cursor != null) 'cursor': cursor,
      };
      final data = widget.load != null
          ? await widget.load!(query)
          : (await ApiClient.instance.get<Map<String, dynamic>>(
                  '/api/system-audit',
                  queryParameters: query,
                )).data ??
                {};
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _entries = (data['entries'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _appliedQuery = Map.of(filters);
        _page = page;
        _nextCursor = data['next_cursor'] as String?;
        if (cursor == null) _pageCursors.clear();
        final currentCursor = cursor ?? data['first_cursor'] as String?;
        if (_pageCursors.length < page) {
          _pageCursors.add(currentCursor);
        } else {
          _pageCursors[page - 1] = currentCursor;
        }
      });
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilters() {
    _load();
  }

  Future<void> _selectDates() async {
    final range = widget.pickDateRange != null
        ? await widget.pickDateRange!(context, _dateRange)
        : await showDateRangePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            initialDateRange: _dateRange,
            helpText: 'Select audit log dates',
            saveText: 'Apply',
          );
    if (!mounted || range == null) return;
    setState(() => _dateRange = range);
    _applyFilters();
  }

  String _dateLabel() {
    final range = _dateRange;
    if (range == null) return 'Select dates';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String day(DateTime date) => '${months[date.month - 1]} ${date.day}';
    final startYear = range.start.year == range.end.year
        ? ''
        : ', ${range.start.year}';
    return '${day(range.start)}$startYear – ${day(range.end)}, ${range.end.year}';
  }

  String _when(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int part) => part.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  void _showDetails(Map<String, dynamic> entry) {
    final description = describeAuditEntry(entry);
    final details = entry['details'];
    String formatted;
    try {
      formatted = const JsonEncoder.withIndent(
        '  ',
      ).convert(details is String ? jsonDecode(details) : details);
    } catch (_) {
      formatted = details?.toString() ?? 'No details';
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(description.title),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  description.summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                SelectableText(
                  'Who: ${entry['actor_name'] ?? entry['actor_email'] ?? 'System'}\n'
                  'When: ${_when(entry['created_at'])}\n'
                  'Affected: ${description.target ?? auditLabel(entry['entity_type']?.toString())}',
                ),
                if (description.changes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'What changed',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final change in description.changes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: SelectableText(change),
                    ),
                ],
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Technical details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Action code: ${entry['action'] ?? '-'}\n'
                        'Entity type: ${entry['entity_type'] ?? '-'}\n'
                        'Entity ID: ${entry['entity_id'] ?? '-'}\n\n$formatted',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashTextSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Audit Log',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh audit log',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            'See who changed access or records, what changed, and when.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filter(_actor, 'Person who acted', Icons.person_outline),
              _filter(_action, 'Action code (e.g. dtr)', Icons.history),
              _filter(
                _entity,
                'Record type (e.g. user)',
                Icons.category_outlined,
              ),
              OutlinedButton.icon(
                onPressed: _selectDates,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_dateLabel()),
              ),
              FilledButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
              TextButton(
                onPressed: () {
                  _actor.clear();
                  _action.clear();
                  _entity.clear();
                  setState(() {
                    _dateRange = null;
                    _hideViews = true;
                  });
                  _applyFilters();
                },
                child: const Text('Reset'),
              ),
              Tooltip(
                message:
                    'Include records created when an administrator opens or searches this Audit Log. This does not change the page number.',
                child: FilterChip(
                  label: const Text('Include audit log visits'),
                  selected: !_hideViews,
                  onSelected: (show) {
                    setState(() {
                      _hideViews = !show;
                    });
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _entries.isEmpty
                  ? const Center(child: Text('No audit entries found'))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: border),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final description = describeAuditEntry(entry);
                        final actor =
                            entry['actor_name'] ??
                            entry['actor_email'] ??
                            'System';
                        final narrow = MediaQuery.sizeOf(context).width < 1100;
                        return ListTile(
                          dense: true,
                          title: Text(description.title),
                          subtitle: Text(
                            '${description.summary}\n'
                            'By $actor${description.target == null ? '' : '  •  ${description.target}'}'
                            '${narrow ? '\n${_when(entry['created_at'])}' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!narrow) ...[
                                Text(
                                  _when(entry['created_at']),
                                  style: TextStyle(color: muted),
                                ),
                                const SizedBox(width: 8),
                              ],
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                          onTap: () => _showDetails(entry),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$_total entries', style: TextStyle(color: muted)),
              const Spacer(),
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 && !_loading
                    ? () {
                        _load(page: _page - 1, cursor: _pageCursors[_page - 2]);
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page $_page'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _nextCursor != null && !_loading
                    ? () {
                        _load(page: _page + 1, cursor: _nextCursor);
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filter(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return SizedBox(
      width: 200,
      child: TextField(
        controller: controller,
        onSubmitted: (_) => _applyFilters(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
