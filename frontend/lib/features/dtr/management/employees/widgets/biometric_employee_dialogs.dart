part of '../pages/manage_employee.dart';

class _RosterStatusPill extends StatelessWidget {
  const _RosterStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2E7D32) : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BiometricImportDialog extends StatefulWidget {
  const _BiometricImportDialog({required this.onImportSuccess});

  final VoidCallback onImportSuccess;

  @override
  State<_BiometricImportDialog> createState() => _BiometricImportDialogState();
}

class _BiometricImportDialogState extends State<_BiometricImportDialog> {
  bool _loadingDevices = true;
  List<dynamic> _devices = [];
  String? _selectedDeviceId;

  bool _loadingUsers = false;
  List<dynamic> _fetchedUsers = [];

  /// Biometric user IDs already linked in HRMS (from API; not the paged table).
  Set<String> _duplicateBioIds = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final res = await ApiClient.instance.get(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active', 'probe_online': '0'},
      );
      if (mounted) {
        setState(() {
          _devices = res.data ?? [];
          if (_devices.isNotEmpty) {
            _selectedDeviceId = _devices.first['id'];
          }
          _loadingDevices = false;
        });
        if (_selectedDeviceId != null) {
          _fetchUsers();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _fetchUsers() async {
    if (_selectedDeviceId == null) return;
    setState(() {
      _loadingUsers = true;
      _fetchedUsers = [];
      _duplicateBioIds = {};
    });
    try {
      final res = await ApiClient.instance.get(
        '/api/biometric-devices/$_selectedDeviceId/users',
      );
      if (mounted) {
        setState(() {
          _fetchedUsers = res.data ?? [];
          _loadingUsers = false;
        });
        await _refreshDuplicateBioIds();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch users: $e')));
        setState(() => _loadingUsers = false);
      }
    }
  }

  Future<void> _refreshDuplicateBioIds() async {
    final ids = _fetchedUsers
        .map((u) => u['biometric_user_id']?.toString().trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    if (!mounted) return;
    if (ids.isEmpty) {
      setState(() => _duplicateBioIds = {});
      return;
    }
    const chunk = 40;
    final found = <String>{};
    try {
      const repo = BiometricImportRepository();
      for (var i = 0; i < ids.length; i += chunk) {
        final end = i + chunk > ids.length ? ids.length : i + chunk;
        final slice = ids.sublist(i, end);
        final matches = await repo.findEmployeesByBiometricIds(slice);
        found.addAll(matches.map((e) => e.biometricUserId));
      }
    } catch (_) {
      if (mounted) setState(() => _duplicateBioIds = {});
      return;
    }
    if (mounted) setState(() => _duplicateBioIds = found);
  }

  void _openUserImportModal(Map<String, dynamic> user, bool isDuplicate) async {
    if (isDuplicate) return;
    final success = await showDialog<bool>(
      context: context,
      builder: (_) => _SingleUserImportModal(user, _selectedDeviceId!),
    );
    if (success == true) {
      widget.onImportSuccess();
      final bid = user['biometric_user_id']?.toString().trim();
      if (bid != null && bid.isNotEmpty && mounted) {
        setState(() => _duplicateBioIds = {..._duplicateBioIds, bid});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import from Biometric Device',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_loadingDevices)
              const CircularProgressIndicator()
            else if (_devices.isEmpty)
              const Text('No devices found.')
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDeviceId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Select Device',
                        isDense: true,
                      ),
                      items: _devices
                          .map(
                            (d) => DropdownMenuItem<String>(
                              value: d['id'],
                              child: Text(d['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedDeviceId = v;
                        _fetchUsers();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loadingUsers ? null : _fetchUsers,
                    icon: const Icon(Icons.sync),
                    label: const Text('Fetch Users'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (_loadingUsers)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _fetchedUsers.isEmpty
                    ? const Center(child: Text('No users fetched yet.'))
                    : ListView.builder(
                        itemCount: _fetchedUsers.length,
                        itemBuilder: (context, index) {
                          final u = _fetchedUsers[index];
                          final bioId = u['biometric_user_id']?.toString();
                          if (bioId == null) return const SizedBox.shrink();

                          final isDuplicate = _duplicateBioIds.contains(bioId);
                          final name = u['full_name']?.toString() ?? 'Unknown';

                          return ListTile(
                            title: Text(name),
                            subtitle: Text('Bio ID: $bioId'),
                            trailing: isDuplicate
                                ? const Chip(
                                    label: Text(
                                      'Duplicate',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    backgroundColor: Colors.orange,
                                  )
                                : FilledButton.icon(
                                    onPressed: () =>
                                        _openUserImportModal(u, isDuplicate),
                                    icon: const Icon(
                                      Icons.person_add_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Import'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF4CAF50),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleUserImportModal extends StatefulWidget {
  final Map<String, dynamic> user;
  final String deviceId;
  const _SingleUserImportModal(this.user, this.deviceId);

  @override
  State<_SingleUserImportModal> createState() => _SingleUserImportModalState();
}

class _SingleUserImportModalState extends State<_SingleUserImportModal> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();

  String _role = 'employee';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameController.text =
        widget.user['full_name']?.toString() ?? 'Imported User';
    _applyImportDefaultPasswords();
  }

  void _applyImportDefaultPasswords() {
    final pwd = defaultPasswordForRoleKey(_role);
    _passwordController.text = pwd;
    _confirmController.text = pwd;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _importing = true);
    try {
      await ApiClient.instance.post(
        '/api/biometric-devices/${widget.deviceId}/import-user',
        data: {
          'biometric_user_id': widget.user['biometric_user_id'].toString(),
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User imported securely and marked inactive.'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        String errMsg = 'Import failed: $e';
        if (e is DioException) {
          errMsg = (e.response?.data is Map)
              ? e.response?.data['error']?.toString() ?? 'Network Error'
              : e.message ?? 'Unknown error';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import Biometric User',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Biometric ID: ${widget.user['biometric_user_id']}',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Admin Email for User',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Initial Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: ['employee', 'admin']
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _role = v ?? 'employee';
                  _applyImportDefaultPasswords();
                }),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _importing ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                    child: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Import as Inactive'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog: all employees with biometric user ID visibility (paged, search, filters).
class _BiometricRosterDialog extends StatefulWidget {
  const _BiometricRosterDialog();

  @override
  State<_BiometricRosterDialog> createState() => _BiometricRosterDialogState();
}

class _BiometricRosterDialogState extends State<_BiometricRosterDialog> {
  static const int _pageSize = 50;

  bool _isDark(BuildContext context) => AppTheme.dashIsDark(context);

  Color _headingColor(BuildContext context) =>
      AppTheme.dashTextPrimaryOf(context);

  Color _mutedColor(BuildContext context) =>
      AppTheme.dashTextSecondaryOf(context);

  int _pageIndex = 0;
  String _filter = 'all';
  String? _selectedDeviceId;
  List<dynamic> _devices = [];
  bool _loadingDevices = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableHorizontalScrollController = ScrollController();
  Timer? _searchDebounce;
  bool _loading = true;
  String? _error;
  List<_EmployeeProfile> _rows = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tableHorizontalScrollController.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (_total <= 0) return 1;
    return ((_total - 1) ~/ _pageSize) + 1;
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active', 'probe_online': '0'},
      );
      if (!mounted) return;
      setState(() {
        _devices = res.data ?? [];
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _devices = [];
          _loadingDevices = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'status': 'All',
        'role': 'All',
        'sort': 'full_name',
        'order': 'asc',
        'limit': _pageSize,
        'offset': _pageIndex * _pageSize,
      };
      if (_filter != 'all') {
        query['biometric_filter'] = _filter;
      }
      final dev = _selectedDeviceId?.trim();
      if (dev != null && dev.isNotEmpty) {
        query['biometric_device_id'] = dev;
      }
      final sq = _searchController.text.trim();
      if (sq.isNotEmpty) {
        query['q'] = sq;
      }

      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
        options: dev != null && dev.isNotEmpty
            ? Options(receiveTimeout: const Duration(seconds: 120))
            : null,
      );
      if (!mounted) return;
      final data = res.data;
      List<_EmployeeProfile> next = [];
      var total = 0;
      if (data is Map) {
        final list = data['employees'] as List<dynamic>? ?? [];
        total = (data['total'] as num?)?.toInt() ?? 0;
        next = list
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
      setState(() {
        _rows = next;
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _rows = [];
        _total = 0;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _pageIndex = 0;
      _load();
    });
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _pageIndex = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final tableHeadingStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: _headingColor(context),
    );
    final tableCellStyle = TextStyle(
      fontSize: 13,
      color: _headingColor(context),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppTheme.dashPanelOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biometric roster',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _headingColor(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedDeviceId == null ||
                                  _selectedDeviceId!.trim().isEmpty
                              ? 'Biometric user IDs stored in HRMS. Use this list to pick a free ID before enrolling someone on the ZKTeco.'
                              : 'Only employees whose Biometric User ID exists on the selected device. The server reads the device user list and may take a few seconds the first time.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: _mutedColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: _mutedColor(context)),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedDeviceId,
                    dropdownColor: AppTheme.dashPanelOf(context),
                    style: AppTheme.dashFieldTextStyle(context),
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Device',
                      prefixIcon: Icon(
                        Icons.devices_other_outlined,
                        color: _mutedColor(context),
                      ),
                      radius: 12,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    hint: Text(
                      'All devices (HRMS only)',
                      style: TextStyle(color: _mutedColor(context)),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'All devices (HRMS only)',
                          style: AppTheme.dashFieldTextStyle(context),
                        ),
                      ),
                      ..._devices.map((d) {
                        final map = Map<String, dynamic>.from(d as Map);
                        final id = map['id']?.toString() ?? '';
                        final name = map['name']?.toString() ?? id;
                        final loc = map['location']?.toString();
                        final label = (loc != null && loc.isNotEmpty)
                            ? '$name · $loc'
                            : name;
                        return DropdownMenuItem<String?>(
                          value: id,
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.dashFieldTextStyle(context),
                          ),
                        );
                      }),
                    ],
                    onChanged: _loadingDevices
                        ? null
                        : (v) {
                            setState(() {
                              _selectedDeviceId = v;
                              _pageIndex = 0;
                            });
                            _load();
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      'All',
                      style: TextStyle(color: _headingColor(context)),
                    ),
                    selected: _filter == 'all',
                    selectedColor: dark
                        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                        : AppTheme.primaryNavy.withValues(alpha: 0.12),
                    backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('all');
                    },
                  ),
                  ChoiceChip(
                    avatar: _filter == 'set'
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    label: Text(
                      'Has ID',
                      style: TextStyle(color: _headingColor(context)),
                    ),
                    selected: _filter == 'set',
                    selectedColor: dark
                        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                        : AppTheme.primaryNavy.withValues(alpha: 0.12),
                    backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('set');
                    },
                  ),
                  ChoiceChip(
                    label: Text(
                      'Missing ID',
                      style: TextStyle(color: _headingColor(context)),
                    ),
                    selected: _filter == 'missing',
                    selectedColor: dark
                        ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                        : AppTheme.primaryNavy.withValues(alpha: 0.12),
                    backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('missing');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _searchController,
                style: AppTheme.dashFieldTextStyle(context),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  hintText: 'Search name, email, employee no., biometric ID…',
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: _mutedColor(context),
                  ),
                  radius: 12,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red.shade800),
                            ),
                          ),
                        )
                      : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'No employees match.',
                            style: TextStyle(color: _mutedColor(context)),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final tableMinWidth = constraints.hasBoundedWidth
                                ? constraints.maxWidth
                                : 0.0;
                            return Scrollbar(
                              controller: _tableHorizontalScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _tableHorizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: tableMinWidth,
                                  ),
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      columnSpacing: 28,
                                      headingRowHeight: 42,
                                      dataRowMinHeight: 44,
                                      headingRowColor: WidgetStateProperty.all(
                                        AppTheme.dashMutedSurfaceOf(context),
                                      ),
                                      headingTextStyle: tableHeadingStyle,
                                      dataTextStyle: tableCellStyle,
                                      columns: [
                                        DataColumn(
                                          label: Text(
                                            'EMP ID',
                                            style: tableHeadingStyle,
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Name',
                                            style: tableHeadingStyle,
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Biometric ID',
                                            style: tableHeadingStyle,
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Active',
                                            style: tableHeadingStyle,
                                          ),
                                        ),
                                      ],
                                      rows: _rows.map((e) {
                                        final bio =
                                            e.biometricUserId?.trim() ?? '';
                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Tooltip(
                                                message: e.displayEmployeeNo,
                                                child: Text(
                                                  e.compactEmployeeNo,
                                                  style: tableCellStyle,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 260,
                                                child: Text(
                                                  e.fullName,
                                                  style: tableCellStyle,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 2,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                bio.isNotEmpty ? bio : '—',
                                                style: tableCellStyle.copyWith(
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                  fontWeight: bio.isNotEmpty
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              _RosterStatusPill(
                                                label: e.isActive
                                                    ? 'Yes'
                                                    : 'No',
                                                active: e.isActive,
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.dashMutedSurfaceOf(context),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.dashHairlineOf(context),
                        ),
                      ),
                      child: Text(
                        _total == 0
                            ? '0 employees'
                            : 'Page ${_pageIndex + 1} of $_totalPages · $_total total',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (_totalPages > 1)
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: _pageIndex <= 0 || _loading
                              ? null
                              : () {
                                  setState(() => _pageIndex--);
                                  _load();
                                },
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Previous'),
                        ),
                        TextButton.icon(
                          onPressed: _pageIndex >= _totalPages - 1 || _loading
                              ? null
                              : () {
                                  setState(() => _pageIndex++);
                                  _load();
                                },
                          label: const Text('Next'),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
