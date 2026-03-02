import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dtr/dtr_provider.dart';
import '../landingpage/constants/app_theme.dart';

/// Employee profile for Manage screen (full data from profiles).
class _EmployeeProfile {
  const _EmployeeProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.email,
    this.isActive = true,
    this.avatarPath,
    this.middleName,
    this.suffix,
    this.sex,
    this.dateOfBirth,
    this.contactNumber,
    this.address,
  });
  final String id;
  final String fullName;
  final String role;
  final String? email;
  final bool isActive;
  final String? avatarPath;
  final String? middleName;
  final String? suffix;
  final String? sex;
  final DateTime? dateOfBirth;
  final String? contactNumber;
  final String? address;

  String get roleDisplay => role == 'admin' ? 'Admin' : 'User';
}

/// Employees management screen: list with filters and detail panel.
/// Matches reference: search, Privilege/Status filters, ID/Name/Privilege columns,
/// right panel with avatar, Add/Edit/Deactivate buttons.
class ManageEmployee extends StatefulWidget {
  const ManageEmployee({super.key});

  @override
  State<ManageEmployee> createState() => _ManageEmployeeState();
}

class _ManageEmployeeState extends State<ManageEmployee> {
  final _searchController = TextEditingController();
  String _privilegeFilter = 'All';
  String _statusFilter = 'Active';
  String? _selectedEmployeeId;
  List<_EmployeeProfile> _employees = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmployees());
  }

  Future<void> _loadEmployees() async {
    setState(() => _loading = true);
    try {
      var query = Supabase.instance.client
          .from('profiles')
          .select(
            'id, full_name, role, email, is_active, avatar_path, middle_name, suffix, sex, date_of_birth, contact_number, address',
          );

      if (_statusFilter == 'Active') {
        query = query.or('is_active.is.null,is_active.eq.true');
      } else if (_statusFilter == 'Inactive') {
        query = query.eq('is_active', false);
      }

      if (_privilegeFilter != 'All') {
        final roleFilter = _privilegeFilter == 'Admin' ? 'admin' : 'employee';
        query = query.eq('role', roleFilter);
      }

      final res = await query.order('full_name');
      _employees = (res as List).map((e) {
        final m = e as Map<String, dynamic>;
        final dob = m['date_of_birth'];
        return _EmployeeProfile(
          id: m['id'] as String,
          fullName: m['full_name'] as String? ?? 'Unknown',
          role: m['role'] as String? ?? 'employee',
          email: m['email'] as String?,
          isActive: m['is_active'] as bool? ?? true,
          avatarPath: m['avatar_path'] as String?,
          middleName: m['middle_name'] as String?,
          suffix: m['suffix'] as String?,
          sex: m['sex'] as String?,
          dateOfBirth: dob != null ? DateTime.tryParse(dob.toString()) : null,
          contactNumber: m['contact_number'] as String?,
          address: m['address'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('Load employees failed: $e');
      _employees = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Employees',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        isNarrow ? _buildNarrowLayout() : _buildWideLayout(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        SizedBox(width: 280, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftPanel(),
        const SizedBox(height: 24),
        _buildRightPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _employees
        : _employees
              .where((e) => e.fullName.toLowerCase().contains(search))
              .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 200, child: _buildSearchField()),
              _buildDropdown(
                'Privilege',
                _privilegeFilter,
                ['All', 'Admin', 'User'],
                (v) {
                  setState(() => _privilegeFilter = v ?? 'All');
                  _loadEmployees();
                },
              ),
              _buildDropdown(
                'Status',
                _statusFilter,
                ['Active', 'Inactive', 'All'],
                (v) {
                  setState(() => _statusFilter = v ?? 'Active');
                  _loadEmployees();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.lightGray.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    'ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Privilege',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No employees yet',
                style: TextStyle(
                  color: AppTheme.textSecondary.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ...filtered.asMap().entries.map((entry) {
              final e = entry.value;
              final isSelected = _selectedEmployeeId == e.id;
              return Material(
                color: isSelected
                    ? AppTheme.primaryNavy.withOpacity(0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedEmployeeId = e.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            e.id.length > 8
                                ? '${e.id.substring(0, 8)}...'
                                : e.id,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text(
                            e.roleDisplay,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withOpacity(0.8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.textSecondary.withOpacity(0.7),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppTheme.lightGray.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRightPanel() {
    _EmployeeProfile? selected;
    if (_selectedEmployeeId != null) {
      try {
        selected = _employees.firstWhere((e) => e.id == _selectedEmployeeId);
      } catch (_) {}
    }
    final sel = selected;
    final hasSelection = sel != null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          hasSelection && (sel.avatarPath ?? '').isNotEmpty
              ? FutureBuilder<String?>(
                  future: Supabase.instance.client.storage
                      .from('avatars')
                      .createSignedUrl(sel.avatarPath!, 3600),
                  builder: (context, snap) {
                    if (snap.hasData && snap.data != null) {
                      return CircleAvatar(
                        radius: 48,
                        backgroundImage: NetworkImage(snap.data!),
                      );
                    }
                    return CircleAvatar(
                      radius: 48,
                      backgroundColor: AppTheme.lightGray,
                      child: Icon(
                        Icons.person_rounded,
                        size: 56,
                        color: AppTheme.textSecondary.withOpacity(0.5),
                      ),
                    );
                  },
                )
              : CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.lightGray,
                  child: Icon(
                    Icons.person_rounded,
                    size: 56,
                    color: AppTheme.textSecondary.withOpacity(0.5),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            hasSelection ? sel.fullName : 'Select an employee',
            style: TextStyle(
              color: hasSelection
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary.withOpacity(0.8),
              fontSize: 14,
              fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showAddEmployeeDialog(context),
              icon: const Icon(Icons.person_add_rounded, size: 20),
              label: const Text('Add Employee'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasSelection
                  ? () => _showEditEmployeeDialog(context, sel)
                  : null,
              icon: Icon(
                Icons.edit_rounded,
                size: 20,
                color: hasSelection
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary.withOpacity(0.5),
              ),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(
                  color: hasSelection
                      ? const Color(0xFF4CAF50).withOpacity(0.6)
                      : AppTheme.lightGray,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasSelection
                  ? () {
                      final p = sel;
                      p.isActive
                          ? _confirmDeactivate(context, p)
                          : _confirmActivate(context, p);
                    }
                  : null,
              icon: Icon(
                (hasSelection && !sel.isActive)
                    ? Icons.person_add_rounded
                    : Icons.person_off_rounded,
                size: 20,
                color: hasSelection
                    ? Colors.white
                    : Colors.white.withOpacity(0.5),
              ),
              label: Text(
                hasSelection && !sel.isActive ? 'Activate' : 'Deactivate',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: (hasSelection && !sel.isActive)
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE53935),
                disabledBackgroundColor: Colors.red.shade200.withOpacity(0.5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmActivate(BuildContext context, _EmployeeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activate employee?'),
        content: Text(
          'This will reactivate the account of ${profile.fullName}. They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'is_active': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', profile.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${profile.fullName} has been activated.')),
        );
        setState(() => _selectedEmployeeId = null);
        _loadEmployees();
        context.read<DtrProvider>().loadEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to activate: $e')));
      }
    }
  }

  void _showAddEmployeeDialog(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _AddEmployeeDialog(),
    );
    if (created == true && mounted) {
      _loadEmployees();
      context.read<DtrProvider>().loadEmployees();
    }
  }

  void _showEditEmployeeDialog(
    BuildContext context,
    _EmployeeProfile profile,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _EditEmployeeDialog(profile: profile),
    );
    if (updated == true && mounted) {
      _loadEmployees();
      context.read<DtrProvider>().loadEmployees();
    }
  }

  void _confirmDeactivate(
    BuildContext context,
    _EmployeeProfile profile,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate employee?'),
        content: Text(
          'This will deactivate the account of ${profile.fullName}. They will no longer be able to sign in.',
        ),
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
      await Supabase.instance.client
          .from('profiles')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', profile.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${profile.fullName} has been deactivated.')),
        );
        setState(() => _selectedEmployeeId = null);
        _loadEmployees();
        context.read<DtrProvider>().loadEmployees();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
      }
    }
  }
}

/// Parses full_name into first, middle, last.
void _parseFullName(
  String fullName,
  TextEditingController first,
  TextEditingController middle,
  TextEditingController last,
) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    first.text = '';
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 1) {
    first.text = parts[0];
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 2) {
    first.text = parts[0];
    middle.text = '';
    last.text = parts[1];
    return;
  }
  first.text = parts.first;
  last.text = parts.last;
  middle.text = parts.sublist(1, parts.length - 1).join(' ');
}

class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({required this.profile});
  final _EmployeeProfile profile;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  late final _EmployeeProfile _profile;
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();

  String? _privilege;
  String? _suffix;
  String? _sex;
  DateTime? _dateOfBirth;
  Uint8List? _selectedImageBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _parseFullName(
      _profile.fullName,
      _firstNameController,
      _middleNameController,
      _lastNameController,
    );
    if (_profile.middleName != null && _profile.middleName!.isNotEmpty) {
      _middleNameController.text = _profile.middleName!;
    }
    _contactController.text = _profile.contactNumber ?? '';
    _addressController.text = _profile.address ?? '';
    _privilege = _profile.role == 'admin' ? 'Admin' : 'User';
    _suffix = _profile.suffix;
    _sex = _profile.sex;
    _dateOfBirth = _profile.dateOfBirth;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withOpacity(0.7),
      fontSize: 14,
    ),
    filled: true,
    fillColor: AppTheme.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
    ),
  );

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.bytes != null) {
      setState(() {
        _selectedImageBytes = result.files.single.bytes;
      });
    }
  }

  Future<void> _saveEmployee(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final suffixPart = (_suffix != null && _suffix != 'None')
        ? ' ${_suffix!}'
        : '';
    final fullName =
        '$firstName${middleName.isNotEmpty ? ' $middleName' : ''} $lastName$suffixPart'
            .trim();
    final privilege = _privilege ?? 'User';
    final role = privilege == 'Admin' ? 'admin' : 'employee';

    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        'full_name': fullName,
        'role': role,
        'updated_at': DateTime.now().toIso8601String(),
        if (middleName.isNotEmpty) 'middle_name': middleName,
        if (_suffix != null && _suffix != 'None') 'suffix': _suffix,
        if (_sex != null) 'sex': _sex,
        if (_dateOfBirth != null)
          'date_of_birth': _dateOfBirth!.toIso8601String().split('T')[0],
        if (_contactController.text.trim().isNotEmpty)
          'contact_number': _contactController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
      };

      if (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty) {
        try {
          final ext = 'jpg';
          final avatarPath = '${_profile.id}/avatar.$ext';
          await Supabase.instance.client.storage
              .from('avatars')
              .uploadBinary(
                avatarPath,
                _selectedImageBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
          updates['avatar_path'] = avatarPath;
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      await Supabase.instance.client
          .from('profiles')
          .update(updates)
          .eq('id', _profile.id);

      if (!mounted) return;
      try {
        context.read<DtrProvider>().loadEmployees();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee updated successfully.')),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height - 48,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAccountSection(),
                            const SizedBox(height: 24),
                            _buildPersonalSection(),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildAccountSection()),
                            const SizedBox(width: 28),
                            Expanded(child: _buildPersonalSection()),
                          ],
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _saveEmployee(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: _selectedImageBytes != null
                ? CircleAvatar(
                    radius: 48,
                    backgroundImage: MemoryImage(_selectedImageBytes!),
                  )
                : _profile.avatarPath != null
                ? FutureBuilder<String>(
                    future: Supabase.instance.client.storage
                        .from('avatars')
                        .createSignedUrl(_profile.avatarPath!, 60),
                    builder: (context, snap) {
                      if (snap.hasData && snap.data != null) {
                        return CircleAvatar(
                          radius: 48,
                          backgroundImage: NetworkImage(snap.data!),
                        );
                      }
                      return CircleAvatar(
                        radius: 48,
                        backgroundColor: AppTheme.lightGray,
                        child: Icon(
                          Icons.person_rounded,
                          size: 56,
                          color: AppTheme.textSecondary.withOpacity(0.5),
                        ),
                      );
                    },
                  )
                : CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.lightGray,
                    child: Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: AppTheme.textSecondary.withOpacity(0.5),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Select Image'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          InputDecorator(
            decoration: _inputDecoration('Email'),
            child: Text(
              _profile.email ?? '—',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _privilege,
            decoration: _inputDecoration('Select'),
            hint: const Text(
              'Select',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Admin',
              'User',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _privilege = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration('First Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _middleNameController,
            decoration: _inputDecoration('Middle Name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration('Last Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _suffix ?? 'None',
            decoration: _inputDecoration('None'),
            hint: const Text(
              'None',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'None',
              'Jr.',
              'Sr.',
              'II',
              'III',
              'IV',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) =>
                setState(() => _suffix = (v == 'None') ? null : v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: _inputDecoration('Select'),
            hint: const Text(
              'Select',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Male',
              'Female',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _sex = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _dateOfBirth ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) setState(() => _dateOfBirth = date);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('Date Of Birth').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              child: Text(
                _dateOfBirth != null
                    ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                    : '',
                style: TextStyle(
                  fontSize: 14,
                  color: _dateOfBirth != null
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contactController,
            decoration: _inputDecoration('Contact Number'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: _inputDecoration('Address'),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _AddEmployeeDialog extends StatefulWidget {
  const _AddEmployeeDialog();

  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();

  String? _privilege;
  String? _suffix;
  String? _sex;
  DateTime? _dateOfBirth;
  bool _obscurePassword = true;
  bool _obscureRepeatPassword = true;
  Uint8List? _selectedImageBytes;
  bool _saving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withOpacity(0.7),
      fontSize: 14,
    ),
    filled: true,
    fillColor: AppTheme.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
    ),
  );

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.bytes != null) {
      setState(() {
        _selectedImageBytes = result.files.single.bytes;
      });
    }
  }

  Future<void> _saveEmployee(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final suffixPart = (_suffix != null && _suffix != 'None')
        ? ' ${_suffix!}'
        : '';
    final fullName =
        '$firstName${middleName.isNotEmpty ? ' $middleName' : ''} $lastName$suffixPart'
            .trim();
    final privilege = _privilege ?? 'User';
    final role = privilege == 'Admin' ? 'admin' : 'employee';

    setState(() => _saving = true);
    try {
      final meta = <String, dynamic>{
        'full_name': fullName,
        'role': role,
        if (middleName.isNotEmpty) 'middle_name': middleName,
        if (_suffix != null && _suffix != 'None') 'suffix': _suffix,
        if (_sex != null) 'sex': _sex,
        if (_dateOfBirth != null)
          'date_of_birth': _dateOfBirth!.toIso8601String().split('T')[0],
        if (_contactController.text.trim().isNotEmpty)
          'contact_number': _contactController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
      };

      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: meta,
      );

      if (!mounted) return;
      if (res.user == null) {
        _showSnackBar(context, 'Account creation failed');
        return;
      }

      final userId = res.user!.id;
      String? avatarPath;

      if (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty) {
        try {
          final ext = 'jpg';
          avatarPath = '$userId/avatar.$ext';
          await Supabase.instance.client.storage
              .from('avatars')
              .uploadBinary(
                avatarPath,
                _selectedImageBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
          await Supabase.instance.client
              .from('profiles')
              .update({
                'avatar_path': avatarPath,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', userId);
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      try {
        context.read<DtrProvider>().loadEmployees();
      } catch (_) {}

      _showSnackBar(
        context,
        'Employee created successfully. They can sign in after email confirmation (if required).',
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) _showSnackBar(context, e.message);
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height - 48,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAccountSection(),
                            const SizedBox(height: 24),
                            _buildPersonalSection(),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildAccountSection()),
                            const SizedBox(width: 28),
                            Expanded(child: _buildPersonalSection()),
                          ],
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _saveEmployee(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add Employee'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: _selectedImageBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(48),
                    child: Image.memory(
                      _selectedImageBytes!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  )
                : CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.lightGray,
                    child: Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: AppTheme.textSecondary.withOpacity(0.5),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Select Image'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            decoration: _inputDecoration('Email'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: _inputDecoration('Password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _repeatPasswordController,
            decoration: _inputDecoration('Repeat Password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRepeatPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () => setState(
                  () => _obscureRepeatPassword = !_obscureRepeatPassword,
                ),
              ),
            ),
            obscureText: _obscureRepeatPassword,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _privilege,
            decoration: _inputDecoration('Select'),
            hint: const Text(
              'Select',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Admin',
              'User',
              'Viewer',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _privilege = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration('First Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _middleNameController,
            decoration: _inputDecoration('Middle Name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration('Last Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _suffix,
            decoration: _inputDecoration('None'),
            hint: const Text(
              'None',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'None',
              'Jr.',
              'Sr.',
              'II',
              'III',
              'IV',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _suffix = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: _inputDecoration('Select'),
            hint: const Text(
              'Select',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Male',
              'Female',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _sex = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _dateOfBirth ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) setState(() => _dateOfBirth = date);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('Date Of Birth').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              child: Text(
                _dateOfBirth != null
                    ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                    : '',
                style: TextStyle(
                  fontSize: 14,
                  color: _dateOfBirth != null
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contactController,
            decoration: _inputDecoration('Contact Number'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: _inputDecoration('Address'),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
