import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';

class SystemBackupsPage extends StatefulWidget {
  const SystemBackupsPage({super.key});
  @override
  State<SystemBackupsPage> createState() => _SystemBackupsPageState();
}

class _SystemBackupsPageState extends State<SystemBackupsPage> {
  Timer? _timer;
  Map<String, dynamic>? _data;
  bool _loading = false, _saving = false, _dirty = false, _enabled = false;
  String? _error;
  String _revision = 'initial';
  TimeOfDay _time = const TimeOfDay(hour: 2, minute: 0);
  final _retention = TextEditingController(text: '7');

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retention.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetSettings = false}) async {
    if (_loading || _saving) return;
    setState(() => _loading = true);
    try {
      final data = (await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/system-backups',
      )).data!;
      if (!mounted) return;
      setState(() {
        _data = data;
        if (!_dirty || resetSettings) {
          final settings = data['settings'] as Map;
          _enabled = settings['enabled'] == true;
          final parts = settings['time'].toString().split(':');
          _time = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
          _retention.text = '${settings['retentionDays']}';
          _revision = settings['revision'].toString();
          _dirty = false;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _perform(bool settings) async {
    final days = int.tryParse(_retention.text);
    if (settings && (days == null || days < 1 || days > 90)) {
      setState(() => _error = 'Retention must be between 1 and 90 days.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (settings) {
        final response = await ApiClient.instance.dio.put(
          '/api/system-backups/settings',
          data: {
            'enabled': _enabled,
            'time':
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
            'retentionDays': days,
            'revision': _revision,
          },
        );
        if (!mounted) return;
        setState(() {
          _dirty = false;
          _revision = response.data['revision'].toString();
        });
      } else {
        await ApiClient.instance.dio.post('/api/system-backups');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings
                  ? 'Backup settings saved.'
                  : 'Backup started. You can leave this page while it runs.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        await _load();
      }
    }
  }

  String _date(dynamic value) => value == null
      ? 'None yet'
      : DateTime.tryParse(
              value.toString(),
            )?.toLocal().toString().split('.').first ??
            'Unavailable';
  String _size(dynamic bytes) =>
      bytes is num ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '—';

  @override
  Widget build(BuildContext context) {
    final history = _data?['history'] as List? ?? [];
    final running = history.isNotEmpty && history.first['status'] == 'running';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Backups',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh backups',
                onPressed: _loading || _saving
                    ? null
                    : () {
                        setState(() => _error = null);
                        _load();
                      },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Text(
            'Save PostgreSQL data and local uploaded documents together.',
          ),
          const SizedBox(height: 12),
          if (_loading || _saving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_data != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last successful backup: ${_date(_data!['lastSuccess']?['finishedAt'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${(_data!['health'] ?? 'unavailable').toString().replaceAll('_', ' ')}',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Server folder: ${_data!['storageLocation']}',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These copies are stored on this server. Copy completed backup folders to secure off-server storage. External storage and server secrets are not included. Restore is handled by your server administrator.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving || _loading || running
                          ? null
                          : () => _perform(false),
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(
                        running ? 'Backup in progress' : 'Back up now',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic backups',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Run daily'),
                      value: _enabled,
                      onChanged: _saving || running
                          ? null
                          : (value) => setState(() {
                              _enabled = value;
                              _dirty = true;
                            }),
                    ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving || running
                              ? null
                              : () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: _time,
                                  );
                                  if (mounted && time != null) {
                                    setState(() {
                                      _time = time;
                                      _dirty = true;
                                    });
                                  }
                                },
                          icon: const Icon(Icons.schedule),
                          label: Text('${_time.format(context)} · Asia/Manila'),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _retention,
                            enabled: !_saving && !running,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() => _dirty = true),
                            decoration: const InputDecoration(
                              labelText: 'Keep for days (1–90)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _saving || _loading || running || !_dirty
                              ? null
                              : () => _perform(true),
                          child: const Text('Save settings'),
                        ),
                        if (_dirty)
                          TextButton(
                            onPressed: _saving || _loading
                                ? null
                                : () => _load(resetSettings: true),
                            child: const Text('Discard changes'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Cleanup runs after a successful backup and always keeps the most recent successful copy. The server must be running for scheduled backups.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Backup history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Text(
                'No backups yet. Create your first backup using Back up now.',
              ),
            for (final raw in history)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text(_date(raw['startedAt'])),
                          Text(
                            '${raw['status']}'.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${raw['source']}'),
                          if (raw['status'] == 'succeeded')
                            Text(_size(raw['sizeBytes'])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText('Backup ID: ${raw['id']}'),
                      if (raw['error'] != null)
                        Text(
                          '${raw['error']}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (raw['warning'] != null) Text('${raw['warning']}'),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
