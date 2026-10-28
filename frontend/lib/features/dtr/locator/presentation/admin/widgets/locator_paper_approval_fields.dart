import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/widgets/form_settings_section.dart';
import 'package:hrms_plaridel/shared/widgets/hrms_date_picker.dart';

class LocatorPaperApprovalFields extends StatefulWidget {
  const LocatorPaperApprovalFields({
    super.key,
    required this.employeeId,
    required this.requestType,
    required this.filingDate,
    required this.onAttachment,
  });
  final String employeeId, requestType, filingDate;
  final ValueChanged<PlatformFile?> onAttachment;
  @override
  State<LocatorPaperApprovalFields> createState() =>
      LocatorPaperApprovalFieldsState();
}

class LocatorPaperApprovalFieldsState
    extends State<LocatorPaperApprovalFields> {
  final _form = GlobalKey<FormState>();
  final _approval = TextEditingController(), _notes = TextEditingController();
  final _names = {
    for (final key in ['final_approver', 'department_reviewer'])
      key: TextEditingController(),
  };
  final _titles = {
    for (final key in ['final_approver', 'department_reviewer'])
      key: TextEditingController(),
  };
  final _selected = <String, String?>{};
  Map<String, dynamic> _choices = {};
  bool _complete = false, _notRecorded = false, _loading = false;
  int _serial = 0;
  String? _lookupError, _error;
  PlatformFile? _file;
  @override
  void dispose() {
    _serial++;
    _approval.dispose();
    _notes.dispose();
    for (final c in [..._names.values, ..._titles.values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validDate(String text) {
    final d = DateTime.tryParse(text);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
        d != null &&
        d.toIso8601String().substring(0, 10) == text;
  }

  Future<void> _load({bool reset = true}) async {
    final serial = ++_serial;
    if (reset) {
      setState(() {
        _loading = false;
        _lookupError = null;
        _complete = false;
        _notRecorded = false;
        for (final key in _names.keys) {
          if (_selected[key] != 'other') {
            _selected[key] = null;
            _names[key]!.clear();
            _titles[key]!.clear();
          }
        }
        _choices = {};
      });
    }
    if (!_validDate(_approval.text) ||
        !_validDate(widget.filingDate) ||
        widget.employeeId.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _lookupError = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/admin/paper-signatories',
        queryParameters: {
          'employee_id': widget.employeeId,
          'request_type': widget.requestType,
          'filing_date': widget.filingDate,
          'approval_date': _approval.text,
        },
      );
      if (!mounted || serial != _serial) return;
      setState(() => _choices = response.data ?? {});
    } catch (_) {
      if (mounted && serial == _serial) {
        setState(
          () => _lookupError =
              'Unable to load signatory suggestions. Retry or choose Other signatory.',
        );
      }
    } finally {
      if (mounted && serial == _serial) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? buildRecord() {
    if (_form.currentState?.validate() != true) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    if (!_validDate(widget.filingDate) ||
        widget.filingDate.compareTo(_approval.text) > 0 ||
        DateTime.parse(_approval.text).isAfter(today)) {
      setState(
        () => _error =
            'Original filing must be on or before approval, and approval cannot be in the future.',
      );
      return null;
    }
    if (_file?.bytes?.isNotEmpty != true) {
      setState(() => _error = 'Upload the signed original paper locator.');
      return null;
    }
    if (!_complete || !_notRecorded) {
      setState(
        () => _error =
            'Confirm the signed paper is complete and has not already been recorded.',
      );
      return null;
    }
    Map<String, dynamic>? person(String group) {
      if (_names[group]!.text.trim().isEmpty) return null;
      final rows = (_choices[group] as List? ?? []).whereType<Map>();
      final selected = rows
          .where((r) => r['user_id'] == _selected[group])
          .firstOrNull;
      return {
        'name': _names[group]!.text.trim(),
        'position_title': _titles[group]!.text.trim(),
        if (selected != null) 'user_id': selected['user_id'],
      };
    }

    return {
      'original_filing_date': widget.filingDate,
      'approval_date': _approval.text,
      'final_approver': person('final_approver'),
      'department_reviewer': person('department_reviewer'),
      'additional_approvers': _notes.text.trim(),
      'confirmed_complete': true,
      'confirmed_not_recorded': true,
    };
  }

  Widget _field(String label, Widget input) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Text(label), const SizedBox(height: 8), input],
    ),
  );
  InputDecoration get _decoration => AppTheme.dashInputDecoration(context);
  Widget _official(String group, String label, {bool required = false}) {
    final choices = (_choices[group] as List? ?? []).whereType<Map>().toList();
    final selected = choices
        .where((r) => r['user_id'] == _selected[group])
        .firstOrNull;
    return FormSettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: ValueKey('$group-$_serial'),
            child: DropdownButtonFormField<String>(
              key: ValueKey('paper-$group-picker'),
              initialValue: _selected[group],
              isExpanded: true,
              decoration: _decoration.copyWith(
                hintText: required
                    ? 'Select the actual signer'
                    : 'Not shown on paper',
              ),
              items: [
                if (!required)
                  const DropdownMenuItem(
                    value: 'none',
                    child: Text('Not shown on paper'),
                  ),
                for (final row in choices)
                  DropdownMenuItem(
                    value: row['user_id'].toString(),
                    child: Text(
                      '${row['name']} · ${row['reviewer_role'] == 'backup' ? 'Backup' : 'Primary'}',
                    ),
                  ),
                const DropdownMenuItem(
                  value: 'other',
                  child: Text('Other signatory'),
                ),
              ],
              onChanged: (value) => setState(() {
                _selected[group] = value;
                final person = choices
                    .where((r) => r['user_id'] == value)
                    .firstOrNull;
                _names[group]!.text = person?['name']?.toString() ?? '';
                _titles[group]!.text =
                    person?['position_title']?.toString() ?? '';
                _complete = false;
                _notRecorded = false;
              }),
              validator: (value) =>
                  required && (value == null || value == 'none')
                  ? 'Choose the official who signed the paper.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          if (_selected[group] != null && _selected[group] != 'none') ...[
            _field(
              'Name on paper',
              TextFormField(
                key: ValueKey('paper-$group-name'),
                controller: _names[group],
                readOnly: selected != null,
                decoration: _decoration,
                maxLength: 200,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter the name on paper.'
                    : null,
              ),
            ),
            _field(
              'Position / designation',
              TextFormField(
                key: ValueKey('paper-$group-title'),
                controller: _titles[group],
                readOnly:
                    selected != null &&
                    (selected['position_title']?.toString() ?? '').isNotEmpty,
                decoration: _decoration,
                maxLength: 200,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter the position on paper.'
                    : null,
              ),
            ),
            Text(
              selected == null
                  ? 'Manually entered names remain unsigned on generated copies.'
                  : selected['has_saved_signature'] == true
                  ? 'This account’s saved signature will be copied when recording.'
                  : 'No saved signature is available; the signature line will stay blank.',
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Record the approvals already completed on paper. HR is the encoder; no further approval routing is added. The employee’s saved signature is copied when available.',
        ),
        const SizedBox(height: 16),
        _field(
          'Final paper approval date',
          TextFormField(
            key: const ValueKey('locator-paper-approval-date'),
            controller: _approval,
            decoration: _decoration.copyWith(
              hintText: 'YYYY-MM-DD',
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final value = await showHrmsDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(_approval.text)?.isAfter(today) ==
                            false
                        ? DateTime.parse(_approval.text)
                        : today,
                    firstDate: DateTime(1900),
                    lastDate: today,
                  );
                  if (value != null && mounted) {
                    _approval.text = value.toIso8601String().substring(0, 10);
                    await _load();
                  }
                },
              ),
            ),
            onChanged: (_) => _load(),
            validator: (value) => _validDate(value ?? '')
                ? null
                : 'Enter a valid approval date (YYYY-MM-DD).',
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_lookupError != null) ...[
          Text(_lookupError!),
          TextButton(
            onPressed: () => _load(reset: false),
            child: const Text('Retry suggestions'),
          ),
        ],
        for (final warning in (_choices['warnings'] as List? ?? []))
          Text(warning.toString()),
        _official(
          'final_approver',
          'Final approving official • Required',
          required: true,
        ),
        const SizedBox(height: 16),
        _official(
          'department_reviewer',
          'Recommending / department official • Optional',
        ),
        const SizedBox(height: 16),
        _field(
          'Other paper approval details',
          TextFormField(
            controller: _notes,
            decoration: _decoration,
            maxLines: 3,
            maxLength: 2000,
          ),
        ),
        FormSettingsSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.upload_file_outlined, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Signed original • Required',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload the fully signed paper locator and its supporting documents. PDF, PNG or JPG, up to 10 MB.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                    withData: true,
                  );
                  if (picked == null || !mounted) return;
                  final file = picked.files.single;
                  if (file.bytes?.isNotEmpty != true ||
                      file.bytes!.length > 10 * 1024 * 1024) {
                    setState(
                      () => _error = 'Upload a PDF or image up to 10 MB.',
                    );
                    return;
                  }
                  setState(() {
                    _file = file;
                    _error = null;
                  });
                  widget.onAttachment(file);
                },
                icon: const Icon(Icons.upload_file),
                label: Text(_file?.name ?? 'Upload signed original'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('locator-paper-complete'),
          contentPadding: EdgeInsets.zero,
          value: _complete,
          onChanged: (v) => setState(() => _complete = v == true),
          title: const Text(
            'I verified the employee signature and all required approvals on the signed original.',
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('locator-paper-not-recorded'),
          contentPadding: EdgeInsets.zero,
          value: _notRecorded,
          onChanged: (v) => setState(() => _notRecorded = v == true),
          title: const Text(
            'I verified this locator has not already been recorded in the system.',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
