import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key, this.load});

  final Future<Map<String, dynamic>> Function(int hours)? load;

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  Timer? _timer;
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  int _hours = 24;
  int? _displayedHours;

  String _rangeLabel(int hours) => hours == 168
      ? '7 days'
      : hours == 1
      ? '1 hour'
      : '24 hours';

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final requestedHours = _hours;
    setState(() => _loading = true);
    try {
      final data = widget.load != null
          ? await widget.load!(requestedHours)
          : (await ApiClient.instance.get<Map<String, dynamic>>(
              '/api/system-health',
              queryParameters: {'hours': requestedHours},
            )).data!;
      if (!mounted) return;
      setState(() {
        _data = data;
        _displayedHours = requestedHours;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = _data != null && requestedHours != _displayedHours
            ? 'Could not load ${_rangeLabel(requestedHours)}. Still showing ${_rangeLabel(_displayedHours!)}. Displayed readings may be outdated. Retry using Refresh or choose another range.'
            : 'Unable to refresh system health. Check your connection and account access.${_data != null ? ' Displayed readings may be outdated.' : ''}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _bytes(dynamic value) {
    if (value is! num) return 'Unavailable';
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var amount = value.toDouble();
    var unit = 0;
    while (amount >= 1024 && unit < units.length - 1) {
      amount /= 1024;
      unit++;
    }
    return '${amount.toStringAsFixed(1)} ${units[unit]}';
  }

  String _time(dynamic value) {
    if (value is! num) return 'No readings yet';
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(date.month)}/${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.dashCanvasOf(context),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _metric(
    String title,
    IconData icon,
    String value,
    String detail, {
    num? usage,
    Color? color,
  }) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
          ),
          if (usage != null) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (usage / 100).clamp(0.0, 1.0),
              color: accent,
              minHeight: 5,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chart(List<dynamic> rows, num end, num bucketMs) {
    if (rows.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Text('History will appear as readings are collected.'),
        ),
      );
    }
    final displayedHours = _displayedHours!;
    final start = end - displayedHours * 3600000;
    final colors = [Colors.orange, Colors.blue, Colors.teal];
    final keys = ['cpuPercent', 'memoryPercent', 'diskPercent'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              Text(
                ['● CPU', '● Memory', '● Disk'][i],
                style: TextStyle(color: colors[i]),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 230,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: displayedHours.toDouble(),
              minY: 0,
              maxY: 100,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 25,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    interval: 25,
                    getTitlesWidget: (value, _) => Text(
                      '${value.toInt()}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map(
                        (spot) => LineTooltipItem(
                          '${['CPU', 'Memory', 'Disk'][spot.barIndex]} ${spot.y.toStringAsFixed(1)}%\n${_time(start + spot.x * 3600000)}',
                          TextStyle(color: colors[spot.barIndex], fontSize: 12),
                        ),
                      )
                      .toList(),
                ),
              ),
              lineBarsData: [
                for (var i = 0; i < 3; i++)
                  LineChartBarData(
                    color: colors[i],
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(show: rows.length == 1),
                    spots: [
                      for (var j = 0; j < rows.length; j++) ...[
                        if (j > 0 &&
                            (rows[j]['timestamp'] as num) -
                                    (rows[j - 1]['timestamp'] as num) >
                                bucketMs * 1.5)
                          FlSpot.nullSpot,
                        if (rows[j][keys[i]] is num)
                          FlSpot(
                            ((rows[j]['timestamp'] as num) - start).toDouble() /
                                3600000,
                            (rows[j][keys[i]] as num).toDouble(),
                          )
                        else
                          FlSpot.nullSpot,
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(_time(start)), Text(_time(end))],
        ),
        const SizedBox(height: 8),
        Text(
          'Average usage per interval. Gaps indicate missing readings. Times are local.',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _data?['current'] as Map?;
    final cpu = current?['cpuPercent'] as num?;
    final memory = current?['memory'] as Map?;
    final disk = current?['disk'] as Map?;
    final database = current?['database'] as Map?;
    final warnings = current?['warnings'] as List? ?? [];
    final stale = _data?['stale'] == true;
    final storageFailed = _data?['storageHealthy'] == false;
    final status = _error != null
        ? 'Status unavailable'
        : current == null
        ? 'Waiting for readings'
        : stale
        ? 'Readings are stale'
        : warnings.isNotEmpty || storageFailed
        ? 'Needs attention'
        : 'Healthy';
    final statusColor = status == 'Healthy' ? Colors.green : Colors.orange;
    String usage(dynamic value) =>
        value is num ? '${value.toStringAsFixed(1)}%' : 'Unavailable';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'System Health',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh system health',
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const Text(
            'Server resource usage and service availability. Readings are recorded every minute and retained for seven days.',
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_data != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(
                    Icons.monitor_heart_outlined,
                    size: 18,
                    color: statusColor,
                  ),
                  label: Text(status),
                ),
                Text('Last reading: ${_time(current?['timestamp'])}'),
                Text('${_data!['sampleCount']} readings in displayed range'),
              ],
            ),
            if (storageFailed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'History could not be saved to disk. Current readings are available, but may be lost on restart.',
                ),
              ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                final cards = [
                  if (_data?['backup'] is Map)
                    _metric(
                      'Backups',
                      Icons.backup_outlined,
                      (_data!['backup']['health'] ?? 'unavailable')
                          .toString()
                          .replaceAll('_', ' '),
                      _data!['backup']['lastSuccessAt'] == null
                          ? 'No successful backup. Open System Administration > Backups.'
                          : 'Last success: ${DateTime.tryParse(_data!['backup']['lastSuccessAt'].toString())?.toLocal().toString().split('.').first ?? 'Unavailable'}',
                      color: _data!['backup']['health'] == 'current'
                          ? Colors.green
                          : Colors.orange,
                    ),
                  _metric(
                    'CPU usage',
                    Icons.memory,
                    usage(cpu),
                    'Server-wide utilization',
                    usage: cpu,
                  ),
                  _metric(
                    'Memory usage',
                    Icons.storage_outlined,
                    usage(memory?['percent']),
                    '${_bytes(memory?['usedBytes'])} / ${_bytes(memory?['totalBytes'])}',
                    usage: memory?['percent'] as num?,
                    color: Colors.blue,
                  ),
                  _metric(
                    'Disk usage',
                    Icons.dns_outlined,
                    usage(disk?['percent']),
                    '${_bytes(disk?['usedBytes'])} / ${_bytes(disk?['totalBytes'])}\n${_bytes(disk?['availableBytes'])} available',
                    usage: disk?['percent'] as num?,
                    color: Colors.teal,
                  ),
                  _metric(
                    'Backend',
                    Icons.cloud_outlined,
                    _error != null ? 'Unverified' : 'Online',
                    'API process uptime: ${current?['uptimeSeconds'] is num ? '${((current!['uptimeSeconds'] as num) / 60).floor()} minutes' : 'Unavailable'}',
                    color: _error != null ? Colors.orange : Colors.green,
                  ),
                  _metric(
                    'Database',
                    Icons.account_tree_outlined,
                    database == null
                        ? 'Unavailable'
                        : database['online'] == true
                        ? 'Connected'
                        : 'Connection failed',
                    database?['latencyMs'] is num
                        ? '${database!['latencyMs']} ms response time'
                        : 'No successful response recorded',
                    color: database?['online'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                ];
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (count - 1) * 16) / count,
                        child: card,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Resource history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1 hour')),
                        ButtonSegment(value: 24, label: Text('24 hours')),
                        ButtonSegment(value: 168, label: Text('7 days')),
                      ],
                      selected: {_hours},
                      onSelectionChanged: _loading
                          ? null
                          : (values) {
                              setState(() {
                                _hours = values.first;
                              });
                              _refresh();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_data != null) ...[
                  Text('Showing ${_rangeLabel(_displayedHours!)}'),
                  if (_loading && _hours != _displayedHours)
                    Text(
                      'Loading ${_rangeLabel(_hours)}… Previous readings remain visible.',
                    ),
                  const SizedBox(height: 12),
                  _chart(
                    _data!['history'] as List? ?? [],
                    _data!['generatedAt'] as num,
                    _data!['bucketMs'] as num,
                  ),
                ] else
                  Text(
                    _loading
                        ? 'Loading readings…'
                        : 'No readings loaded. Refresh or choose another range to retry.',
                  ),
              ],
            ),
          ),
          if (_data != null) ...[
            const SizedBox(height: 24),
            _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent warnings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if ((_data!['recentWarnings'] as List? ?? []).isEmpty)
                    const Text('No recorded warnings in this range.'),
                  for (final entry in _data!['recentWarnings'] as List? ?? [])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${_time(entry['timestamp'])}  •  ${(entry['messages'] as List).join(' · ')}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
