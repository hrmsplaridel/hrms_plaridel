import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';

class AdminLocatorCorrectionDraft {
  const AdminLocatorCorrectionDraft({
    required this.employeeId,
    required this.date,
    required this.requestType,
    required this.office,
    required this.reason,
    required this.correctionReason,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    this.attachmentBytes,
    this.attachmentName,
  });

  final String employeeId;
  final DateTime date;
  final LocatorRequestType requestType;
  final String office;
  final String reason;
  final String correctionReason;
  final bool amIn;
  final bool amOut;
  final bool pmIn;
  final bool pmOut;
  final List<int>? attachmentBytes;
  final String? attachmentName;
}

class AdminLocatorCorrectionDialog extends StatefulWidget {
  const AdminLocatorCorrectionDialog({super.key, required this.requestTypes});

  final List<LocatorRequestType> requestTypes;

  @override
  State<AdminLocatorCorrectionDialog> createState() =>
      _AdminLocatorCorrectionDialogState();
}

class _AdminLocatorCorrectionDialogState
    extends State<AdminLocatorCorrectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _officeController = TextEditingController();
  final _reasonController = TextEditingController();
  final _correctionController = TextEditingController();
  List<_EmployeeOption> _employees = const [];
  String? _employeeId;
  late LocatorRequestType _requestType;
  DateTime _date = DateTime.now().subtract(const Duration(days: 1));
  bool _amIn = false;
  bool _amOut = false;
  bool _pmIn = false;
  bool _pmOut = false;
  bool _loadingEmployees = true;
  String? _loadError;
  List<int>? _attachmentBytes;
  String? _attachmentName;

  @override
  void initState() {
    super.initState();
    _requestType = widget.requestTypes.isNotEmpty
        ? widget.requestTypes.first
        : LocatorRequestType.locator;
    _loadEmployees();
  }

  @override
  void dispose() {
    _officeController.dispose();
    _reasonController.dispose();
    _correctionController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final response = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: const {'limit': 500, 'offset': 0},
      );
      final data = response.data;
      final rows = data is Map
          ? (data['employees'] as List<dynamic>? ?? const [])
          : data is List
          ? data
          : const <dynamic>[];
      final employees =
          rows
              .whereType<Map>()
              .map(
                (row) => _EmployeeOption(
                  id: (row['id'] ?? '').toString(),
                  name: (row['full_name'] ?? 'Employee').toString(),
                ),
              )
              .where((employee) => employee.id.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loadingEmployees = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingEmployees = false;
        _loadError = 'Unable to load employees: $error';
      });
    }
  }

  InputDecoration _decoration(String label, {String? hint}) =>
      AppTheme.dashInputDecoration(
        context,
      ).copyWith(labelText: label, hintText: hint);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashPanelOf(context),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppTheme.dashPanelOf(context),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.edit_calendar_outlined),
            SizedBox(width: 10),
            Expanded(child: Text('Record Locator Correction')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadError != null)
                  Text(_loadError!, style: const TextStyle(color: Colors.red)),
                DropdownButtonFormField<String>(
                  initialValue: _employeeId,
                  isExpanded: true,
                  decoration: _decoration('Employee'),
                  items: _employees
                      .map(
                        (employee) => DropdownMenuItem(
                          value: employee.id,
                          child: Text(employee.name),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingEmployees
                      ? null
                      : (value) => setState(() => _employeeId = value),
                  validator: (value) =>
                      value == null ? 'Select an employee' : null,
                ),
                const SizedBox(height: 12),
                _dateField(),
                const SizedBox(height: 12),
                DropdownButtonFormField<LocatorRequestType>(
                  initialValue: _requestType,
                  isExpanded: true,
                  decoration: _decoration('Request Type'),
                  items: widget.requestTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _requestType = value;
                      if (value.usesWfhCoverage) {
                        _amIn = _amOut = _pmIn = _pmOut = true;
                      }
                      if (!value.requiresAttachment) {
                        _attachmentBytes = null;
                        _attachmentName = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Covered DTR slots',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _slot('AM IN', _amIn, (value) => _amIn = value),
                    _slot('AM OUT', _amOut, (value) => _amOut = value),
                    _slot('PM IN', _pmIn, (value) => _pmIn = value),
                    _slot('PM OUT', _pmOut, (value) => _pmOut = value),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _officeController,
                  decoration: _decoration(
                    _requestType.locationLabel,
                    hint: _requestType.locationHint,
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _decoration('Purpose / Reason'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _correctionController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: _decoration(
                    'Correction or Emergency Reason',
                    hint:
                        'Explain why this past locator is being recorded by HR.',
                  ),
                  validator: (value) => (value ?? '').trim().length < 10
                      ? 'Enter at least 10 characters'
                      : null,
                ),
                if (_requestType.requiresAttachment) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _attachmentName ?? 'Upload required attachment',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            border: Border(
              top: BorderSide(color: AppTheme.dashHairlineOf(context)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Record Correction'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField() => InkWell(
    onTap: () async {
      final now = DateTime.now();
      final latestCorrectionDate = now.subtract(const Duration(days: 1));
      final picked = await showHrmsDatePicker(
        context: context,
        initialDate: _date.isAfter(latestCorrectionDate)
            ? latestCorrectionDate
            : _date,
        firstDate: DateTime(2000),
        lastDate: latestCorrectionDate,
        helpText: 'Select correction date',
      );
      if (picked != null) setState(() => _date = picked);
    },
    child: InputDecorator(
      decoration: _decoration('Locator Date'),
      child: Text(MaterialLocalizations.of(context).formatMediumDate(_date)),
    ),
  );

  Widget _slot(String label, bool value, ValueChanged<bool> assign) =>
      FilterChip(
        selected: value,
        label: Text(label),
        onSelected: (selected) => setState(() => assign(selected)),
      );

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Required' : null;

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file?.bytes == null) return;
    setState(() {
      _attachmentBytes = file!.bytes;
      _attachmentName = file.name;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final isToday =
        _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
    if (isToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use the normal employee filing and approval workflow for today.',
          ),
        ),
      );
      return;
    }
    if (!(_amIn || _amOut || _pmIn || _pmOut)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one DTR slot.')),
      );
      return;
    }
    if (_requestType.requiresAttachment && _attachmentBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload the required attachment.')),
      );
      return;
    }
    Navigator.of(context).pop(
      AdminLocatorCorrectionDraft(
        employeeId: _employeeId!,
        date: _date,
        requestType: _requestType,
        office: _officeController.text.trim(),
        reason: _reasonController.text.trim(),
        correctionReason: _correctionController.text.trim(),
        amIn: _amIn,
        amOut: _amOut,
        pmIn: _pmIn,
        pmOut: _pmOut,
        attachmentBytes: _attachmentBytes,
        attachmentName: _attachmentName,
      ),
    );
  }
}

class _EmployeeOption {
  const _EmployeeOption({required this.id, required this.name});

  final String id;
  final String name;
}
