import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Department record for display/CRUD.
class _DepartmentRecord {
  const _DepartmentRecord({
    required this.id,
    required this.name,
    this.departmentNumber,
    this.description,
    required this.isActive,
    required this.canPermanentlyDelete,
  });
  final String id;
  final String name;
  final int? departmentNumber;
  final String? description;
  final bool isActive;
  final bool canPermanentlyDelete;

  String get displayDepartmentNo => departmentNumber != null
      ? 'DEPT-${departmentNumber!.toString().padLeft(3, '0')}'
      : '—';
}

class _DepartmentDeactivationBlocker {
  const _DepartmentDeactivationBlocker({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;
}

class _DepartmentDeactivationPreview {
  const _DepartmentDeactivationPreview({
    required this.canDeactivate,
    required this.blockers,
  });

  factory _DepartmentDeactivationPreview.fromJson(Map<String, dynamic> json) {
    final rawBlockers = json['blockers'];
    final blockers = rawBlockers is List
        ? rawBlockers.whereType<Map>().map((item) {
            final countValue = item['count'];
            return _DepartmentDeactivationBlocker(
              label: item['label']?.toString() ?? 'active dependencies',
              count: countValue is num
                  ? countValue.toInt()
                  : int.tryParse(countValue?.toString() ?? '') ?? 0,
            );
          }).toList()
        : <_DepartmentDeactivationBlocker>[];
    return _DepartmentDeactivationPreview(
      canDeactivate: json['can_deactivate'] == true,
      blockers: blockers,
    );
  }

  final bool canDeactivate;
  final List<_DepartmentDeactivationBlocker> blockers;
}

/// Department management screen: list with search/status filter + form for Add/Update/Deactivate.
class ManageDepartment extends StatefulWidget {
  const ManageDepartment({super.key});

  @override
  State<ManageDepartment> createState() => _ManageDepartmentState();
}

class _ManageDepartmentState extends State<ManageDepartment> {
  static const int _rowsPerPage = 10;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _statusFilter = 'Active';
  int _page = 0;
  List<_DepartmentRecord> _departments = [];
  bool _loading = false;
  _DepartmentRecord? _selectedDepartment;
  StateSetter? _drawerSetState;
  bool _reviewersLoading = false;
  bool _reviewersSaving = false;
  String? _reviewerEffectiveDate;
  Map<String, dynamic>? _primaryReviewer;
  List<Map<String, dynamic>> _reviewerRoster = [];
  List<String> _backupReviewerIds = [];
  int _departmentLoadGeneration = 0;

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

  void _updateDepartmentFormState(VoidCallback update) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDepartments());
  }

  @override
  void dispose() {
    _departmentLoadGeneration++;
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    final generation = ++_departmentLoadGeneration;
    final requestedStatus = _statusFilter;
    setState(() {
      _loading = true;
      _page = 0;
    });
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
        queryParameters: {'status': requestedStatus},
      );
      final data = res.data ?? [];
      final departments = data.map((e) {
        final m = e as Map<String, dynamic>;
        final numVal = m['department_number'];
        return _DepartmentRecord(
          id: m['id'] as String,
          name: m['name'] as String? ?? '',
          departmentNumber: numVal is int
              ? numVal
              : (numVal != null ? int.tryParse(numVal.toString()) : null),
          description: m['description'] as String?,
          isActive: m['is_active'] as bool? ?? true,
          canPermanentlyDelete: m['can_permanently_delete'] as bool? ?? false,
        );
      }).toList();
      if (!mounted ||
          generation != _departmentLoadGeneration ||
          requestedStatus != _statusFilter) {
        return;
      }
      setState(() => _departments = departments);
    } on DioException catch (e) {
      if (!mounted ||
          generation != _departmentLoadGeneration ||
          requestedStatus != _statusFilter) {
        return;
      }
      debugPrint('Load departments failed: ${e.response?.data ?? e.message}');
      setState(() => _departments = []);
    } catch (e) {
      if (!mounted ||
          generation != _departmentLoadGeneration ||
          requestedStatus != _statusFilter) {
        return;
      }
      debugPrint('Load departments failed: $e');
      setState(() => _departments = []);
    } finally {
      if (mounted && generation == _departmentLoadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectDepartment(_DepartmentRecord d) {
    _updateDepartmentFormState(() {
      _selectedDepartment = d;
      _nameController.text = d.name;
      _descriptionController.text = d.description ?? '';
    });
    _loadReviewerConfig(d.id);
  }

  void _clearForm() {
    _updateDepartmentFormState(() {
      _selectedDepartment = null;
      _nameController.clear();
      _descriptionController.clear();
      _reviewerEffectiveDate = null;
      _primaryReviewer = null;
      _reviewerRoster = [];
      _backupReviewerIds = [];
    });
  }

  Future<void> _loadReviewerConfig(
    String departmentId, {
    String? effectiveDate,
  }) async {
    _updateDepartmentFormState(() => _reviewersLoading = true);
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/departments/$departmentId/reviewer-config',
        queryParameters: {
          if (effectiveDate != null) 'effective_date': effectiveDate,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      final rawRoster = data['eligible_employees'];
      final rawBackups = data['backups'];
      _updateDepartmentFormState(() {
        _reviewerEffectiveDate = data['effective_date']?.toString();
        _primaryReviewer = data['primary'] is Map
            ? Map<String, dynamic>.from(data['primary'] as Map)
            : null;
        _reviewerRoster = rawRoster is List
            ? rawRoster
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        _backupReviewerIds = rawBackups is List
            ? rawBackups
                  .whereType<Map>()
                  .map((item) => item['reviewerId']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toList()
            : [];
      });
    } on DioException catch (error) {
      if (mounted) {
        final message =
            (error.response?.data as Map?)?['error'] ?? error.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load reviewers: $message')),
        );
      }
    } finally {
      _updateDepartmentFormState(() => _reviewersLoading = false);
    }
  }

  Future<void> _pickReviewerEffectiveDate() async {
    final initial =
        DateTime.tryParse(_reviewerEffectiveDate ?? '') ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || _selectedDepartment == null) return;
    final value =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    await _loadReviewerConfig(_selectedDepartment!.id, effectiveDate: value);
  }

  Future<void> _saveReviewerBackups() async {
    final department = _selectedDepartment;
    final effectiveDate = _reviewerEffectiveDate;
    if (department == null || effectiveDate == null || _reviewersSaving) return;
    _updateDepartmentFormState(() => _reviewersSaving = true);
    try {
      await ApiClient.instance.put(
        '/api/departments/${department.id}/reviewer-backups',
        data: {
          'effective_from': effectiveDate,
          'employee_ids': _backupReviewerIds,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Department reviewer backups saved.')),
        );
      }
      await _loadReviewerConfig(department.id, effectiveDate: effectiveDate);
    } on DioException catch (error) {
      if (mounted) {
        final message =
            (error.response?.data as Map?)?['error'] ?? error.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save reviewers: $message')),
        );
      }
    } finally {
      _updateDepartmentFormState(() => _reviewersSaving = false);
    }
  }

  Future<bool> _addDepartment() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return false;
    }
    try {
      await ApiClient.instance.post(
        '/api/departments',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          'is_active': true,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department added.')));
        _clearForm();
        _loadDepartments();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
      return false;
    }
  }

  Future<bool> _updateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to update.')),
      );
      return false;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a department name.')),
      );
      return false;
    }
    try {
      await ApiClient.instance.put(
        '/api/departments/${d.id}',
        data: {
          'name': name,
          'description': _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Department updated.')));
        _clearForm();
        _loadDepartments();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
      return false;
    }
  }

  Future<bool> _deactivateDepartment() async {
    final d = _selectedDepartment;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a department to deactivate.')),
      );
      return false;
    }
    late final _DepartmentDeactivationPreview preview;
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/departments/${d.id}/deactivation-preview',
      );
      preview = _DepartmentDeactivationPreview.fromJson(response.data ?? {});
    } on DioException catch (e) {
      if (mounted) {
        final msg =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to check department dependencies';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check department dependencies: $e'),
          ),
        );
      }
      return false;
    }
    if (!mounted) return false;

    if (!preview.canDeactivate) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Department is still in use'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resolve the following items before deactivating "${d.name}":',
              ),
              const SizedBox(height: 16),
              ...preview.blockers.map(
                (blocker) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${blocker.count} ${blocker.label}'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate department?'),
        content: Text(
          'This will deactivate "${d.name}". It will no longer appear in active lists.',
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
    if (ok != true || !mounted) return false;
    try {
      await ApiClient.instance.put(
        '/api/departments/${d.id}',
        data: {'is_active': false},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${d.name} has been deactivated.')),
        );
        _clearForm();
        _loadDepartments();
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
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $msg')));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
      }
      return false;
    }
  }

  Future<bool> _reactivateDepartment() async {
    final department = _selectedDepartment;
    if (department == null || department.isActive) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reactivate department?'),
        content: Text(
          'This will restore "${department.name}" to active department lists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await ApiClient.instance.put(
        '/api/departments/${department.id}',
        data: {'is_active': true},
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${department.name} has been reactivated.')),
      );
      _clearForm();
      _loadDepartments();
      return true;
    } on DioException catch (error) {
      if (mounted) {
        final message =
            (error.response?.data as Map?)?['error'] ??
            error.message ??
            'Failed to reactivate department';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reactivate: $message')),
        );
      }
      return false;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to reactivate: $error')));
      }
      return false;
    }
  }

  Future<String?> _requestMistakenDeleteReason(
    _DepartmentRecord department,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete mistaken department?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes "${department.name}". This is allowed only because the department has no dependent records.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why was this department created by mistake?',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'A reason is required.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete permanently'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<bool> _deleteMistakenDepartment() async {
    final department = _selectedDepartment;
    if (department == null || !department.canPermanentlyDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This department is already in use and cannot be permanently deleted.',
          ),
        ),
      );
      return false;
    }

    final reason = await _requestMistakenDeleteReason(department);
    if (reason == null || !mounted) return false;
    try {
      await ApiClient.instance.delete(
        '/api/departments/${department.id}',
        data: {'reason': reason},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mistaken department deleted.')),
        );
        _clearForm();
        _loadDepartments();
      }
      return true;
    } on DioException catch (e) {
      if (mounted) {
        final message =
            (e.response?.data as Map?)?['error'] ??
            e.message ??
            'Failed to delete department';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.toString())));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete department: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _openDepartmentDrawer({_DepartmentRecord? department}) async {
    _drawerSetState = null;
    if (department == null) {
      _clearForm();
    } else {
      _selectDepartment(department);
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
          final drawerWidth = screenWidth < 720 ? screenWidth : 520.0;
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
                    return _buildDepartmentDrawer(dialogContext);
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

  Widget _buildDepartmentDrawer(BuildContext drawerContext) {
    final isEditing = _selectedDepartment != null;
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
                    isEditing ? 'Edit Department' : 'Add Department',
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
    final isEditing = _selectedDepartment != null;
    final department = _selectedDepartment;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          if (department != null && department.isActive)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateDepartment();
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
          if (department != null && !department.isActive)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _reactivateDepartment();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Reactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green,
                side: const BorderSide(color: Colors.green),
              ),
            ),
          if (department != null && department.canPermanentlyDelete)
            const SizedBox(width: 12),
          if (department != null && department.canPermanentlyDelete)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deleteMistakenDepartment();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Delete Mistake'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () async {
              final ok = isEditing
                  ? await _updateDepartment()
                  : await _addDepartment();
              if (ok && drawerContext.mounted) {
                Navigator.of(drawerContext).pop();
              }
            },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Department'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Department',
                style: TextStyle(
                  color: _headingColor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openDepartmentDrawer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Department'),
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
        const SizedBox(height: 20),
        _buildLeftPanel(),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final dark = _isDark(context);
    final search = _searchController.text.toLowerCase();
    final filtered = search.isEmpty
        ? _departments
        : _departments.where((d) {
            final n = d.name.toLowerCase();
            final desc = (d.description ?? '').toLowerCase();
            return n.contains(search) || desc.contains(search);
          }).toList();
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
        ? <_DepartmentRecord>[]
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
              SizedBox(width: 200, child: _buildSearchField()),
              _buildStatusDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 88, child: _tableHeaderText('No.')),
                Expanded(child: _tableHeaderText('Name')),
                Expanded(flex: 2, child: _tableHeaderText('Description')),
              ],
            ),
          ),
          if (_loading)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: const CircularProgressIndicator(),
            )
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No departments',
                style: TextStyle(
                  color: _mutedColor(context).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            Column(
              children: [
                Table(
                  columnWidths: const {
                    0: FixedColumnWidth(88),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(2),
                  },
                  children: paged.map((d) {
                    final isSelected = _selectedDepartment?.id == d.id;
                    return TableRow(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (dark
                                  ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                                  : AppTheme.primaryNavy.withValues(
                                      alpha: 0.08,
                                    ))
                            : null,
                      ),
                      children: [
                        _tableCell(
                          d.displayDepartmentNo,
                          onTap: () => _openDepartmentDrawer(department: d),
                        ),
                        _tableCell(
                          d.name,
                          onTap: () => _openDepartmentDrawer(department: d),
                        ),
                        _tableCell(
                          d.description ?? '—',
                          onTap: () => _openDepartmentDrawer(department: d),
                          secondary: true,
                        ),
                      ],
                    );
                  }).toList(),
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

  Widget _tableHeaderText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: _headingColor(context),
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _tableCell(
    String text, {
    VoidCallback? onTap,
    bool secondary = false,
  }) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: secondary ? 12 : 13,
              color: secondary ? _mutedColor(context) : _headingColor(context),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() => _page = 0),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search',
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: _mutedColor(context).withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        radius: 10,
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: (v) {
          setState(() {
            _statusFilter = v ?? 'Active';
            _page = 0;
          });
          _loadDepartments();
        },
      ),
    );
  }

  Widget _buildFormPanel({bool framed = true, bool showActions = true}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Department Name',
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
          decoration: _inputDecoration('Department Name'),
        ),
        const SizedBox(height: 20),
        Text(
          'Description',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descriptionController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration('Description'),
          maxLines: 4,
        ),
        if (_selectedDepartment != null) ...[
          const SizedBox(height: 28),
          Divider(color: AppTheme.dashHairlineOf(context)),
          const SizedBox(height: 18),
          Text(
            'Department Reviewers',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _headingColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The official Head is automatic. Selected backups can review the same requests.',
            style: TextStyle(fontSize: 12, color: _mutedColor(context)),
          ),
          const SizedBox(height: 18),
          Text(
            'Effective date',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reviewersLoading ? null : _pickReviewerEffectiveDate,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(
                _reviewerEffectiveDate ?? 'Select effective date',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_reviewersLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primary reviewer',
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _primaryReviewer?['reviewerName'] ??
                            'No official Department Head assigned',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _headingColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Backup reviewers',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _mutedColor(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Selection order sets the review rank.',
              style: TextStyle(fontSize: 12, color: _mutedColor(context)),
            ),
            const SizedBox(height: 8),
            if (_reviewerRoster.where((employee) {
              return employee['id']?.toString() !=
                  _primaryReviewer?['reviewerId']?.toString();
            }).isEmpty)
              Text(
                'No other active employees are assigned to this department on this date.',
                style: TextStyle(fontSize: 12, color: _mutedColor(context)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reviewerRoster
                    .where((employee) {
                      return employee['id']?.toString() !=
                          _primaryReviewer?['reviewerId']?.toString();
                    })
                    .map((employee) {
                      final id = employee['id']?.toString() ?? '';
                      final selected = _backupReviewerIds.contains(id);
                      final rank = selected
                          ? _backupReviewerIds.indexOf(id) + 1
                          : null;
                      return FilterChip(
                        selected: selected,
                        avatar: rank == null
                            ? null
                            : CircleAvatar(child: Text('$rank')),
                        label: Text(employee['name']?.toString() ?? id),
                        onSelected: (value) {
                          _updateDepartmentFormState(() {
                            if (value) {
                              if (_backupReviewerIds.length < 5) {
                                _backupReviewerIds.add(id);
                              }
                            } else {
                              _backupReviewerIds.remove(id);
                            }
                          });
                        },
                      );
                    })
                    .toList(),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _reviewersSaving ? null : _saveReviewerBackups,
                icon: _reviewersSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save Reviewers'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ],
        if (showActions) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _addDepartment(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Department'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _selectedDepartment != null
                    ? () => _updateDepartment()
                    : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedDepartment != null
                    ? () => _deactivateDepartment()
                    : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
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

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
