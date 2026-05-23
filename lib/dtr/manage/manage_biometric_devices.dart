import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

/// If [last_sync_at] is older than this, show "Stale" (adjust to match your ingest interval).
const Duration _kBiometricStaleAfter = Duration(hours: 1);

enum _BiometricSyncHealth { neverSynced, ok, stale }

_BiometricSyncHealth _biometricSyncHealth(DateTime? lastSync, DateTime now) {
  if (lastSync == null) return _BiometricSyncHealth.neverSynced;
  if (now.difference(lastSync) <= _kBiometricStaleAfter) {
    return _BiometricSyncHealth.ok;
  }
  return _BiometricSyncHealth.stale;
}

/// Parses `online` from API (bool, null, or loose string/num from JSON).
bool? _parseOnlineBool(dynamic o) {
  if (o == null) return null;
  if (o is bool) return o;
  if (o is num) return o != 0;
  final s = o.toString().trim().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return null;
}

String _formatRelativeSync(DateTime past, DateTime now) {
  final diff = now.difference(past);
  if (diff.isNegative) return 'Just now';
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${past.year}-${past.month.toString().padLeft(2, '0')}-${past.day.toString().padLeft(2, '0')}';
}

Widget _buildRegistrationBadge(bool isActive) {
  final (label, bg, fg) = isActive
      ? ('Active', const Color(0xFFE3F2FD), const Color(0xFF1565C0))
      : ('Inactive', const Color(0xFFEEEEEE), const Color(0xFF616161));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

/// Reachability of ZKTeco TCP port from the API server (not full SDK handshake).
/// [online] null + no stored IP → "No IP". null + has IP → "Unknown" (probe missing or parse issue).
Widget _buildOnlineBadge(bool? online, String? ipAddress) {
  final hasIp = ipAddress != null && ipAddress.trim().isNotEmpty;
  final (label, bg, fg) = !hasIp
      ? ('No IP', const Color(0xFFFFF3E0), const Color(0xFFE65100))
      : online == null
      ? ('Unknown', const Color(0xFFF5F5F5), const Color(0xFF757575))
      : online
      ? ('Online', const Color(0xFFE8F5E9), const Color(0xFF2E7D32))
      : ('Offline', const Color(0xFFFFEBEE), const Color(0xFFC62828));
  final tip = !hasIp
      ? 'No IP address stored — add one to probe connectivity.'
      : online == null
      ? 'Could not determine reachability (refresh or check API). When set: TCP port 4370 from the server.'
      : 'Network reachability from the HRMS server (TCP port 4370).';
  return Tooltip(
    message: tip,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    ),
  );
}

Widget _buildSyncBadge(_BiometricSyncHealth health) {
  final (label, bg, fg) = switch (health) {
    _BiometricSyncHealth.neverSynced => (
      'Never synced',
      const Color(0xFFEEEEEE),
      const Color(0xFF616161),
    ),
    _BiometricSyncHealth.ok => (
      'Sync OK',
      const Color(0xFFE8F5E9),
      const Color(0xFF2E7D32),
    ),
    _BiometricSyncHealth.stale => (
      'Stale',
      const Color(0xFFFFEBEE),
      const Color(0xFFE65100),
    ),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

class _DeviceRecord {
  const _DeviceRecord({
    required this.id,
    required this.name,
    this.deviceId,
    this.location,
    this.ipAddress,
    this.lastSyncAt,
    required this.isActive,
    this.online,
  });
  final String id;
  final String name;
  final String? deviceId;
  final String? location;
  final String? ipAddress;
  final DateTime? lastSyncAt;
  final bool isActive;

  /// `null` = no IP or probe skipped; `true`/`false` = TCP 4370 reachable from server.
  final bool? online;
}

class ManageBiometricDevices extends StatefulWidget {
  const ManageBiometricDevices({super.key});

  @override
  State<ManageBiometricDevices> createState() => _ManageBiometricDevicesState();
}

class _ManageBiometricDevicesState extends State<ManageBiometricDevices> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _locationController = TextEditingController();
  final _ipAddressController = TextEditingController();

  String _statusFilter = 'Active';
  List<_DeviceRecord> _devices = [];
  bool _loading = false;
  _DeviceRecord? _selectedDevice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _deviceIdController.dispose();
    _locationController.dispose();
    _ipAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: {'status': _statusFilter, 'probe_online': '1'},
      );
      final data = res.data ?? [];
      _devices = (data).map((e) {
        final m = e as Map<String, dynamic>;
        final lastSync = m['last_sync_at'];
        final online = m.containsKey('online')
            ? _parseOnlineBool(m['online'])
            : null;
        return _DeviceRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          deviceId: m['device_id'] as String?,
          location: m['location'] as String?,
          ipAddress: m['ip_address'] as String?,
          lastSyncAt: lastSync != null
              ? DateTime.tryParse(lastSync.toString())
              : null,
          isActive: m['is_active'] as bool? ?? true,
          online: online,
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint(
        'Load biometric devices failed: ${e.response?.data ?? e.message}',
      );
      _devices = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _selectDevice(_DeviceRecord d) {
    setState(() {
      _selectedDevice = d;
      _nameController.text = d.name;
      _deviceIdController.text = d.deviceId ?? '';
      _locationController.text = d.location ?? '';
      _ipAddressController.text = d.ipAddress ?? '';
    });
  }

  void _clearForm() {
    setState(() {
      _selectedDevice = null;
      _nameController.clear();
      _deviceIdController.clear();
      _locationController.clear();
      _ipAddressController.clear();
    });
  }

  Future<void> _addDevice() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.post(
        '/api/biometric-devices',
        data: {
          'name': name,
          'device_id': _deviceIdController.text.trim().isEmpty
              ? null
              : _deviceIdController.text.trim(),
          'location': _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          'ip_address': _ipAddressController.text.trim().isEmpty
              ? null
              : _ipAddressController.text.trim(),
          'is_active': true,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Device added.')));
        _clearForm();
        _loadDevices();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to add';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $msg')));
      }
    }
  }

  Future<void> _updateDevice() async {
    final d = _selectedDevice;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a device to update.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name.')),
      );
      return;
    }
    try {
      await ApiClient.instance.put(
        '/api/biometric-devices/${d.id}',
        data: {
          'name': name,
          'device_id': _deviceIdController.text.trim().isEmpty
              ? null
              : _deviceIdController.text.trim(),
          'location': _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          'ip_address': _ipAddressController.text.trim().isEmpty
              ? null
              : _ipAddressController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Device updated.')));
        _clearForm();
        _loadDevices();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to update';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $msg')));
      }
    }
  }

  Future<void> _deactivateDevice() async {
    final d = _selectedDevice;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate device?'),
        content: Text('"${d.name}" will no longer appear in active lists.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.put(
        '/api/biometric-devices/${d.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Device deactivated.')));
        _clearForm();
        _loadDevices();
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to deactivate';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $msg')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;
    final search = _searchController.text.toLowerCase();
    final filtered = _devices
        .where(
          (d) =>
              d.name.toLowerCase().contains(search) ||
              (d.deviceId ?? '').toLowerCase().contains(search) ||
              (d.location ?? '').toLowerCase().contains(search),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Biometric Devices',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Register and manage biometric devices for time logging. (Optional)',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildListPanel(filtered),
                  const SizedBox(height: 24),
                  _buildFormPanel(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 1, child: _buildListPanel(filtered)),
                  const SizedBox(width: 24),
                  Expanded(flex: 1, child: _buildFormPanel()),
                ],
              ),
      ],
    );
  }

  Widget _buildListPanel(List<_DeviceRecord> filtered) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: AppTheme.lightGray.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                items: ['Active', 'Inactive', 'All']
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _statusFilter = v ?? 'Active');
                  _loadDevices();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No devices',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = filtered[i];
                final isSelected = _selectedDevice?.id == d.id;
                final now = DateTime.now();
                final health = _biometricSyncHealth(d.lastSyncAt, now);
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryNavy.withValues(
                    alpha: 0.08,
                  ),
                  leading: Icon(
                    Icons.fingerprint_rounded,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.8),
                  ),
                  title: Text(
                    d.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${d.deviceId ?? '—'} · ${d.location ?? '—'}${d.ipAddress != null && d.ipAddress!.isNotEmpty ? ' · ${d.ipAddress}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildRegistrationBadge(d.isActive),
                          _buildOnlineBadge(d.online, d.ipAddress),
                          _buildSyncBadge(health),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.lastSyncAt != null
                            ? 'Last sync · ${_formatRelativeSync(d.lastSyncAt!, now)}'
                            : 'No sync recorded yet',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () => _selectDevice(d),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedDevice != null) ...[
            Text(
              'Sync status',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final d = _selectedDevice!;
                final now = DateTime.now();
                final health = _biometricSyncHealth(d.lastSyncAt, now);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGray.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildSyncBadge(health),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              d.lastSyncAt != null
                                  ? 'Last sync · ${_formatRelativeSync(d.lastSyncAt!, now)}'
                                  : 'No sync recorded yet — device has not posted logs to the server.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sync OK = last sync within ${_kBiometricStaleAfter.inHours} hour(s). Reload list to refresh.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'Device name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'e.g. Main entrance',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Device ID',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _deviceIdController,
            decoration: InputDecoration(
              hintText: 'Optional – from device',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Location',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _locationController,
            decoration: InputDecoration(
              hintText: 'Optional',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'IP address (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _ipAddressController,
            decoration: InputDecoration(
              hintText: 'e.g. 192.168.1.10',
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _addDevice,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Device'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _selectedDevice != null ? _updateDevice : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
              ),
              FilledButton.icon(
                onPressed: _selectedDevice != null ? _deactivateDevice : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
