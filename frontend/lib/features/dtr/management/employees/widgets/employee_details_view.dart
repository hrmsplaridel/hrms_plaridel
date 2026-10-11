import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'employment_type_field.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

class EmployeeDetailsView extends StatefulWidget {
  const EmployeeDetailsView({super.key, required this.employeeId});
  final String employeeId;
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
      ? value.toString()
      : 'Not specified';
  String _date(dynamic value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    return date == null
        ? _value(value)
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _field(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
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
          style: TextStyle(color: AppTheme.dashTextPrimaryOf(context)),
        ),
      ],
    ),
  );

  Widget _section(String title, List<Widget> fields) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const Divider(),
        ...fields,
      ],
    ),
  );

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
                child: _field(metric.key, days(metric.value)),
              ),
          ],
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile ?? const <String, dynamic>{};
    final type = p['employment_type']?.toString();
    final history = (p['assignment_history'] as List? ?? const [])
        .whereType<Map>();
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        title: const Text('Employee full details'),
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _value(p['full_name']),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                  _section('Personal information', [
                    _field('First name', p['first_name']),
                    _field('Middle name', p['middle_name']),
                    _field('Last name', p['last_name']),
                    _field('Suffix', p['suffix']),
                    _field('Sex', p['sex']),
                    _field('Date of birth', _date(p['date_of_birth'])),
                    _field('Civil status', p['civil_status']),
                    _field('Nationality', p['nationality']),
                    _field('Contact number', p['contact_number']),
                    _field(
                      'Address',
                      formatStoredAddressForDisplay(p['address']?.toString()),
                    ),
                  ]),
                  _section('Employment', [
                    _field('Employee number', p['employee_number']),
                    _field(
                      'Employment type',
                      type == 'regular'
                          ? 'Regular (legacy)'
                          : employmentTypeLabels[type] ?? type,
                    ),
                    _field('Employment status', p['employment_status']),
                    _field('Salary grade', p['salary_grade']),
                    _field('Date hired', _date(p['date_hired'])),
                    _field('Separation date', _date(p['separation_date'])),
                    _field(
                      'Monthly VL/SL credits',
                      p['leave_credit_eligible'] == false
                          ? 'Not eligible'
                          : 'Eligible',
                    ),
                    if (p['leave_credit_eligible_until'] != null)
                      _field(
                        'Credit eligibility until',
                        _date(p['leave_credit_eligible_until']),
                      ),
                    _field('Current department', p['current_department_name']),
                    _field('Current position', p['current_position_name']),
                  ]),
                  _credits(p),
                  _section('Account', [
                    _field('Username / email', p['email']),
                    _field('Role', p['role']),
                    _field(
                      'Login status',
                      p['is_active'] == false ? 'Disabled' : 'Enabled',
                    ),
                    _field('Biometric user ID', p['biometric_user_id']),
                  ]),
                  _section('Assignment history', [
                    if (history.isEmpty) const Text('No assignments recorded.'),
                    for (final a in history) ...[
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
                      const Divider(),
                    ],
                  ]),
                ],
              ),
            ),
    );
  }
}
