import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/avatar_url.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/widgets/skeleton_bone.dart';
import 'employment_type_field.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

class EmployeeDetailsView extends StatefulWidget {
  const EmployeeDetailsView({super.key, required this.employeeId, this.onEdit});
  final String employeeId;

  /// Supplied only by a host that already exposes employee editing.
  final VoidCallback? onEdit;
  @override
  State<EmployeeDetailsView> createState() => _EmployeeDetailsViewState();
}

class _EmployeeDetailsViewState extends State<EmployeeDetailsView> {
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/employees/${widget.employeeId}/details',
      );
      if (mounted) {
        setState(() {
          _profile = response.data;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              (e.response?.data is Map ? e.response?.data['error'] : null)
                  ?.toString() ??
              'Could not load employee details.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load employee details.';
        });
      }
    }
  }

  String _value(dynamic value) => value?.toString().trim().isNotEmpty == true
      ? value.toString().trim()
      : 'Not specified';
  String _date(dynamic value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return date == null
        ? _value(value)
        : '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _label(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 'Not specified';
    return raw
        .split(RegExp(r'[_\s]+'))
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Widget _field(String label, dynamic value, {bool emphasis = false}) => Column(
    key: ValueKey(
      'employee-detail-${label.toLowerCase().replaceAll(' ', '-')}',
    ),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.dashTextSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 4),
      SelectableText(
        _value(value),
        style: TextStyle(
          color: emphasis
              ? AppTheme.primaryNavy
              : AppTheme.dashTextPrimaryOf(context),
          fontSize: emphasis ? 18 : 14,
          fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
          height: 1.45,
        ),
      ),
    ],
  );

  Widget _grid(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 520 &&
          MediaQuery.textScalerOf(context).scale(14) <= 19;
      final width = twoColumns
          ? (constraints.maxWidth - 24) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 24,
        runSpacing: 20,
        children: [
          for (final field in fields) SizedBox(width: width, child: field),
        ],
      );
    },
  );

  Widget _section(
    String title,
    List<Widget> fields, {
    IconData icon = Icons.badge_outlined,
  }) => Container(
    key: ValueKey(
      'employee-details-${title.toLowerCase().replaceAll(' ', '-')}',
    ),
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.dashPanelOf(context),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primaryNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...fields,
      ],
    ),
  );

  Widget _summary(Map<String, dynamic> profile) {
    final name = _value(profile['full_name']);
    final words = name.split(RegExp(r'\s+'));
    final firstName = profile['first_name']?.toString().trim() ?? '';
    final lastName = profile['last_name']?.toString().trim() ?? '';
    final initials = [
      firstName.isEmpty ? words.first : firstName,
      if (lastName.isNotEmpty || words.length > 1)
        lastName.isEmpty ? words.last : lastName,
    ].map((word) => word.characters.first.toUpperCase()).join();
    final avatarPath = profile['avatar_path']?.toString().trim() ?? '';
    final placeholder = Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 20,
          color: AppTheme.primaryNavy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final status = profile['employment_status']?.toString().trim() ?? '';
    final statusColor = status.toLowerCase() == 'active'
        ? const Color(0xFF2E7D32)
        : AppTheme.dashTextSecondaryOf(context);
    return Container(
      key: const ValueKey('employee-details-summary'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.25),
              ),
            ),
            child: avatarPath.isEmpty
                ? placeholder
                : Image.network(
                    userAvatarImageUrl(
                      widget.employeeId,
                      avatarPath: avatarPath,
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _value(profile['current_position_name']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _value(profile['current_department_name']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (status.isNotEmpty)
                      Semantics(
                        label: 'Employment status',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _label(status),
                            style: TextStyle(
                              color:
                                  AppTheme.dashIsDark(context) &&
                                      status.toLowerCase() == 'active'
                                  ? const Color(0xFF81C784)
                                  : statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (profile['employee_number'] != null)
                      Text(
                        'Employee #${profile['employee_number']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credits(Map<String, dynamic> profile) {
    final balances = (profile['credit_balances'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => LeaveBalance.fromJson(Map<String, dynamic>.from(row)))
        .where((balance) => balance.isCreditBalance)
        .toList();
    final eligible = profile['leave_credit_eligible'] != false;
    final historical = balances.any(
      (b) =>
          b.earnedDays != 0 ||
          b.usedDays != 0 ||
          b.pendingDays != 0 ||
          b.adjustedDays != 0 ||
          b.lastAccrualDate != null,
    );
    if (!eligible && !historical) {
      return _section('Leave credits', [
        const Text('This employee does not earn monthly VL/SL credits.'),
      ]);
    }
    if (eligible) {
      for (final type in [LeaveType.vacationLeave, LeaveType.sickLeave]) {
        if (!balances.any((b) => b.effectiveLeaveTypeName == type.value)) {
          balances.add(
            LeaveBalance(userId: widget.employeeId, leaveType: type),
          );
        }
      }
    }
    String days(double value) => '${value.toStringAsFixed(2)} days';
    return _section('Leave credits', [
      for (final balance in balances) ...[
        Text(
          balance.leaveTypeLabel,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final metric in <String, double>{
              'Available': balance.availableDays,
              'Earned': balance.earnedDays,
              'Used': balance.usedDays,
              'Pending': balance.pendingDays,
              'Adjusted': balance.adjustedDays,
            }.entries)
              SizedBox(
                width: 130,
                child: _field(
                  metric.key,
                  days(metric.value),
                  emphasis: metric.key == 'Available',
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ]);
  }

  Widget _profileContent(Map<String, dynamic> p) {
    final type = p['employment_type']?.toString();
    final history = (p['assignment_history'] as List? ?? const [])
        .whereType<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Employment', [
          _grid([
            _field('Employee number', p['employee_number']),
            _field(
              'Employment type',
              type == 'regular'
                  ? 'Regular (legacy)'
                  : employmentTypeLabels[type] ?? type,
            ),
            _field('Current position', p['current_position_name']),
            _field('Current department', p['current_department_name']),
            _field('Employment status', _label(p['employment_status'])),
            _field('Salary grade', p['salary_grade']),
            _field('Date hired', _date(p['date_hired'])),
            _field('Separation date', _date(p['separation_date'])),
            _field(
              'Monthly VL/SL credits',
              p['leave_credit_eligible'] == false ? 'Not eligible' : 'Eligible',
            ),
            if (p['leave_credit_eligible_until'] != null)
              _field(
                'Credit eligibility until',
                _date(p['leave_credit_eligible_until']),
              ),
          ]),
        ], icon: Icons.work_outline_rounded),
        _section('Personal information', [
          _grid([
            _field('First name', p['first_name']),
            _field('Middle name', p['middle_name']),
            _field('Last name', p['last_name']),
            _field('Suffix', p['suffix']),
            _field('Sex', p['sex']),
            _field('Date of birth', _date(p['date_of_birth'])),
            _field('Civil status', p['civil_status']),
            _field('Nationality', p['nationality']),
          ]),
        ], icon: Icons.person_outline_rounded),
        _section('Contact', [
          _grid([
            _field('Email address', p['email']),
            _field('Contact number', p['contact_number']),
          ]),
          const SizedBox(height: 20),
          _field(
            'Address',
            formatStoredAddressForDisplay(p['address']?.toString()),
          ),
        ], icon: Icons.contact_mail_outlined),
        _credits(p),
        _section('Account', [
          _grid([
            _field('Role', _label(p['role'])),
            _field(
              'Login status',
              p['is_active'] == false ? 'Disabled' : 'Enabled',
            ),
            _field('Biometric user ID', p['biometric_user_id']),
          ]),
        ], icon: Icons.manage_accounts_outlined),
        _section('Assignment history', [
          if (history.isEmpty) const Text('No assignments recorded.'),
          for (final a in history)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _grid([
                _field('Department', a['department_name']),
                _field('Position', a['position_name']),
                _field('Shift', a['shift_name']),
                if (a['shift_start_time'] != null ||
                    a['shift_end_time'] != null)
                  _field(
                    'Shift hours',
                    '${_value(a['shift_start_time'])} – ${_value(a['shift_end_time'])}',
                  ),
                _field(
                  'Effective period',
                  '${_date(a['effective_from'])} to ${a['effective_to'] == null ? 'No end date' : _date(a['effective_to'])}',
                ),
                _field('Status', a['status']),
                if (a['remarks']?.toString().trim().isNotEmpty == true)
                  _field('Remarks', a['remarks']),
              ]),
            ),
        ], icon: Icons.history_rounded),
      ],
    );
  }

  Widget _loadingContent() => Semantics(
    label: 'Loading employee details',
    child: const ExcludeSemantics(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBone(height: 72, width: double.infinity),
            SizedBox(height: 24),
            SkeletonBone(height: 24, width: 150),
            SizedBox(height: 16),
            SkeletonBone(height: 120, width: double.infinity),
            SizedBox(height: 16),
            SkeletonBone(height: 120, width: double.infinity),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = _profile ?? const <String, dynamic>{};
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: const Text(
          'Employee full details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _loading
          ? _loadingContent()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                _summary(p),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('employee-details-scroll'),
                    padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                    ),
                    child: _profileContent(p),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        key: const ValueKey('employee-details-footer'),
        decoration: BoxDecoration(
          color: AppTheme.dashPanelOf(context),
          border: Border(
            top: BorderSide(color: AppTheme.dashHairlineOf(context)),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              if (widget.onEdit != null)
                FilledButton.icon(
                  onPressed: _loading || _error != null || _profile == null
                      ? null
                      : widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit employee'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
