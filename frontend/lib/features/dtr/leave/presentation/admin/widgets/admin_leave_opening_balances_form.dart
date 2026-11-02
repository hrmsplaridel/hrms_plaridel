import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_adjustment_employee_loader.dart';
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';
import 'package:hrms_plaridel/shared/widgets/workforce_loading_skeleton.dart';

class AdminLeaveOpeningBalancesForm extends StatefulWidget {
  const AdminLeaveOpeningBalancesForm({
    super.key,
    required this.onSavingChanged,
  });
  final ValueChanged<bool> onSavingChanged;
  @override
  State<AdminLeaveOpeningBalancesForm> createState() => _OpeningBalancesState();
}

class _OpeningBalancesState extends State<AdminLeaveOpeningBalancesForm> {
  final _form = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _sl = TextEditingController(),
      _vl = TextEditingController(),
      _reason = TextEditingController();
  final _qualifying = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  Map<String, String> _recordedCutoffs = {};
  String? _departmentFilter;
  String _statusFilter = 'all';
  Map<String, dynamic>? _employee, _existing;
  bool _loading = true, _saving = false, _confirmed = false;
  String? _error, _currentBalances;
  DateTime? _cutoff, _latestCutoff, _dateHired;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _search.dispose();
    _sl.dispose();
    _vl.dispose();
    _reason.dispose();
    _qualifying.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        loadLeaveAdjustmentEmployees(),
        ApiClient.instance
            .get<Map<String, dynamic>>('/api/leave/admin/opening-balances')
            .then((r) => r.data),
      ]);
      final rows = results[0] as List<Map<String, dynamic>>;
      final status = results[1] as Map<String, dynamic>?;
      if (status?['setups'] is! List) {
        throw const FormatException(
          'Invalid opening balance recording status.',
        );
      }
      final cutoffs = <String, String>{
        for (final setup in (status!['setups'] as List).whereType<Map>())
          setup['user_id'].toString(): setup['cutoff_date'].toString(),
      };
      if (mounted) {
        setState(() {
          _employees = rows.where((r) => r['role'] != 'super_admin').toList();
          _recordedCutoffs = cutoffs;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectEmployee(Map<String, dynamic> employee) async {
    final generation = ++_generation;
    setState(() {
      _employee = employee;
      _loading = true;
      _error = null;
      _existing = null;
      _confirmed = false;
      _cutoff = null;
      _dateHired = null;
      _currentBalances = null;
    });
    _sl.clear();
    _vl.clear();
    _reason.clear();
    _qualifying.clear();
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/admin/opening-balances/${employee['id']}',
      );
      if (!mounted || generation != _generation) return;
      final data = response.data!;
      final today = DateTime.parse(data['official_date'].toString());
      final latest = DateTime(today.year, today.month, 0);
      final balances = (data['balances'] as List? ?? []).whereType<Map>();
      double available(String type) {
        final row = balances.where((b) => b['leave_type'] == type).firstOrNull;
        double n(String key) => double.tryParse('${row?[key] ?? 0}') ?? 0;
        return n('earned_days') -
            n('used_days') +
            n('adjusted_days') -
            n('pending_days');
      }

      setState(() {
        _latestCutoff = latest;
        _cutoff = latest;
        final hireValue = data.containsKey('date_hired') ? data['date_hired'] : employee['date_hired'];
        _dateHired = DateTime.tryParse(hireValue?.toString() ?? '');
        _existing = data['setup'] is Map
            ? Map<String, dynamic>.from(data['setup'] as Map)
            : null;
        if (_existing != null) {
          _recordedCutoffs[employee['id'].toString()] =
              _existing!['cutoff_date'].toString();
        } else {
          _recordedCutoffs.remove(employee['id'].toString());
        }
        _currentBalances =
            'Currently recorded: SL ${available('sickLeave').toStringAsFixed(3)} · VL ${available('vacationLeave').toStringAsFixed(3)} days';
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = userFacingApiError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  DateTime get _usageCutoff => _existing == null
      ? DateTime.utc(_cutoff!.year, _cutoff!.month, _cutoff!.day)
      : DateTime.parse('${_existing!['cutoff_date'].toString().substring(0, 10)}T00:00:00Z');

  DateTime get _usageStart {
    final yearStart = DateTime.utc(_usageCutoff.year);
    final hired = _dateHired;
    if (hired == null) return yearStart;
    final hireDate = DateTime.utc(hired.year, hired.month, hired.day);
    return hireDate.isAfter(yearStart) ? hireDate : yearStart;
  }

  int get _maxQualifyingDays {
    final days = _usageCutoff.difference(_usageStart).inDays + 1;
    return days < 0 ? 0 : days;
  }
  Future<void> _chooseMonth() async {
    final picked = await showHrmsDatePicker(
      context: context,
      initialDate: _cutoff!,
      firstDate: DateTime(1900),
      lastDate: _latestCutoff!,
      helpText: 'Select the month already accounted for',
    );
    if (picked != null && mounted) {
      setState(() {
        _cutoff = DateTime(picked.year, picked.month + 1, 0);
        _confirmed = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _loading ||
        _cutoff == null ||
        _existing != null ||
        _form.currentState?.validate() != true) {
      return;
    }
    if (!_confirmed) {
      setState(
        () => _error =
            'Confirm the balances are verified through the cutoff date.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onSavingChanged(true);
    try {
      await ApiClient.instance.dio.post(
        '/api/leave/admin/opening-balances/${_employee!['id']}',
        data: {
          'cutoff_date': _date(_cutoff!),
          'sick_leave_days': double.parse(_sl.text.trim()),
          'vacation_leave_days': double.parse(_vl.text.trim()),
          'reason': _reason.text.trim(),
          'qualifying_leave_days': double.parse(_qualifying.text.trim()),
          'confirmed': true,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        widget.onSavingChanged(false);
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String key, {
    bool days = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_saving,
        keyboardType: days
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.multiline,
        maxLines: days ? 1 : 3,
        maxLength: days ? null : 500,
        decoration: AppTheme.dashInputDecoration(context).copyWith(
          hintText: days
              ? '0.000 days'
              : 'Source document or HR verification reference',
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Required';
          if (days &&
              (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(text) ||
                  (double.tryParse(text) ?? double.infinity) > 9999999)) {
            return 'Enter non-negative days, up to 3 decimal places.';
          }
          if (key == 'opening-qualifying-days' && double.parse(text) > _maxQualifyingDays) {
            return 'Qualifying usage cannot exceed $_maxQualifyingDays calendar days for this period.';
          }
          return null;
        },
      ),
      const SizedBox(height: 20),
    ],
  );

  bool get _needsUsageVerification => _existing!=null && _existing!['qualifying_leave_days']==null;

  Future<void> _saveUsage() async {
    if(_saving || _loading || !_needsUsageVerification || _form.currentState?.validate()!=true) return;
    if(!_confirmed) {setState(()=>_error='Confirm the historical usage against the HR leave card.');return;}
    setState(() {_saving=true;_error=null;});widget.onSavingChanged(true);
    try {
      await ApiClient.instance.dio.post('/api/leave/admin/opening-balances/${_employee!['id']}/usage',data:{
        'cutoff_date':_existing!['cutoff_date'].toString().substring(0,10),
        'qualifying_leave_days':double.parse(_qualifying.text.trim()),'reference':_reason.text.trim(),'confirmed':true,
      });
      if(mounted) Navigator.of(context).pop(true);
    } catch(e) {if(mounted)setState(()=>_error=userFacingApiError(e));}
    finally {if(mounted){setState(()=>_saving=false);widget.onSavingChanged(false);}}
  }

  Widget _usageFields(String year, {bool legacy=false}) => Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      const SizedBox(height:20),
      Text('Vacation / Forced Leave already taken in $year',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)),
      const SizedBox(height:8),
      Text('Enter the verified qualifying working days from ${_date(_usageStart)} through ${_date(_usageCutoff)}. Enter 0 if none. Verify the total against the HR leave card. These days count for year-end compliance without another credit deduction.'),
      const SizedBox(height:16),
      _field('Qualifying days already taken',_qualifying,'opening-qualifying-days'),
      if(legacy) ...[
        _field('HR verification reference',_reason,'opening-usage-reference',days:false),
        CheckboxListTile(contentPadding:EdgeInsets.zero,value:_confirmed,onChanged:_saving?null:(value)=>setState(()=>_confirmed=value==true),
          title:const Text('I verified the qualifying usage through the saved cutoff.')),
      ],
    ],
  );

  String _department(Map<String, dynamic> employee) {
    for (final key in ['current_department_name', 'department_name']) {
      final name = employee[key]?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return 'No department assigned';
  }

  String _position(Map<String, dynamic> employee) =>
      (employee['current_position_name'] ?? employee['position_name'] ?? '')
          .toString()
          .trim();

  String _employmentLabel(Map<String, dynamic> employee) {
    final value = employee['employment_type']?.toString().trim() ?? '';
    return value
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1).toLowerCase())
        .join(' ');
  }

  void _clearFilters() => setState(() {
    _search.clear();
    _departmentFilter = null;
    _statusFilter = 'all';
  });

  Widget _filterField(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _badge(String label, {bool recorded = false}) {
    final color = recorded
        ? (AppTheme.dashIsDark(context)
              ? Colors.green.shade300
              : Colors.green.shade800)
        : AppTheme.dashTextSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: recorded
            ? color.withValues(alpha: 0.1)
            : AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _employeeRow(Map<String, dynamic> employee) {
    final name = (employee['full_name'] ?? 'Employee').toString();
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
              .toUpperCase();
    final position = _position(employee);
    final number = employee['employee_number']?.toString().trim() ?? '';
    final employment = _employmentLabel(employee);
    final recorded = _recordedCutoffs.containsKey(employee['id'].toString());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectEmployee(employee),
        hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppTheme.primaryNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_department(employee)}${position.isEmpty ? '' : ' · $position'}',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (number.isNotEmpty)
                          Text(
                            'ID $number',
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 11,
                            ),
                          ),
                        if (employment.isNotEmpty) _badge(employment),
                        _badge(
                          recorded ? 'Recorded' : 'Not recorded',
                          recorded: recorded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeePicker() {
    if (_loading || _error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const WorkforceRowsSkeleton(
                columns: [1, 3],
                rows: 4,
                label: 'Loading employee recording status',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadEmployees,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
      );
    }
    final departments = _employees.map(_department).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final departmentEmployees = _employees
        .where(
          (e) =>
              _departmentFilter == null || _department(e) == _departmentFilter,
        )
        .toList();
    final recorded = departmentEmployees
        .where((e) => _recordedCutoffs.containsKey(e['id'].toString()))
        .length;
    final query = _search.text.trim().toLowerCase();
    final employees = departmentEmployees.where((e) {
      final hasSetup = _recordedCutoffs.containsKey(e['id'].toString());
      if (_statusFilter == 'recorded' && !hasSetup ||
          _statusFilter == 'not_recorded' && hasSetup) {
        return false;
      }
      return '${e['full_name']} ${e['employee_number'] ?? ''} ${_department(e)} ${_position(e)}'
          .toLowerCase()
          .contains(query);
    }).toList();
    final hasFilters =
        query.isNotEmpty || _departmentFilter != null || _statusFilter != 'all';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select an employee',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the available credits verified on their HR leave card.',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = _filterField(
                    'Employee',
                    TextField(
                      key: const ValueKey('opening-employee-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: AppTheme.dashInputDecoration(context)
                          .copyWith(
                            hintText: 'Search name or employee number',
                            prefixIcon: const Icon(Icons.search, size: 20),
                          ),
                    ),
                  );
                  final department = _filterField(
                    'Department',
                    DropdownButtonFormField<String>(
                      key: const ValueKey('opening-department-filter'),
                      initialValue: _departmentFilter ?? '',
                      isExpanded: true,
                      menuMaxHeight: 300,
                      decoration: AppTheme.dashInputDecoration(context),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text(
                            'All departments',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...departments.map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _departmentFilter = value == '' ? null : value,
                      ),
                    ),
                  );
                  final status = _filterField(
                    'Setup status',
                    DropdownButtonFormField<String>(
                      key: const ValueKey('opening-status-filter'),
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: AppTheme.dashInputDecoration(context),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'All statuses',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'not_recorded',
                          child: Text(
                            'Not recorded',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'recorded',
                          child: Text(
                            'Recorded',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _statusFilter = value ?? 'all'),
                    ),
                  );
                  if (constraints.maxWidth < 640) {
                    return Column(
                      children: [
                        search,
                        const SizedBox(height: 12),
                        department,
                        const SizedBox(height: 12),
                        status,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: search),
                      const SizedBox(width: 12),
                      Expanded(child: department),
                      const SizedBox(width: 12),
                      Expanded(child: status),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '$recorded of ${departmentEmployees.length} opening balances recorded',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: departmentEmployees.isEmpty
                      ? 0
                      : recorded / departmentEmployees.length,
                  minHeight: 4,
                  color: AppTheme.primaryNavy,
                  backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    'Showing ${employees.length} of ${_employees.length} employees',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                  if (hasFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
        Expanded(
          child: employees.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _employees.isEmpty
                          ? 'No active employees eligible for leave credits.'
                          : 'No employees match these filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('opening-employee-list'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: employees.length,
                  itemBuilder: (_, index) => _employeeRow(employees[index]),
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppTheme.dashHairlineOf(context),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_employee == null) return _buildEmployeePicker();
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter verified available credits from the employee’s HR leave card. This is a one-time deployment setup.',
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_cutoff == null)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => _employee == null
                                  ? _loadEmployees()
                                  : _selectEmployee(_employee!),
                        child: const Text('Retry'),
                      ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_employee!['full_name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                ++_generation;
                                setState(() {
                                  _employee = null;
                                  _loading = false;
                                  _error = null;
                                });
                              },
                        child: const Text('Change employee'),
                      ),
                    ],
                  ),
                  if (_existing != null)
                    Text(
                      'Opening balances were recorded through ${_existing!['cutoff_date'].toString().substring(0, 10)}. Choose Adjust existing balance for corrections.',
                    ),
                  if (!_loading && _needsUsageVerification) ...[
                    const SizedBox(height:12),
                    const Text('Needs history review. Automatic year-end deductions are blocked until this usage is verified.'),
                    _usageFields(_existing!['cutoff_date'].toString().substring(0,4),legacy:true),
                  ],
                  if (!_loading && _existing!=null && !_needsUsageVerification)
                    Text('Verified qualifying usage: ${_existing!['qualifying_leave_days']} days in ${_existing!['cutoff_date'].toString().substring(0,4)}.'),
                  if (!_loading && _cutoff != null && _existing == null) ...[
                    if (_currentBalances != null) Text(_currentBalances!),
                    const SizedBox(height: 20),
                    const Text(
                      'Balances accounted through',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _chooseMonth,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_date(_cutoff!)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use a completed month-end. Earlier accruals and attendance deductions will not change these imported credits.',
                    ),
                    const SizedBox(height: 20),
                    _field('Available Sick Leave days', _sl, 'opening-sl'),
                    _field('Available Vacation Leave days', _vl, 'opening-vl'),
                    _usageFields(_cutoff!.year.toString()),
                    _field(
                      'Verified source / reason',
                      _reason,
                      'opening-reason',
                      days: false,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirmed,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _confirmed = v == true),
                      title: const Text(
                        'I verified the available balances and qualifying leave usage through the selected cutoff.',
                      ),
                    ),
                  ],
                  if (_loading)
                    const WorkforceRowsSkeleton(
                      columns: [1],
                      rows: 4,
                      label: 'Loading opening balance setup',
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_employee != null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed:
                    _loading || _saving || _cutoff == null || (_existing != null && !_needsUsageVerification)
                    ? null
                    : _needsUsageVerification ? _saveUsage : _save,
                child: Text(_saving ? 'Saving…' : _needsUsageVerification ? 'Save verified usage' : 'Save opening balances'),
              ),
            ),
          ),
      ],
    );
  }
}
