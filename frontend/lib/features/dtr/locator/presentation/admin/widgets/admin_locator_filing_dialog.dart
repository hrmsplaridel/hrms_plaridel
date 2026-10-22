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

class AdminLocatorFilingDialog extends StatefulWidget {
  const AdminLocatorFilingDialog({super.key, required this.requestTypes});
  final List<LocatorRequestType> requestTypes;
  @override
  State<AdminLocatorFilingDialog> createState() =>
      _AdminLocatorFilingDialogState();
}

class _AdminLocatorFilingDialogState extends State<AdminLocatorFilingDialog> {
  final _form = GlobalKey<FormState>();
  final _search = TextEditingController(),
      _office = TextEditingController(),
      _reason = TextEditingController();
  final _selected = <String>{};
  final _additionalDetails = <String,dynamic>{};
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _results = [];
  late LocatorRequestType _type;
  DateTime _date = DateTime.now();
  bool _loading = false, _saving = false, _canReview = false, _created = false;
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
    _loadReviewer();
  }

  @override
  void dispose() {
    _search.dispose();
    _office.dispose();
    _reason.dispose();
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
      _error = null;
      if (!more) {
        _employees = [];
        _selected.clear();
      }
    });
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/admin/filing-employees',
        queryParameters: {
          'slip_date': _dateString,
          'search': _search.text.trim(),
          'offset': more ? _employees.length : 0,
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _employees.addAll(
          (r.data?['employees'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        _total = (r.data?['total'] as num?)?.toInt() ?? 0;
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

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one employee.');
      return;
    }
    if (!_slots.values.any((v) => v)) {
      setState(() => _error = 'Select the covered time segments.');
      return;
    }
    if (_type.requiresAttachment && _attachment?.bytes == null) {
      setState(() => _error = 'Upload the required attachment.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _results = [];
    });
    try {
      Map<String, dynamic>? signature;
      if (_type.autoApproveAdmin && _canReview) {
        signature = await promptLocatorSignature(context, slot: 'hr_approver');
        if (signature == null) return;
      }
      final data = <String, dynamic>{
        'employee_ids': jsonEncode(_selected.toList()),
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
        '/api/locator-slips/admin/file',
        data: FormData.fromMap(data),
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
      if (!mounted) return;
      setState(() {
        _results = (r.data?['results'] as List? ?? [])
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
      _employees
          .where((e) => e['id'] == id)
          .firstOrNull?['full_name']
          ?.toString() ??
      id;
  int get _successCount => _results.where((r) => r['request'] != null).length;
  int get _failureCount => _results.length - _successCount;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.dashPanelOf(context),
    appBar: AppBar(
      title: const Text('File locator for employees'),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          onPressed: _saving ? null : () => Navigator.pop(context, _created),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _section('Request details', [
            InkWell(
              onTap: _saving
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final picked = await showHrmsDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: DateTime(now.year + 1, 12, 31),
                      );
                      if (picked != null && mounted) {
                        setState(() => _date = picked);
                        _load();
                      }
                    },
              child: InputDecorator(
                decoration: _decoration('Locator Date'),
                child: Text(
                  MaterialLocalizations.of(context).formatMediumDate(_date),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<LocatorRequestType>(
              initialValue: _type,
              isExpanded: true,
              decoration: _decoration('Request Type'),
              items: widget.requestTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (t) => setState(() {
                      _type = t!;
                      _additionalDetails.clear();
                      _attachment = null;
                    }),
            ),
            const SizedBox(height: 12),
            Text(
              _type.approvalRoute == 'mayor_direct'
                  ? 'Requests go directly to the Mayor for approval.'
                  : _type.approvalRoute == 'mayor'
                  ? 'Department approval is followed by manual Mayor signing for the selected employment types.'
                  : _type.autoApproveAdmin && _canReview
                  ? 'Valid requests will be approved using your signature.'
                  : 'Requests follow the normal department and HR approval route.',
            ),
            const SizedBox(height: 12),
            const Text('Covered DTR slots'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _slots.entries
                  .map(
                    (s) => FilterChip(
                      label: Text(s.key.toUpperCase().replaceAll('_', ' ')),
                      selected: s.value,
                      onSelected: _saving
                          ? null
                          : (v) => setState(() => _slots[s.key] = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the slots to cover. Selecting all four covers the full shift, including IN/OUT for single-session employees.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _office,
              enabled: !_saving,
              decoration: _decoration(_type.locationLabel),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the destination' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: _decoration('Purpose / Reason'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the reason' : null,
            ),
            if (_type.employeeDetailSchema.isNotEmpty) Padding(
              padding:const EdgeInsets.only(top:12),
              child:AbsorbPointer(absorbing:_saving,child:LocatorCustomFieldInputs(
                key:ValueKey('fields-${_type.code}'),fields:_type.employeeDetailSchema,values:_additionalDetails,
              )),
            ),
            if (_type.requiresAttachment)
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final r = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                          withData: true,
                        );
                        if (r != null && mounted) {
                          setState(() => _attachment = r.files.single);
                        }
                      },
                child: Text(_attachment?.name ?? 'Upload required attachment'),
              ),
          ]),
          const SizedBox(height: 16),
          _section('Employees', [
            TextField(
              controller: _search,
              enabled: !_saving,
              decoration: _decoration('Search employee or department'),
              onSubmitted: (_) => _load(),
            ),
            TextButton(
              onPressed: _saving || _loading ? null : () => _load(),
              child: const Text('Search'),
            ),
            Text(
              '${_selected.length} selected · ${_employees.length} of $_total employees',
            ),
            TextButton(
              onPressed: _saving || _loading
                  ? null
                  : () => setState(() {
                      for (final e in _employees) {
                        if (_selected.length >= 100) break;
                        _selected.add(e['id'].toString());
                      }
                    }),
              child: const Text('Select loaded employees (up to 100)'),
            ),
            if (_loading) const LinearProgressIndicator(),
            ..._employees.map(
              (e) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e['full_name']?.toString() ?? 'Employee'),
                subtitle: Text(e['department_name']?.toString() ?? ''),
                value: _selected.contains(e['id']),
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        if (v == true && _selected.length < 100) {
                          _selected.add(e['id'].toString());
                        } else {
                          _selected.remove(e['id']);
                        }
                      }),
              ),
            ),
            if (_employees.length < _total)
              TextButton(
                onPressed: _loading || _saving ? null : () => _load(more: true),
                child: const Text('Load more employees'),
              ),
          ]),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(
              'Filing results',
              _results
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_employeeName(r['employee_id'].toString())),
                      subtitle: Text(
                        r['error']?.toString() ??
                            'Created: ${r['request']['status']}',
                      ),
                      trailing: Text(r['error'] != null ? 'Failed' : 'Created'),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_results.isNotEmpty) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  '$_successCount ${_successCount == 1 ? 'request' : 'requests'} filed successfully · $_failureCount failed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _failureCount > 0 ? Colors.deepOrange : Colors.green,
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, _created),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving || _loading ? null : _submit,
                  child: Text(_saving ? 'Filing…' : 'File requests'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
