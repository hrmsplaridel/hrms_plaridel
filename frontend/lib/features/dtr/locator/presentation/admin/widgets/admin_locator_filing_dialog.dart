import 'dart:async';
import 'dart:convert';
import '../../shared/widgets/locator_custom_fields.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_signature_prompt.dart';
import 'package:hrms_plaridel/shared/widgets/form_settings_section.dart';
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';
import 'locator_paper_approval_fields.dart';
import 'locator_paper_employee_picker.dart';

class AdminLocatorFilingDialog extends StatefulWidget {
  const AdminLocatorFilingDialog({
    super.key,
    required this.requestTypes,
    this.approvedPaper = false,
  });
  final List<LocatorRequestType> requestTypes;
  final bool approvedPaper;
  @override
  State<AdminLocatorFilingDialog> createState() =>
      _AdminLocatorFilingDialogState();
}

class _AdminLocatorFilingDialogState extends State<AdminLocatorFilingDialog> {
  final _form = GlobalKey<FormState>();
  GlobalKey<LocatorPaperApprovalFieldsState> _paperKey =
      GlobalKey<LocatorPaperApprovalFieldsState>();
  final _originalDate = TextEditingController();
  String _paperContext = '';
  Timer? _searchDebounce;
  final _search = TextEditingController(),
      _office = TextEditingController(),
      _reason = TextEditingController();
  final _selected = <String>{};
  final _profiles = <String, Map<String, dynamic>>{};
  final _unavailable = <String>{};
  final _employeeScroll = ScrollController();
  final _detailsScroll = ScrollController();
  final _reviewScroll = ScrollController();
  final _additionalDetails = <String, dynamic>{};
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _results = [];
  late LocatorRequestType _type;
  DateTime _date = DateTime.now();
  bool _loading = false, _saving = false, _canReview = false, _created = false;
  bool _validatingEmployees = false;
  int _step = 0, _availabilityGeneration = 0;
  String? _availabilityError, _employeeError;
  final _slots = {
    'am_in': false,
    'am_out': false,
    'pm_in': false,
    'pm_out': false,
  };
  int _total = 0, _generation = 0;
  String? _error;
  PlatformFile? _attachment;
  @override
  void initState() {
    super.initState();
    _type = widget.requestTypes.first;
    _load();
    if (!widget.approvedPaper) _loadReviewer();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _office.dispose();
    _reason.dispose();
    _originalDate.dispose();
    _employeeScroll.dispose();
    _detailsScroll.dispose();
    _reviewScroll.dispose();
    super.dispose();
  }

  String get _dateString =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  Future<void> _loadReviewer() async {
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/final-reviewer/me',
      );
      if (mounted) setState(() => _canReview = r.data?['can_review'] == true);
    } catch (_) {
      /* Filing remains available with normal approval. */
    }
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _employeeError = null;
      if (!more) {
        _employees = [];
      }
    });
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/admin/filing-employees',
        queryParameters: {
          if (widget.approvedPaper)
            'paper': 'true'
          else
            'slip_date': _dateString,
          'search': _search.text.trim(),
          'offset': more ? _employees.length : 0,
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final rows = (r.data?['employees'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final employee in rows) {
          _profiles[employee['id'].toString()] = employee;
        }
        _employees = <String, Map<String, dynamic>>{
          for (final employee in [..._employees, ...rows])
            employee['id'].toString(): employee,
        }.values.toList();
        _total = (r.data?['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _employeeError = userFacingApiError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _validateSelection() {
    if (_selected.isEmpty) {
      setState(
        () => _error = widget.approvedPaper
            ? 'Select an employee.'
            : 'Select at least one employee.',
      );
      return false;
    }
    if (_validatingEmployees || _availabilityError != null) {
      setState(() => _error = 'Check employee availability before continuing.');
      return false;
    }
    if (_unavailable.isNotEmpty) {
      setState(
        () => _error =
            'Remove unavailable employees or choose another locator date.',
      );
      return false;
    }
    return true;
  }

  bool _validateDetails() {
    if (!_validateSelection()) return false;
    if (_form.currentState?.validate() != true) {
      setState(() => _error = 'Complete the required request details.');
      return false;
    }
    if (!_slots.values.any((v) => v)) {
      setState(() => _error = 'Select the covered time segments.');
      return false;
    }
    if (!widget.approvedPaper &&
        _type.requiresAttachment &&
        _attachment?.bytes == null) {
      setState(() => _error = 'Upload the required attachment.');
      return false;
    }
    return true;
  }

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (widget.approvedPaper && step == 2) {
        final contextKey =
            '${_selected.firstOrNull}/${_type.code}/${_originalDate.text}/$_dateString/${_office.text}/${_reason.text}/${jsonEncode(_slots)}/${jsonEncode(_additionalDetails)}';
        if (_paperContext != contextKey) {
          _paperContext = contextKey;
          _paperKey = GlobalKey<LocatorPaperApprovalFieldsState>();
          _attachment = null;
        }
      }
      _step = step;
      _error = null;
    });
  }

  void _continue() {
    if (_saving || _loading || _validatingEmployees) return;
    if (_step == 0 && _validateSelection()) {
      _goToStep(1);
    } else if (_step == 1 && _validateDetails()) {
      _goToStep(2);
    }
  }

  void _removeEmployee(String id) {
    setState(() {
      _selected.remove(id);
      _unavailable.remove(id);
      _error = null;
    });
  }

  Future<void> _revalidateEmployees() async {
    final generation = ++_availabilityGeneration;
    final date = _dateString;
    final ids = _selected.toList();
    if (ids.isEmpty) {
      setState(() {
        _unavailable.clear();
        _availabilityError = null;
        _validatingEmployees = false;
      });
      return;
    }
    setState(() {
      _validatingEmployees = true;
      _availabilityError = null;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/admin/filing-employees',
        queryParameters: {'slip_date': date, 'employee_ids': jsonEncode(ids)},
      );
      if (!mounted ||
          generation != _availabilityGeneration ||
          date != _dateString) {
        return;
      }
      final rows = (response.data?['employees'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final available = rows.map((e) => e['id'].toString()).toSet();
      setState(() {
        for (final employee in rows) {
          _profiles[employee['id'].toString()] = employee;
        }
        _unavailable
          ..clear()
          ..addAll(ids.where((id) => !available.contains(id)));
      });
    } catch (_) {
      if (mounted && generation == _availabilityGeneration) {
        setState(
          () => _availabilityError =
              'Unable to check selected employees for this date. Retry before continuing.',
        );
      }
    } finally {
      if (mounted && generation == _availabilityGeneration) {
        setState(() => _validatingEmployees = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showHrmsDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.approvedPaper
          ? DateTime(1900)
          : DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (!mounted || picked == null || DateUtils.isSameDay(picked, _date)) {
      return;
    }
    setState(() {
      _date = picked;
      _results = [];
    });
    if (widget.approvedPaper) {
      await _revalidateEmployees();
    } else {
      await Future.wait([_load(), _revalidateEmployees()]);
    }
  }

  Future<void> _submit() async {
    if (_saving || _loading || _validatingEmployees || !_validateDetails()) {
      return;
    }
    final paperRecord = widget.approvedPaper
        ? _paperKey.currentState?.buildRecord()
        : null;
    if (widget.approvedPaper && paperRecord == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _results = [];
    });
    try {
      Map<String, dynamic>? signature;
      if (!widget.approvedPaper && _type.autoApproveAdmin && _canReview) {
        signature = await promptLocatorSignature(context, slot: 'hr_approver');
        if (signature == null) return;
      }
      final data = <String, dynamic>{
        if (widget.approvedPaper)
          'employee_id': _selected.single
        else
          'employee_ids': jsonEncode(_selected.toList()),
        if (paperRecord != null) 'paper_approval': jsonEncode(paperRecord),
        'slip_date': _dateString,
        'request_type': _type.code,
        'office': _office.text.trim(),
        'reason': _reason.text.trim(),
        'additional_details': jsonEncode(_additionalDetails),
        'full_shift': _slots.values.every((v) => v).toString(),
        for (final slot in _slots.entries) slot.key: slot.value.toString(),
        if (signature != null) 'signature': jsonEncode(signature),
        if (_attachment?.bytes != null)
          'file': MultipartFile.fromBytes(
            _attachment!.bytes!,
            filename: _attachment!.name,
          ),
      };
      final r = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        widget.approvedPaper
            ? '/api/locator-slips/admin/approved-paper'
            : '/api/locator-slips/admin/file',
        data: FormData.fromMap(data),
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
      if (!mounted) return;
      if (widget.approvedPaper) {
        _created = true;
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _results =
            (widget.approvedPaper
                    ? [
                        {'employee_id': _selected.single, 'request': r.data},
                      ]
                    : r.data?['results'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        for (final row in _results) {
          if (row['request'] != null) {
            _selected.remove(row['employee_id']);
            _created = true;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${userFacingApiError(e)} Check request history before retrying if the connection was interrupted.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label) =>
      AppTheme.dashInputDecoration(context, labelText: label);

  Widget _section(String title, List<Widget> children) => FormSettingsSection(
    child: Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  String _employeeName(String id) =>
      _profiles[id]?['full_name']?.toString() ?? id;
  int get _successCount => _results.where((r) => r['request'] != null).length;
  int get _failureCount => _results.where((r) => r['request'] == null).length;
  bool get _busy => _saving || _loading || _validatingEmployees;
  bool get _finished => _created && _selected.isEmpty;
  String get _formattedDate =>
      MaterialLocalizations.of(context).formatMediumDate(_date);
  String get _approvalMessage {
    if (widget.approvedPaper) {
      return 'The signed paper is already approved. Recording will not send another approval request.';
    }
    if (_type.approvalWorkflowId != null) {
      return _type.autoApproveAdmin && _canReview
          ? 'Requests follow the configured workflow. Eligible requests may use your approval signature when that workflow permits it.'
          : 'Requests follow the configured approval workflow.';
    }
    if (_type.approvalRoute == 'mayor_direct') {
      return 'Requests go directly to the Mayor for approval.';
    }
    if (_type.approvalRoute == 'mayor') {
      return 'Department approval is followed by manual Mayor signing for the selected employment types.';
    }
    return _type.autoApproveAdmin && _canReview
        ? 'Eligible requests will use your approval signature. Final approval depends on each employee’s configured routing.'
        : 'Requests follow the normal department and HR approval route.';
  }

  Widget _availabilityNotice() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_validatingEmployees) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        const Text('Checking selected employees for this date…'),
      ],
      if (_availabilityError != null) ...[
        Text(
          _availabilityError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _revalidateEmployees,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry availability check'),
          ),
        ),
      ],
      for (final id in _unavailable)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_employeeName(id)} is unavailable on $_formattedDate. Remove this employee or choose another date.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _selectedEmployees({bool editable = false}) {
    if (widget.approvedPaper) {
      final id = _selected.firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (id != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                _employeeName(id),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Recording an already-approved paper locator',
              ),
            ),
          _availabilityNotice(),
        ],
      );
    }
    return _section('Selected employees (${_selected.length})', [
      if (_selected.isEmpty) const Text('No employees selected.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in _selected)
            InputChip(
              label: Text(_employeeName(id)),
              avatar: Icon(
                _unavailable.contains(id)
                    ? Icons.person_off_outlined
                    : Icons.person_outline,
                size: 18,
              ),
              deleteButtonTooltipMessage: 'Remove ${_employeeName(id)}',
              onDeleted: editable && !_busy ? () => _removeEmployee(id) : null,
            ),
        ],
      ),
      if (!editable && !_finished)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : () => _goToStep(0),
            icon: const Icon(Icons.people_outline, size: 18),
            label: const Text('Change employees'),
          ),
        ),
      _availabilityNotice(),
    ]);
  }

  Widget _employeeStep() => ListView(
    controller: _employeeScroll,
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        widget.approvedPaper
            ? 'Choose the employee for this signed paper locator. Record one original document at a time.'
            : 'Choose the employees to file for. The same request details will apply to everyone selected.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _saving || _validatingEmployees ? null : _pickDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text('Locator date: $_formattedDate'),
        ),
      ),
      Text(
        'Employees are listed based on the selected date.',
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
      const SizedBox(height: 12),
      if (_selected.isNotEmpty) ...[
        _selectedEmployees(editable: true),
        const SizedBox(height: 16),
      ],
      _section('Employees', [
        TextField(
          key: const ValueKey('locator-filing-search'),
          controller: _search,
          enabled: !_saving,
          decoration: _decoration('Search employee or department'),
          onSubmitted: (_) {
            if (!_busy) _load();
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _load(),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Search'),
          ),
        ),
        Text(
          '${_selected.length} selected · ${_employees.length} of $_total employees',
        ),
        if (!widget.approvedPaper)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      for (final employee in _employees) {
                        if (_selected.length >= 100) break;
                        _selected.add(employee['id'].toString());
                      }
                      _error = null;
                    }),
              child: const Text('Select loaded employees (up to 100)'),
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_employeeError != null) ...[
          Text(
            _employeeError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: _busy ? null : () => _load(),
            child: const Text('Retry employees'),
          ),
        ],
        if (!_loading && _employeeError == null && _employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No employees match this date or search.'),
          ),
        ..._employees.map(
          (employee) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(employee['full_name']?.toString() ?? 'Employee'),
            subtitle: Text(employee['department_name']?.toString() ?? ''),
            value: _selected.contains(employee['id'].toString()),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    final id = employee['id'].toString();
                    if (value == true && _selected.length < 100) {
                      if (widget.approvedPaper) {
                        _selected.clear();
                        _unavailable.clear();
                      }
                      _selected.add(id);
                    } else if (value != true) {
                      _selected.remove(id);
                      _unavailable.remove(id);
                    }
                    _error = null;
                  }),
          ),
        ),
        if (_employees.length < _total)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('Load more employees'),
          ),
      ]),
    ],
  );

  Widget _detailsStep() => Form(
    key: _form,
    child: SingleChildScrollView(
      controller: _detailsScroll,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _selectedEmployees(),
          const SizedBox(height: 16),
          if (widget.approvedPaper) ...[
            const Text(
              'Locator Details',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Copy the locator type, date, destination and covered time segments from the signed paper.',
            ),
            const SizedBox(height: 20),
          ],
          _section(widget.approvedPaper ? 'Locator details' : 'Request details', [
            InkWell(
              key: const ValueKey('locator-filing-date'),
              onTap: _saving || _validatingEmployees ? null : _pickDate,
              child: InputDecorator(
                decoration: _decoration('Locator Date').copyWith(
                  suffixIcon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                  ),
                ),
                child: Text(_formattedDate),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.approvedPaper) ...[
              TextFormField(
                key: const ValueKey('locator-paper-original-date'),
                controller: _originalDate,
                decoration: _decoration('Original filing date').copyWith(
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: () async {
                      final today = DateUtils.dateOnly(DateTime.now());
                      final value = await showHrmsDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse(
                                  _originalDate.text,
                                )?.isAfter(today) ==
                                false
                            ? DateTime.parse(_originalDate.text)
                            : today,
                        firstDate: DateTime(1900),
                        lastDate: today,
                      );
                      if (value != null && mounted) {
                        setState(
                          () => _originalDate.text = value
                              .toIso8601String()
                              .substring(0, 10),
                        );
                      }
                    },
                  ),
                ),
                validator: (value) {
                  final text = value ?? '', date = DateTime.tryParse(text);
                  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                          date != null &&
                          date.toIso8601String().substring(0, 10) == text
                      ? null
                      : 'Enter the original filing date (YYYY-MM-DD).';
                },
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<LocatorRequestType>(
              initialValue: _type,
              isExpanded: true,
              decoration: _decoration('Request Type'),
              items: widget.requestTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (type) => setState(() {
                      _type = type!;
                      _additionalDetails.clear();
                      _attachment = null;
                      _results = [];
                      _error = null;
                    }),
            ),
            const SizedBox(height: 12),
            Text(_approvalMessage),
            const SizedBox(height: 16),
            const Text('Covered DTR slots'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots.entries)
                  FilterChip(
                    label: Text(slot.key.toUpperCase().replaceAll('_', ' ')),
                    selected: slot.value,
                    onSelected: _saving
                        ? null
                        : (value) => setState(() => _slots[slot.key] = value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the slots to cover. Selecting all four covers the full shift, including IN/OUT for single-session employees.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('locator-filing-destination'),
              controller: _office,
              enabled: !_saving,
              decoration: _decoration(_type.locationLabel),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter the destination' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('locator-filing-reason'),
              controller: _reason,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: _decoration('Purpose / Reason'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter the reason' : null,
            ),
            if (_type.employeeDetailSchema.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: LocatorCustomFieldInputs(
                    key: ValueKey('fields-${_type.code}'),
                    fields: _type.employeeDetailSchema,
                    values: _additionalDetails,
                  ),
                ),
              ),
            if (!widget.approvedPaper && _type.requiresAttachment)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                            withData: true,
                          );
                          if (result != null && mounted) {
                            setState(() => _attachment = result.files.single);
                          }
                        },
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _attachment?.name ?? 'Upload required attachment',
                  ),
                ),
              ),
          ]),
        ],
      ),
    ),
  );

  Widget _reviewLine(String label, String value) => Padding(
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
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _reviewStep() => SingleChildScrollView(
    controller: _reviewScroll,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.approvedPaper)
          const Text(
            'Review the employees and request details before filing. Each employee receives a separate request.',
          ),
        const SizedBox(height: 16),
        _selectedEmployees(),
        const SizedBox(height: 16),
        if (widget.approvedPaper)
          AbsorbPointer(
            absorbing: _saving,
            child: LocatorPaperApprovalFields(
              key: _paperKey,
              employeeId: _selected.firstOrNull ?? '',
              requestType: _type.code,
              filingDate: _originalDate.text,
              onAttachment: (file) => setState(() => _attachment = file),
            ),
          ),
        _section(
          widget.approvedPaper ? 'Paper locator summary' : 'Request summary',
          [
            _reviewLine('Locator date', _formattedDate),
            _reviewLine('Request type', _type.label),
            _reviewLine(
              'Covered DTR slots',
              _slots.entries
                  .where((slot) => slot.value)
                  .map((slot) => slot.key.toUpperCase().replaceAll('_', ' '))
                  .join(', '),
            ),
            _reviewLine(_type.locationLabel, _office.text.trim()),
            _reviewLine('Purpose / Reason', _reason.text.trim()),
            for (final line in locatorAdditionalFieldLines(
              _type.employeeDetailSchema,
              _additionalDetails,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
            if (_attachment != null)
              _reviewLine('Attachment', _attachment!.name),
          ],
        ),
        const SizedBox(height: 16),
        if (!widget.approvedPaper)
          _section('Approval', [Text(_approvalMessage)]),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section('Filing results', [
            for (final result in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_employeeName(result['employee_id'].toString())),
                subtitle: Text(
                  result['error']?.toString() ??
                      'Created: ${result['request']['status']}',
                ),
                trailing: Icon(
                  result['request'] == null
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: result['request'] == null
                      ? Theme.of(context).colorScheme.error
                      : Colors.green,
                ),
              ),
          ]),
        ],
      ],
    ),
  );

  Widget _footer() {
    final nextLabel = _step == 0
        ? 'Continue'
        : _step == 1
        ? (widget.approvedPaper
              ? 'Continue to paper approval'
              : 'Review requests')
        : _finished
        ? 'Done'
        : widget.approvedPaper
        ? 'Record approved locator'
        : _results.isNotEmpty
        ? 'Retry failed requests'
        : 'File requests';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_step == 2 && _results.isNotEmpty) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '$_successCount ${_successCount == 1 ? 'request' : 'requests'} filed successfully · $_failureCount failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _failureCount > 0
                          ? Colors.deepOrange
                          : Colors.green,
                    ),
                  ),
                ),
                if (_failureCount > 0)
                  const Text(
                    'Failed employees remain selected. Review Filing results below before retrying.',
                  ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  if (_step > 0 && !widget.approvedPaper) ...[
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              _goToStep(_step - 1);
                            },
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : _step < 2
                            ? _continue
                            : _finished
                            ? () => Navigator.pop(context, _created)
                            : _submit,
                        icon: Icon(
                          _step < 2
                              ? Icons.arrow_forward
                              : _finished
                              ? Icons.check
                              : Icons.send_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _saving
                              ? (widget.approvedPaper
                                    ? 'Recording…'
                                    : 'Filing…')
                              : nextLabel,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPaperEmployee(Map<String, dynamic> employee) {
    _searchDebounce?.cancel();
    final id = employee['id'].toString();
    if (_selected.firstOrNull != id) {
      _office.clear();
      _reason.clear();
      _originalDate.clear();
      _additionalDetails.clear();
      _slots.updateAll((_, _) => false);
      _paperContext = '';
      _paperKey = GlobalKey<LocatorPaperApprovalFieldsState>();
      _attachment = null;
      _results = [];
      _unavailable.clear();
      _availabilityError = null;
    }
    _selected
      ..clear()
      ..add(id);
    _goToStep(1);
  }

  Widget _paperStepBody(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );

  Widget _paperRecording() => Scaffold(
    backgroundColor: AppTheme.dashPanelOf(context),
    appBar: AppBar(
      title: Text(
        _step == 2
            ? 'Original Paper Approval'
            : 'Record approved paper locator',
      ),
      automaticallyImplyLeading: false,
      leading: _step == 0
          ? null
          : IconButton(
              tooltip: _step == 1
                  ? 'Back to employee selection'
                  : 'Back to locator details',
              onPressed: _saving || _validatingEmployees
                  ? null
                  : () => _goToStep(_step - 1),
              icon: const Icon(Icons.arrow_back),
            ),
      actions: [
        IconButton(
          tooltip: 'Close filing',
          onPressed: _saving ? null : () => Navigator.pop(context, _created),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: IndexedStack(
      index: _step,
      children: [
        LocatorPaperEmployeePicker(
          search: _search,
          scrollController: _employeeScroll,
          employees: _employees,
          total: _total,
          loading: _loading,
          error: _employeeError,
          onSearchChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(
              const Duration(milliseconds: 300),
              () => _load(),
            );
          },
          onSearch: () {
            _searchDebounce?.cancel();
            _load();
          },
          onLoadMore: () => _load(more: true),
          onSelect: _selectPaperEmployee,
        ),
        _paperStepBody('Step 2 of 3 • Locator details', _detailsStep()),
        _paperStepBody('Step 3 of 3 • Paper approval', _reviewStep()),
      ],
    ),
    bottomNavigationBar: _step == 0 ? null : _footer(),
  );

  @override
  Widget build(BuildContext context) => widget.approvedPaper
      ? _paperRecording()
      : Scaffold(
          backgroundColor: AppTheme.dashPanelOf(context),
          appBar: AppBar(
            title: Text(
              widget.approvedPaper
                  ? 'Record approved paper locator'
                  : 'File locator for employees',
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                tooltip: 'Close filing',
                onPressed: _saving
                    ? null
                    : () => Navigator.pop(context, _created),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Step ${_step + 1} of 3 • ${['Employees', 'Request details', 'Review and submit'][_step]}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var index = 0; index < 3; index++) ...[
                          if (index > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: index <= _step
                                    ? Theme.of(context).colorScheme.primary
                                    : AppTheme.dashHairlineOf(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _step,
                  children: [_employeeStep(), _detailsStep(), _reviewStep()],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _footer(),
        );
}
