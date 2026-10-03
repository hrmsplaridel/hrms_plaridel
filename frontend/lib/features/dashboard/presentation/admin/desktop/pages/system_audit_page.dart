import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class SystemAuditPage extends StatefulWidget {
  const SystemAuditPage({super.key});

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
  int _total = 0;
  int _loadVersion = 0;
  bool _loading = true;
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

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/system-audit',
        queryParameters: {
          'page': _page,
          'limit': _pageSize,
          if (_actor.text.trim().isNotEmpty) 'actor': _actor.text.trim(),
          if (_action.text.trim().isNotEmpty) 'action': _action.text.trim(),
          if (_entity.text.trim().isNotEmpty)
            'entity_type': _entity.text.trim(),
        },
      );
      if (!mounted || version != _loadVersion) return;
      final data = response.data ?? {};
      setState(() {
        _entries = (data['entries'] as List? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? 0;
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
    _page = 1;
    _load();
  }

  String _when(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int part) => part.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  void _showDetails(Map<String, dynamic> entry) {
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
        title: Text(entry['action']?.toString() ?? 'Audit entry'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: SelectableText(
              'Actor: ${entry['actor_name'] ?? entry['actor_email'] ?? 'System'}\n'
              'Date: ${_when(entry['created_at'])}\n'
              'Entity: ${entry['entity_type'] ?? '-'}\n'
              'ID: ${entry['entity_id'] ?? '-'}\n\n$formatted',
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
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filter(_actor, 'Actor', Icons.person_outline),
              _filter(_action, 'Action', Icons.history),
              _filter(_entity, 'Entity type', Icons.category_outlined),
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
                  _applyFilters();
                },
                child: const Text('Reset'),
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
                        final actor =
                            entry['actor_name'] ??
                            entry['actor_email'] ??
                            'System';
                        final narrow = MediaQuery.sizeOf(context).width < 1100;
                        return ListTile(
                          dense: true,
                          title: Text(entry['action']?.toString() ?? '-'),
                          subtitle: Text(
                            '$actor | ${entry['entity_type'] ?? '-'}'
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
                        _page--;
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page $_page'),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page * _pageSize < _total && !_loading
                    ? () {
                        _page++;
                        _load();
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
