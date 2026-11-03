import 'package:file_picker/file_picker.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_review_dialogs.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';

/// Staff filing uses the complete leave form with a separate employee context.
class AdminLeaveFilingPanel extends StatefulWidget {
  const AdminLeaveFilingPanel({super.key});
  @override
  State<AdminLeaveFilingPanel> createState() => _AdminLeaveFilingPanelState();
}

class _AdminLeaveFilingPanelState extends State<AdminLeaveFilingPanel> {
  final _search = TextEditingController();
  final _employees = <AppUser>[];
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  int _total = 0;
  int _serial = 0;
  AppUser? _selected;
  final _paperKey = GlobalKey<FormState>();
  final _paperFields = {
    for (final key in [
      'original_filing_date',
      'approval_date',
      'final_name',
      'final_title',
      'cert_name',
      'cert_title',
      'dept_name',
      'dept_title',
      'additional',
    ])
      key: TextEditingController(),
  };
  bool _confirmedComplete = false;
  bool _confirmedNotRecorded = false;
  Map<String, dynamic>? _paperApproval;
  LeaveRequest? _pendingRequest;
  Completer<bool>? _paperStep;
  bool _reviewingPaper = false;
  bool _savingPaper = false;
  List<int>? _signedBytes;
  String? _signedName;
  final _signatoryChoices = <String, List<Map<String, dynamic>>>{};
  final _selectedSigners = <String, String?>{};
  static const _signerFields = {
    'final_approver': ['final_name', 'final_title'],
    'certification_officer': ['cert_name', 'cert_title'],
    'department_reviewer': ['dept_name', 'dept_title'],
  };
  bool _loadingSigners = false;
  String? _signerError;
  String? _signerContext;
  String? _signerDate;
  List<String> _signerWarnings = [];
  int _signerSerial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_paperStep?.isCompleted == false) _paperStep!.complete(false);
    _search.dispose();
    for (final controller in _paperFields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      return data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Unable to contact the leave service. Please retry.';
    }
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<void> _load({bool more = false}) async {
    final serial = ++_serial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/admin/filing-employees',
        queryParameters: {
          'search': _search.text.trim(),
          'offset': more ? _employees.length : 0,
        },
      );
      if (!mounted || serial != _serial) return;
      final data = response.data ?? {};
      final rows = (data['employees'] as List? ?? []).whereType<Map>().map(
        (row) => AppUser.fromJson(Map<String, dynamic>.from(row)),
      );
      setState(() {
        if (!more) _employees.clear();
        _employees.addAll(rows);
        _total = (data['total'] as num?)?.toInt() ?? _employees.length;
      });
    } catch (error) {
      if (mounted && serial == _serial) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && serial == _serial) setState(() => _loading = false);
    }
  }

  Future<bool> _reviewPaper(LeaveRequest request) {
    if (_paperStep?.isCompleted == false) return Future.value(false);
    final step = Completer<bool>();
    setState(() {
      _pendingRequest = request;
      _paperFields['original_filing_date']!.text = _dateText(
        request.dateFiled!,
      );
      _paperStep = step;
      _reviewingPaper = true;
      _error = null;
    });
    unawaited(_loadSignatoryChoices());
    return step.future;
  }

  void _clearConfiguredSigners() {
    for (final group in _signerFields.keys) {
      final selected = _selectedSigners[group];
      if (selected != null && selected != 'other' && selected != 'none') {
        _selectedSigners[group] = null;
        for (final key in _signerFields[group]!) {
          _paperFields[key]!.clear();
        }
      }
    }
    _confirmedComplete = false;
    _confirmedNotRecorded = false;
  }

  Future<void> _loadSignatoryChoices({bool force = false}) async {
    final request = _pendingRequest;
    if (request == null) return;
    final approval = _paperFields['approval_date']!.text.trim();
    final filing = _paperFields['original_filing_date']!.text;
    if (approval.isNotEmpty && !_validDate(approval)) {
      ++_signerSerial;
      setState(() {
        _clearConfiguredSigners();
        _signatoryChoices.clear();
        _signerDate = null;
        _loadingSigners = false;
        _signerContext = null;
        _signerError =
            'Enter a valid approval date to refresh signatory suggestions. You can also use Other signatory.';
      });
      return;
    }
    final effective = approval.isEmpty ? filing : approval;
    final contextKey =
        '${request.userId}|${request.effectiveLeaveTypeName}|$filing|$effective';
    if (!force && _signerContext == contextKey) return;
    final serial = ++_signerSerial;
    setState(() {
      if (_signerContext != contextKey) {
        _clearConfiguredSigners();
        _signatoryChoices.clear();
        _signerDate = null;
        _signerWarnings = [];
      }
      _signerContext = contextKey;
      _loadingSigners = true;
      _signerError = null;
    });
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/admin/paper-signatories',
        queryParameters: {
          'employee_id': request.userId,
          'leave_type': request.effectiveLeaveTypeName,
          'filing_date': filing,
          if (approval.isNotEmpty) 'approval_date': approval,
        },
      );
      if (!mounted || serial != _signerSerial) return;
      final data = response.data ?? {};
      setState(() {
        for (final group in _signerFields.keys) {
          _signatoryChoices[group] = (data[group] as List? ?? [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          final selected = _selectedSigners[group];
          if (selected != null &&
              selected != 'other' &&
              selected != 'none' &&
              !_signatoryChoices[group]!.any(
                (row) => row['user_id'] == selected,
              )) {
            _selectedSigners[group] = null;
            for (final key in _signerFields[group]!) {
              _paperFields[key]!.clear();
            }
          }
        }
        _signerWarnings = (data['warnings'] as List? ?? [])
            .map((value) => value.toString())
            .toList();
        _signerDate = data['effective_date']?.toString();
      });
    } catch (error) {
      if (mounted && serial == _signerSerial) {
        setState(() {
          _signerError =
              'Unable to load signatory suggestions. Choose Other signatory to copy the signer from the paper, or retry.';
          _signatoryChoices.clear();
          _clearConfiguredSigners();
        });
      }
    } finally {
      if (mounted && serial == _signerSerial) {
        setState(() => _loadingSigners = false);
      }
    }
  }

  Widget _signerPicker(String group, String label, {bool required = false}) {
    final selected = _selectedSigners[group];
    final choices = _signatoryChoices[group] ?? [];
    final fields = _signerFields[group]!;
    final configured =
        selected != null && selected != 'other' && selected != 'none';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('paper_signer_$group'),
          initialValue: selected,
          isExpanded: true,
          hint: Text(
            required ? 'Select the actual signer' : 'Select signer (optional)',
          ),
          decoration: const InputDecoration(),
          items: [
            if (!required)
              const DropdownMenuItem(
                value: 'none',
                child: Text('Not shown on paper'),
              ),
            for (final row in choices)
              DropdownMenuItem(
                value: row['user_id']?.toString(),
                child: Text(
                  '${row['name']} · ${row['reviewer_role'] == 'backup' ? 'Backup' : 'Primary'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: 'other',
              child: Text('Other signatory'),
            ),
          ],
          validator: (value) => required && value == null
              ? 'Select the final approving official shown on paper.'
              : null,
          onChanged: (value) => setState(() {
            _selectedSigners[group] = value;
            _confirmedComplete = false;
            _confirmedNotRecorded = false;
            Map<String, dynamic>? person;
            for (final row in choices) {
              if (row['user_id'] == value) person = row;
            }
            _paperFields[fields[0]]!.text = person?['name']?.toString() ?? '';
            _paperFields[fields[1]]!.text =
                person?['position_title']?.toString() ?? '';
          }),
        ),
        const SizedBox(height: 16),
        if (selected != null && selected != 'none')
          _pair(
            _field(
              fields[0],
              'Name on paper',
              required: required,
              readOnly: configured,
            ),
            _field(
              fields[1],
              'Position / designation',
              required: required,
              readOnly:
                  configured &&
                  choices.any(
                    (row) =>
                        row['user_id'] == selected &&
                        (row['position_title']?.toString() ?? '').isNotEmpty,
                  ),
            ),
          ),
        if (configured)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              choices.any(
                    (person) =>
                        person['user_id'] == selected &&
                        person['has_saved_signature'] == true,
                  )
                  ? 'Their saved signature will be applied to the generated form.'
                  : 'No saved signature is available for this account. The signature line will remain blank.',
            ),
          ),
        if (configured && _paperFields[fields[1]]!.text.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Position is unavailable. Enter the position shown on the paper.',
            ),
          ),
      ],
    );
  }

  void _returnToDetails() {
    if (_savingPaper) return;
    setState(() {
      _reviewingPaper = false;
      _error = null;
    });
    if (_paperStep?.isCompleted == false) _paperStep!.complete(false);
  }

  Future<void> _pickSignedForm() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null ||
          file.bytes!.isEmpty ||
          !RegExp(
            r'\.(pdf|jpe?g|png)$',
            caseSensitive: false,
          ).hasMatch(file.name)) {
        setState(
          () => _error = 'Choose a PDF, JPG or PNG containing the signed form.',
        );
        return;
      }
      if (file.bytes!.length > 10 * 1024 * 1024) {
        setState(() => _error = 'File too large. Max 10MB.');
        return;
      }
      setState(() {
        _signedBytes = file.bytes;
        _signedName = file.name;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to open the file. Please retry.');
      }
    }
  }

  Future<bool> _file(
    LeaveRequest request, {
    List<int>? bytes,
    String? name,
  }) async {
    if (bytes == null || name == null || _paperApproval == null) {
      throw Exception(
        'Upload the approved signed paper form and required supporting documents.',
      );
    }
    final auth = context.read<AuthProvider>();
    final actor = auth.user?.id;
    final allocation = await showDialog<LeaveApprovalInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminLeaveApproveDialog(
        request: request,
        title: 'Paid / unpaid days on the approved paper',
        confirmLabel: 'Record approval',
        creditSummary:
            'Enter the allocation already approved on paper. Paid days use credits only for credit-based leave.',
      ),
    );
    if (!mounted ||
        actor == null ||
        auth.user?.id != actor ||
        allocation == null) {
      return false;
    }
    await ApiLeaveRepository().recordApprovedPaperLeave(
      request,
      paperApproval: _paperApproval!,
      approval: allocation,
      fileBytes: bytes,
      fileName: name,
    );
    return true;
  }

  String _dateText(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  bool _validDate(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    return parsed != null && _dateText(parsed) == value;
  }

  Future<void> _pickDate(String key) async {
    final provider = context.read<LeaveProvider>();
    await provider.loadOfficialDate();
    if (!mounted) return;
    final today = provider.officialDate;
    if (today == null) {
      setState(
        () => _error =
            'Load the official HRMS date before recording paper approvals.',
      );
      return;
    }
    final selected = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(_paperFields[key]!.text)?.isAfter(today) == false &&
              (DateTime.tryParse(_paperFields[key]!.text)?.year ?? 0) >= 1900
          ? DateTime.parse(_paperFields[key]!.text)
          : today,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (selected != null && mounted) {
      setState(() => _paperFields[key]!.text = _dateText(selected));
      if (key == 'approval_date') unawaited(_loadSignatoryChoices());
    }
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool date = false,
    int lines = 1,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Semantics(
          label: label,
          child: TextFormField(
            key: ValueKey('paper_field_$key'),
            controller: _paperFields[key],
            readOnly: readOnly,
            onChanged: key == 'approval_date'
                ? (_) => unawaited(_loadSignatoryChoices())
                : null,
            maxLines: lines,
            maxLength: lines > 1 ? 2000 : 200,
            decoration: InputDecoration(
              hintText: date ? 'YYYY-MM-DD' : null,
              counterText: '',
              suffixIcon: date
                  ? IconButton(
                      tooltip: 'Choose $label',
                      onPressed: () => _pickDate(key),
                      icon: const Icon(Icons.calendar_today_outlined),
                    )
                  : null,
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return required ? 'Required' : null;
              }
              if (date && !_validDate(value)) {
                return 'Use a valid date: YYYY-MM-DD';
              }
              return null;
            },
          ),
        ),
      ],
    ),
  );

  Future<void> _continuePaper() async {
    if (_savingPaper || !(_paperKey.currentState?.validate() ?? false)) return;
    if (_signedBytes == null) {
      setState(
        () => _error =
            'Upload the approved signed paper form and required supporting documents.',
      );
      return;
    }
    setState(() {
      _savingPaper = true;
      _error = null;
    });
    try {
      final provider = context.read<LeaveProvider>();
      await provider.loadOfficialDate();
      if (!mounted) return;
      final filing = _paperFields['original_filing_date']!.text,
          approval = _paperFields['approval_date']!.text;
      if (provider.officialDate == null ||
          filing.compareTo(approval) > 0 ||
          approval.compareTo(_dateText(provider.officialDate!)) > 0) {
        setState(
          () => _error =
              'Original filing must be on or before approval. Approval cannot be in the future.',
        );
        return;
      }
      if (!_confirmedComplete || !_confirmedNotRecorded) {
        setState(
          () => _error =
              'Confirm the paper approvals are complete and this leave has not already been recorded or deducted.',
        );
        return;
      }
      if ((_paperFields['cert_name']!.text.trim().isEmpty !=
              _paperFields['cert_title']!.text.trim().isEmpty) ||
          (_paperFields['dept_name']!.text.trim().isEmpty !=
              _paperFields['dept_title']!.text.trim().isEmpty)) {
        setState(
          () => _error =
              'Enter both name and position for each paper official, or leave both blank.',
        );
        return;
      }
      Map<String, String> official(String name, String title, String group) {
        final selected = _selectedSigners[group];
        final linked = (_signatoryChoices[group] ?? []).any(
          (person) => person['user_id'] == selected,
        );
        return {
          'name': _paperFields[name]!.text.trim(),
          'position_title': _paperFields[title]!.text.trim(),
          if (linked && selected != null) 'user_id': selected,
        };
      }

      setState(
        () => _paperApproval = {
          'original_filing_date': filing,
          'approval_date': approval,
          'final_approver': official(
            'final_name',
            'final_title',
            'final_approver',
          ),
          'certification_officer': official(
            'cert_name',
            'cert_title',
            'certification_officer',
          ),
          'department_reviewer': official(
            'dept_name',
            'dept_title',
            'department_reviewer',
          ),
          'additional_approvers': _paperFields['additional']!.text.trim(),
          'confirmed_complete': true,
          'confirmed_not_recorded': true,
        },
      );
      final saved = await _file(
        _pendingRequest!,
        bytes: _signedBytes,
        name: _signedName,
      );
      if (!mounted) return;
      if (saved && _paperStep?.isCompleted == false) _paperStep!.complete(true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _savingPaper = false);
    }
  }

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 640) {
        return Column(children: [first, second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _section(
    String title,
    String description,
    IconData icon,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _paperDetails() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Original Paper Approval'),
        leading: IconButton(
          tooltip: 'Back to leave details',
          icon: const Icon(Icons.arrow_back),
          onPressed: _savingPaper ? null : _returnToDetails,
        ),
      ),
      bottomNavigationBar: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const Text(
                  'Next: review paid / unpaid days, then record the approved leave.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: _savingPaper ? null : _continuePaper,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(
                      _savingPaper ? 'Recording…' : 'Review and record',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _savingPaper,
        child: Form(
          key: _paperKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Step 3 of 3 • Paper approval',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person_outline,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected!.fullName ?? 'Employee',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Recording an already-approved paper application',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Copy the approval details from the signed paper and upload the original. The employee’s saved signature will be included in generated copies if available. Review the selected leave details before recording.',
              ),
              const SizedBox(height: 24),
              _section(
                'Selected leave',
                'These details were entered in the previous step.',
                Icons.event_note_outlined,
                [
                  Text(
                    _pendingRequest!.leaveTypeDisplayName ??
                        _pendingRequest!.effectiveLeaveTypeName,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_dateText(_pendingRequest!.startDate!)} to ${_dateText(_pendingRequest!.endDate!)} · ${_pendingRequest!.workingDaysApplied} day(s)',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Original filing date: ${_paperFields['original_filing_date']!.text}',
                  ),
                  if ((_pendingRequest!.reason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_pendingRequest!.reason!),
                  ],
                ],
              ),
              _section(
                'Approval dates · Required',
                'Use the original dates on the paper, not the date you are encoding it.',
                Icons.event_outlined,
                [
                  _field(
                    'approval_date',
                    'Final approval date',
                    required: true,
                    date: true,
                  ),
                ],
              ),
              _section(
                'Final approving official · Required',
                'Choose the person who actually signed the paper. Select Other signatory for someone outside the suggestions.',
                Icons.verified_user_outlined,
                [
                  if (_loadingSigners)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_signerDate != null && !_loadingSigners)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Suggestions for $_signerDate. Verify against the signed paper.',
                      ),
                    ),
                  if (_signerError != null) ...[
                    Text(_signerError!),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _loadSignatoryChoices(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry suggestions'),
                      ),
                    ),
                  ],
                  for (final warning in _signerWarnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(warning),
                    ),
                  _signerPicker(
                    'final_approver',
                    'Final approving official',
                    required: true,
                  ),
                ],
              ),
              _section(
                'Other signatories · Optional',
                'Complete these only when shown on the paper. Enter both the name and position for each official.',
                Icons.people_outline,
                [
                  _signerPicker(
                    'certification_officer',
                    'Leave-credit certifier',
                  ),
                  _signerPicker(
                    'department_reviewer',
                    'Recommending / department official',
                  ),
                  _field('additional', 'Additional approval details', lines: 3),
                ],
              ),
              _section(
                'Signed paper form · Required',
                'Upload the fully signed form and all required supporting documents as one PDF, JPG or PNG (max 10MB).',
                Icons.upload_file_outlined,
                [
                  if (_signedName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_signedName!),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _savingPaper ? null : _pickSignedForm,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _signedName == null
                              ? 'Upload signed form'
                              : 'Replace signed form',
                        ),
                      ),
                      if (_signedName != null)
                        TextButton(
                          onPressed: _savingPaper
                              ? null
                              : () => setState(() {
                                  _signedName = null;
                                  _signedBytes = null;
                                }),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ],
              ),
              _section(
                'Verification · Required',
                'Confirm both checks before continuing.',
                Icons.fact_check_outlined,
                [
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    value: _confirmedComplete,
                    onChanged: (v) =>
                        setState(() => _confirmedComplete = v == true),
                    title: const Text(
                      'I verified the employee signature and all required approvals on paper, including Mayor or custom reviewers where applicable.',
                    ),
                  ),
                  const Divider(),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    value: _confirmedNotRecorded,
                    onChanged: (v) =>
                        setState(() => _confirmedNotRecorded = v == true),
                    title: const Text(
                      'I verified this leave has not already been recorded or deducted in this system.',
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

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return PopScope(
        canPop: !_reviewingPaper,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _returnToDetails();
        },
        child: IndexedStack(
          index: _reviewingPaper ? 1 : 0,
          children: [
            TickerMode(
              enabled: !_reviewingPaper,
              child: ExcludeFocus(
                excluding: _reviewingPaper,
                child: LeaveRequestFormScreen(
                  key: ValueKey(_selected!.id),
                  filingEmployee: _selected,
                  onReviewPaperApproval: _reviewPaper,
                  onBackToEmployeeSelection: () => setState(() {
                    _selected = null;
                    _error = null;
                  }),
                ),
              ),
            ),
            if (_pendingRequest != null)
              _paperDetails()
            else
              const SizedBox.shrink(),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Record Approved Paper Leave')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 1 of 3 • Employee',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select an employee',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Record one fully approved paper application at a time. Enable approved paper recording for the leave type under Leave Type Rules. Use My Leave for new personal applications.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Search employees',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _load(),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _employees.length + 1,
              itemBuilder: (context, index) {
                if (index == _employees.length) {
                  if (_employees.isEmpty && !_loading) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No employees found.'),
                    );
                  }
                  return _employees.length < _total
                      ? TextButton(
                          onPressed: _loading ? null : () => _load(more: true),
                          child: const Text('Load more employees'),
                        )
                      : const SizedBox.shrink();
                }
                final employee = _employees[index];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(employee.fullName ?? 'Employee'),
                  subtitle: Text(
                    employee.employmentType?.replaceAll('_', ' ') ?? '',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() {
                    if (_selected?.id != employee.id) {
                      for (final controller in _paperFields.values) {
                        controller.clear();
                      }
                      _confirmedComplete = false;
                      _confirmedNotRecorded = false;
                      _paperApproval = null;
                      _signerContext = null;
                      ++_signerSerial;
                      _selectedSigners.clear();
                      _signatoryChoices.clear();
                      _signerDate = null;
                      _signerWarnings = [];
                      _signerError = null;
                      _pendingRequest = null;
                      _signedName = null;
                      _signedBytes = null;
                      _reviewingPaper = false;
                    }
                    _selected = employee;
                    _error = null;
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
