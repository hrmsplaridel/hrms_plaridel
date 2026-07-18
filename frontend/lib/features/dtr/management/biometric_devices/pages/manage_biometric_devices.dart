import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

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

Widget _buildVendorBadge(String vendor) {
  final label = _BiometricVendor.fromValue(vendor).label;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFF3E5F5),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: const Color(0xFF7B1FA2).withValues(alpha: 0.35),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF7B1FA2),
      ),
    ),
  );
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

/// Supported biometric device vendors.
enum _BiometricVendor {
  zkteco('zkteco', 'ZKTeco'),
  hikvision('hikvision', 'Hikvision'),
  anviz('anviz', 'Anviz'),
  other('other', 'Other');

  const _BiometricVendor(this.value, this.label);
  final String value;
  final String label;

  static _BiometricVendor fromValue(String? v) {
    return _BiometricVendor.values.firstWhere(
      (e) => e.value == (v ?? '').toLowerCase(),
      orElse: () => _BiometricVendor.zkteco,
    );
  }
}

class _DeviceRecord {
  const _DeviceRecord({
    required this.id,
    required this.name,
    this.deviceId,
    this.location,
    this.ipAddress,
    this.vendor = 'zkteco',
    this.lastSyncAt,
    required this.isActive,
    this.online,
  });
  final String id;
  final String name;
  final String? deviceId;
  final String? location;
  final String? ipAddress;
  final String vendor;
  final DateTime? lastSyncAt;
  final bool isActive;

  /// `null` = no IP or probe skipped; `true`/`false` = reachable from server.
  final bool? online;
}

class ManageBiometricDevices extends StatefulWidget {
  const ManageBiometricDevices({super.key});

  @override
  State<ManageBiometricDevices> createState() => _ManageBiometricDevicesState();
}

class _ManageBiometricDevicesState extends State<ManageBiometricDevices> {
  static const int _rowsPerPage = 10;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _locationController = TextEditingController();
  final _ipAddressController = TextEditingController();

  _BiometricVendor _selectedVendor = _BiometricVendor.zkteco;
  String _statusFilter = 'Active';
  int _page = 0;
  List<_DeviceRecord> _devices = [];
  bool _loading = false;
  _DeviceRecord? _selectedDevice;
  StateSetter? _drawerSetState;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  BoxDecoration _filterDecoration(BuildContext context) => BoxDecoration(
    color: _isDark(context)
        ? AppTheme.dashMutedSurfaceOf(context)
        : AppTheme.lightGray.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: _isDark(context)
          ? AppTheme.dashHairlineOf(context)
          : Colors.transparent,
    ),
  );

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  void _updateDeviceFormState(VoidCallback update) {
    if (mounted) setState(update);
    final drawerSetState = _drawerSetState;
    if (!mounted || drawerSetState == null) return;
    try {
      drawerSetState(() {});
    } catch (_) {
      _drawerSetState = null;
    }
  }

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
    setState(() {
      _loading = true;
      _page = 0;
    });
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
          vendor: m['vendor'] as String? ?? 'zkteco',
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
    _updateDeviceFormState(() {
      _selectedDevice = d;
      _nameController.text = d.name;
      _deviceIdController.text = d.deviceId ?? '';
      _locationController.text = d.location ?? '';
      _ipAddressController.text = d.ipAddress ?? '';
      _selectedVendor = _BiometricVendor.fromValue(d.vendor);
    });
  }

  void _clearForm() {
    _updateDeviceFormState(() {
      _selectedDevice = null;
      _nameController.clear();
      _deviceIdController.clear();
      _locationController.clear();
      _ipAddressController.clear();
      _selectedVendor = _BiometricVendor.zkteco;
    });
  }

  Future<bool> _addDevice() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name.')),
      );
      return false;
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
          'vendor': _selectedVendor.value,
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
      return true;
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
      return false;
    }
  }

  Future<bool> _updateDevice() async {
    final d = _selectedDevice;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a device to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name.')),
      );
      return false;
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
          'vendor': _selectedVendor.value,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Device updated.')));
        _clearForm();
        _loadDevices();
      }
      return true;
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
      return false;
    }
  }

  Future<bool> _deactivateDevice() async {
    final d = _selectedDevice;
    if (d == null) return false;
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
    if (ok != true || !mounted) return false;
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
      return true;
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
      return false;
    }
  }

  Future<void> _openDeviceDrawer({_DeviceRecord? device}) async {
    _drawerSetState = null;
    if (device == null) {
      _clearForm();
    } else {
      _selectDevice(device);
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.32),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, __) {
          final screenWidth = MediaQuery.of(dialogContext).size.width;
          final drawerWidth = screenWidth < 720 ? screenWidth : 560.0;
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: Material(
                color: AppTheme.dashPanelOf(dialogContext),
                elevation: 18,
                child: StatefulBuilder(
                  builder: (context, drawerSetState) {
                    _drawerSetState = drawerSetState;
                    return _buildDeviceDrawer(dialogContext);
                  },
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
    } finally {
      _drawerSetState = null;
    }
  }

  Widget _buildDeviceDrawer(BuildContext drawerContext) {
    final isEditing = _selectedDevice != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing
                        ? 'Edit Biometric Device'
                        : 'Add Biometric Device',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _buildFormPanel(framed: false, showActions: false),
            ),
          ),
          _buildDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedDevice != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
          if (isEditing)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateDevice();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing ? await _updateDevice() : await _addDevice();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Device'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Biometric Devices',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openDeviceDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Device'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE85D04),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Register and manage biometric devices for time logging. (Optional)',
          style: TextStyle(color: _mutedColor(context), fontSize: 14),
        ),
        const SizedBox(height: 20),
        _buildListPanel(filtered),
      ],
    );
  }

  Widget _buildListPanel(List<_DeviceRecord> filtered) {
    final dark = _isDark(context);
    final total = filtered.length;
    final pageCount = total == 0
        ? 1
        : ((total + _rowsPerPage - 1) ~/ _rowsPerPage);
    final page = _page >= pageCount ? pageCount - 1 : _page;
    final pageStart = page * _rowsPerPage;
    final pageEnd = pageStart + _rowsPerPage > total
        ? total
        : pageStart + _rowsPerPage;
    final paged = total == 0
        ? <_DeviceRecord>[]
        : filtered.sublist(pageStart, pageEnd);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
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
                  onChanged: (_) => setState(() => _page = 0),
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    hintText: 'Search',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    radius: 10,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: _filterDecoration(context),
                child: DropdownButton<String>(
                  value: _statusFilter,
                  dropdownColor: AppTheme.dashPanelOf(context),
                  style: AppTheme.dashFieldTextStyle(context),
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: ['Active', 'Inactive', 'All']
                      .map(
                        (o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            o,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _statusFilter = v ?? 'Active';
                      _page = 0;
                    });
                    _loadDevices();
                  },
                ),
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
                  style: TextStyle(color: _mutedColor(context), fontSize: 14),
                ),
              ),
            )
          else
            Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: paged.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = paged[i];
                    final isSelected = _selectedDevice?.id == d.id;
                    final now = DateTime.now();
                    final health = _biometricSyncHealth(d.lastSyncAt, now);
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08),
                      leading: Icon(
                        Icons.fingerprint_rounded,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.8),
                      ),
                      title: Text(
                        d.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _headingColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${d.deviceId ?? '—'} · ${d.location ?? '—'}${d.ipAddress != null && d.ipAddress!.isNotEmpty ? ' · ${d.ipAddress}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _mutedColor(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildRegistrationBadge(d.isActive),
                              _buildVendorBadge(d.vendor),
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
                              color: _mutedColor(context),
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      onTap: () => _openDeviceDrawer(device: d),
                    );
                  },
                ),
                _buildPaginationFooter(
                  total: total,
                  page: page,
                  pageCount: pageCount,
                  pageStart: pageStart,
                  pageEnd: pageEnd,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter({
    required int total,
    required int page,
    required int pageCount,
    required int pageStart,
    required int pageEnd,
  }) {
    final summary = total == 0
        ? 'No results'
        : 'Showing ${pageStart + 1}-$pageEnd of $total';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: TextStyle(fontSize: 12, color: _mutedColor(context)),
            ),
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: TextStyle(fontSize: 12, color: _mutedColor(context)),
          ),
          if (pageCount > 1) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: page > 0
                  ? () => setState(() => _page = page - 1)
                  : null,
              child: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: page < pageCount - 1
                  ? () => setState(() => _page = page + 1)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
    final dark = _isDark(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedDevice != null) ...[
          Text(
            'Sync status',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
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
                  color: dark
                      ? AppTheme.dashMutedSurfaceOf(context)
                      : AppTheme.lightGray.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dashHairlineOf(context)),
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
                              color: _headingColor(context),
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
                        color: _mutedColor(context),
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
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('e.g. Main entrance'),
        ),
        const SizedBox(height: 16),
        Text(
          'Device ID',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _deviceIdController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Optional – from device'),
        ),
        const SizedBox(height: 16),
        Text(
          'Location',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _locationController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Optional'),
        ),
        const SizedBox(height: 16),
        Text(
          'IP address (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _ipAddressController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('e.g. 192.168.1.10'),
        ),
        const SizedBox(height: 16),
        Text(
          'Brand / Vendor',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
            borderRadius: BorderRadius.circular(8),
            color: _isDark(context)
                ? AppTheme.dashMutedSurfaceOf(context)
                : Colors.white,
          ),
          child: DropdownButton<_BiometricVendor>(
            value: _selectedVendor,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            items: _BiometricVendor.values
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(
                      v.label,
                      style: AppTheme.dashFieldTextStyle(context),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _updateDeviceFormState(() => _selectedVendor = v);
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _selectedVendor == _BiometricVendor.zkteco
              ? 'Uses pyzk over TCP port 4370. Supports live sync and push-to-device.'
              : _selectedVendor == _BiometricVendor.hikvision
              ? 'Uses Hikvision ISAPI over HTTP (port 80). Live sync supported.'
              : _selectedVendor == _BiometricVendor.anviz
              ? 'Uses Anviz protocol over TCP port 5010. Polling sync supported.'
              : 'Non-standard device. Use file-based manual import for attendance logs.',
          style: TextStyle(fontSize: 11, color: _mutedColor(context)),
        ),
        if (showActions) ...[
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _addDevice(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Device'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _selectedDevice != null
                    ? () => _updateDevice()
                    : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
              ),
              FilledButton.icon(
                onPressed: _selectedDevice != null
                    ? () => _deactivateDevice()
                    : null,
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
      ],
    );

    if (!framed) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: content,
    );
  }
}
