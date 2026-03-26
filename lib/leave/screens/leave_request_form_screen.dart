import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../widgets/leave_guidance_widgets.dart';

typedef LeaveRequestAction = Future<bool> Function(LeaveRequest request);

/// Modern, digital-first employee leave request form.
class LeaveRequestFormScreen extends StatefulWidget {
  const LeaveRequestFormScreen({
    super.key,
    this.initialRequest,
    this.onSaveDraft,
    this.onSubmitRequest,
  });

  final LeaveRequest? initialRequest;
  final LeaveRequestAction? onSaveDraft;
  final LeaveRequestAction? onSubmitRequest;

  @override
  State<LeaveRequestFormScreen> createState() => _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState extends State<LeaveRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late LeaveType _leaveType;
  LeaveLocationOption? _locationOption;
  SickLeaveNature? _sickLeaveNature;
  StudyLeavePurpose? _studyPurpose;
  LeaveOtherPurpose? _otherPurpose;
  LeaveCommutationOption _commutation = LeaveCommutationOption.notRequested;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _busy = false;
  LeaveRequest? _savedRequest;
  bool _attachmentUploading = false;

  late final TextEditingController _customLeaveTypeController;
  late final TextEditingController _reasonController;
  late final TextEditingController _locationDetailsController;
  late final TextEditingController _sickIllnessController;
  late final TextEditingController _womenIllnessController;
  late final TextEditingController _studyPurposeDetailsController;
  late final TextEditingController _otherPurposeDetailsController;
  late final TextEditingController _workingDaysController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRequest;
    _savedRequest = initial;
    _leaveType = initial?.leaveType ?? LeaveType.vacationLeave;
    _locationOption = initial?.locationOption;
    _sickLeaveNature = initial?.sickLeaveNature;
    _studyPurpose = initial?.studyPurpose;
    _otherPurpose = initial?.otherPurpose;
    _commutation = initial?.commutation ?? LeaveCommutationOption.notRequested;
    _startDate = initial?.startDate;
    _endDate = initial?.endDate;

    _customLeaveTypeController = TextEditingController(
      text: initial?.customLeaveTypeText ?? '',
    );
    _reasonController = TextEditingController(text: initial?.reason ?? '');
    _locationDetailsController = TextEditingController(
      text: initial?.locationDetails ?? '',
    );
    _sickIllnessController = TextEditingController(
      text: initial?.sickIllnessDetails ?? '',
    );
    _womenIllnessController = TextEditingController(
      text: initial?.womenIllnessDetails ?? '',
    );
    _studyPurposeDetailsController = TextEditingController(
      text: initial?.studyPurposeDetails ?? '',
    );
    _otherPurposeDetailsController = TextEditingController(
      text: initial?.otherPurposeDetails ?? '',
    );
    _workingDaysController = TextEditingController(
      text: initial?.workingDaysApplied?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _customLeaveTypeController.dispose();
    _reasonController.dispose();
    _locationDetailsController.dispose();
    _sickIllnessController.dispose();
    _womenIllnessController.dispose();
    _studyPurposeDetailsController.dispose();
    _otherPurposeDetailsController.dispose();
    _workingDaysController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _resetConditionalSelectionsForType(LeaveType type) {
    _locationOption = null;
    _sickLeaveNature = null;
    _studyPurpose = null;
    _otherPurpose = null;
    _customLeaveTypeController.clear();
    _locationDetailsController.clear();
    _sickIllnessController.clear();
    _womenIllnessController.clear();
    _studyPurposeDetailsController.clear();
    _otherPurposeDetailsController.clear();
  }

  Future<void> _saveDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select date(s)');
      return;
    }
    await _submit(isDraft: true);
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select start and end dates');
      return;
    }

    // FIX #7: Validate that the working days field matches the computed value.
    final computed = _computeWorkingDays();
    if (computed != null) {
      final entered = double.tryParse(_workingDaysController.text.trim());
      if (entered == null) {
        _showMessage('Please enter a valid number of working days.');
        return;
      }
      if (entered <= 0) {
        _showMessage('Working days must be greater than 0.');
        return;
      }
      if (entered > computed) {
        _showMessage(
          'Working days ($entered) cannot exceed the computed '
          'Mon–Fri days for the selected range ($computed).'
        );
        return;
      }
    }

    // FIX #6: Block submit if leave type requires an attachment and none exists.
    if (_leaveType.requiresAttachment && !_hasAttachment()) {
      // For sick leave, the attachment is only strictly required when > 5 days
      // (matching the backend leaveTypeRules.js rule).
      final isSickLeaveMandatory = _leaveType == LeaveType.sickLeave
          ? ((_computeWorkingDays() ?? 0) > 5)
          : true;
      if (isSickLeaveMandatory) {
        _showAttachmentRequiredDialog();
        return;
      }
    }

    await _submit(isDraft: false);
  }

  /// Returns the number of Mon–Fri days between start and end date (inclusive),
  /// or null if dates are not yet set.
  int? _computeWorkingDays() {
    if (_startDate == null || _endDate == null) return null;
    if (_endDate!.isBefore(_startDate!)) return null;
    int count = 0;
    DateTime d = _startDate!;
    while (!d.isAfter(_endDate!)) {
      final wd = d.weekday; // 1=Mon … 7=Sun
      if (wd != DateTime.saturday && wd != DateTime.sunday) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }

  bool _hasAttachment() {
    final current = _savedRequest ?? widget.initialRequest;
    return (current?.attachmentName ?? '').trim().isNotEmpty;
  }

  void _showAttachmentRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Text('Attachment Required'),
          ],
        ),
        content: Text(
          'This leave type (${_leaveType.displayName}) requires a supporting '
          'document (e.g. medical certificate, birth certificate).\n\n'
          'Please save as draft first, upload the required document, then submit.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit({required bool isDraft}) async {
    setState(() => _busy = true);
    try {
      final initial = widget.initialRequest;
      final userId = context.read<AuthProvider>().user!.id;

      // FIX #4: prefer the ID from _savedRequest (set on first save) so that
      // subsequent "Save Draft" clicks do a PUT (update) rather than another POST.
      final existingId = _savedRequest?.id ?? initial?.id;

      final req = LeaveRequest(
        id: existingId,
        userId: userId,
        leaveType: _leaveType,
        customLeaveTypeText: _leaveType == LeaveType.others
            ? _customLeaveTypeController.text.trim()
            : null,
        startDate: _startDate,
        endDate: _endDate,
        workingDaysApplied: double.tryParse(_workingDaysController.text.trim()),
        reason: _reasonController.text.trim(),
        locationOption:
            (_leaveType == LeaveType.vacationLeave ||
                _leaveType == LeaveType.specialPrivilegeLeave)
            ? _locationOption
            : null,
        locationDetails: _locationDetailsController.text.trim(),
        sickLeaveNature: _leaveType == LeaveType.sickLeave
            ? _sickLeaveNature
            : null,
        sickIllnessDetails: _sickIllnessController.text.trim(),
        womenIllnessDetails:
            _leaveType == LeaveType.specialLeaveBenefitsForWomen
            ? _womenIllnessController.text.trim()
            : null,
        studyPurpose: _leaveType == LeaveType.studyLeave ? _studyPurpose : null,
        studyPurposeDetails: _studyPurposeDetailsController.text.trim(),
        otherPurpose: _leaveType == LeaveType.others ? _otherPurpose : null,
        otherPurposeDetails: _otherPurposeDetailsController.text.trim(),
        commutation: _commutation,
        attachmentName:
            _savedRequest?.attachmentName ?? initial?.attachmentName,
        attachmentPath:
            _savedRequest?.attachmentPath ?? initial?.attachmentPath,
        status: isDraft ? LeaveRequestStatus.draft : LeaveRequestStatus.pending,
      );

      if (isDraft) {
        // The onSaveDraft callback (in leave_main.dart) handles the
        // saveDraft vs updateRequest routing based on whether req.id is set.
        final success = widget.onSaveDraft != null
            ? await widget.onSaveDraft!(req)
            : false;
        if (!mounted) return;
        if (success) Navigator.of(context).pop(true);
      } else {
        final action = widget.onSubmitRequest;
        if (action != null) {
          final success = await action(req);
          if (!mounted) return;
          if (success) Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formMaxWidth = 800.0; // Clean, narrow column for digital entry

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('File Leave Request'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Leave Details',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select the type of leave and provide the necessary details.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // A. General instruction panel
                    const LeaveGeneralInstructionsPanel(),
                    const SizedBox(height: 24),

                    // Card 1: Leave Type
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionTitle('1. Leave Type'),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<LeaveType>(
                            value: _leaveType,
                            decoration: _inputDecoration('Select Leave Type'),
                            items: LeaveType.values
                                .where(
                                  (t) => t.employeeCanFile || t == _leaveType,
                                )
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.displayName),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _leaveType = val;
                                  _resetConditionalSelectionsForType(val);
                                });
                              }
                            },
                          ),

                          // B. Dynamic leave-type guidance
                          const SizedBox(height: 14),
                          LeaveTypeGuidanceCard(leaveType: _leaveType),

                          if (_leaveType == LeaveType.others) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _customLeaveTypeController,
                              decoration: _inputDecoration(
                                'Specify other leave type...',
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // C. Full guidelines button (below Card 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: const ViewFullGuidelinesButton(),
                    ),
                    const SizedBox(height: 16),

                    // Card 2: Dates
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionTitle('2. Dates of Leave'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDatePicker(
                                  label: 'Start Date',
                                  value: _startDate,
                                  onChanged: (d) =>
                                      setState(() => _startDate = d),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildDatePicker(
                                  label: 'End Date',
                                  value: _endDate,
                                  onChanged: (d) =>
                                      setState(() => _endDate = d),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // FIX #7: Auto-fill working days and validate against computed.
                          Builder(
                            builder: (context) {
                              final computed = _computeWorkingDays();
                              return TextFormField(
                                controller: _workingDaysController,
                                keyboardType: TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: _inputDecoration(
                                  'Number of Working Days Applied For',
                                ).copyWith(
                                  suffixIcon:  computed != null
                                      ? Tooltip(
                                          message:
                                              'Auto-computed: $computed Mon–Fri day(s)',
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.auto_fix_high,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _workingDaysController.text =
                                                  computed.toString(),
                                            ),
                                          ),
                                        )
                                      : null,
                                  helperText: computed != null
                                      ? 'Mon–Fri days for selected range: $computed'
                                      : 'Select dates to auto-compute',
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty)
                                    return 'Required';
                                  final entered = double.tryParse(val.trim());
                                  if (entered == null) return 'Must be a number';
                                  if (entered <= 0)
                                    return 'Must be greater than 0';
                                  // FIX #7: Hard-block if entered > computed.
                                  if (computed != null && entered > computed) {
                                    return 'Cannot exceed $computed computed working day(s) for this range';
                                  }
                                  // Warn about max days for leave type
                                  final maxDays = _leaveType.maxDays;
                                  if (maxDays != null && entered > maxDays) {
                                    return '${_leaveType.displayName} allows max $maxDays days';
                                  }
                                  return null;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Card 3: Dynamic Details based on leave type
                    _buildDetailsCard(),

                    const SizedBox(height: 16),

                    // Card 4: Attachments & Commutation
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionTitle('4. Additional Information'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Checkbox(
                                value:
                                    _commutation ==
                                    LeaveCommutationOption.requested,
                                onChanged: (val) {
                                  setState(() {
                                    _commutation = val == true
                                        ? LeaveCommutationOption.requested
                                        : LeaveCommutationOption.notRequested;
                                  });
                                },
                              ),
                              const Expanded(
                                child: Text('Requested Commutation of Leave'),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          _buildAttachmentSection(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.onSaveDraft != null)
                          OutlinedButton(
                            onPressed: _busy ? null : _saveDraft,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: const Text('Save Draft'),
                          ),
                        const SizedBox(width: 16),
                        if (widget.onSubmitRequest != null)
                          FilledButton(
                            onPressed: _busy ? null : _submitRequest,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Submit Request'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTheme.primaryNavy,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Text(
          value == null
              ? 'Select Date'
              : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    List<Widget> children = [_buildSectionTitle('3. Leave Details')];

    // Shared Reasons
    children.addAll([
      const SizedBox(height: 16),
      TextFormField(
        controller: _reasonController,
        maxLines: 2,
        decoration: _inputDecoration('General Reason / Remarks (Optional)'),
      ),
    ]);

    // Dynamic based on type
    if (_leaveType == LeaveType.vacationLeave ||
        _leaveType == LeaveType.specialPrivilegeLeave) {
      children.addAll([
        const SizedBox(height: 16),
        Text('Location Option', style: TextStyle(fontWeight: FontWeight.w500)),
        RadioListTile<LeaveLocationOption>(
          title: const Text('Within Philippines'),
          value: LeaveLocationOption.withinPhilippines,
          groupValue: _locationOption,
          onChanged: (v) => setState(() => _locationOption = v),
        ),
        RadioListTile<LeaveLocationOption>(
          title: const Text('Abroad'),
          value: LeaveLocationOption.abroad,
          groupValue: _locationOption,
          onChanged: (v) => setState(() => _locationOption = v),
        ),
        if (_locationOption != null) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _locationDetailsController,
            decoration: _inputDecoration('Specify location...'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ],
      ]);
    } else if (_leaveType == LeaveType.sickLeave) {
      children.addAll([
        const SizedBox(height: 16),
        Text(
          'Nature of Illness',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        RadioListTile<SickLeaveNature>(
          title: const Text('In Hospital'),
          value: SickLeaveNature.inHospital,
          groupValue: _sickLeaveNature,
          onChanged: (v) => setState(() => _sickLeaveNature = v),
        ),
        RadioListTile<SickLeaveNature>(
          title: const Text('Out Patient'),
          value: SickLeaveNature.outPatient,
          groupValue: _sickLeaveNature,
          onChanged: (v) => setState(() => _sickLeaveNature = v),
        ),
        if (_sickLeaveNature != null) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _sickIllnessController,
            decoration: _inputDecoration('Specify illness details...'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ],
      ]);
    } else if (_leaveType == LeaveType.specialLeaveBenefitsForWomen) {
      children.addAll([
        const SizedBox(height: 16),
        TextFormField(
          controller: _womenIllnessController,
          decoration: _inputDecoration('Specify illness details...'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ]);
    } else if (_leaveType == LeaveType.studyLeave) {
      children.addAll([
        const SizedBox(height: 16),
        Text(
          'Purpose of Study Leave',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        RadioListTile<StudyLeavePurpose>(
          title: const Text('Completion of Master\'s Degree'),
          value: StudyLeavePurpose.completionOfMastersDegree,
          groupValue: _studyPurpose,
          onChanged: (v) => setState(() => _studyPurpose = v),
        ),
        RadioListTile<StudyLeavePurpose>(
          title: const Text('BAR / Board Examination Review'),
          value: StudyLeavePurpose.barBoardExaminationReview,
          groupValue: _studyPurpose,
          onChanged: (v) => setState(() => _studyPurpose = v),
        ),
        if (_studyPurpose != null) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _studyPurposeDetailsController,
            decoration: _inputDecoration('Specify study leave details...'),
          ),
        ],
      ]);
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildAttachmentSection() {
    final current = _savedRequest ?? widget.initialRequest;
    final requestId = current?.id;
    final hasAttachment = (current?.attachmentName ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Attachments', style: TextStyle(fontWeight: FontWeight.w500)),
            if (_leaveType.requiresAttachment) ...[
              const SizedBox(width: 8),
              // FIX #6: Show mandatory badge for attachment-required types.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  _leaveType == LeaveType.sickLeave
                      ? 'Required if > 5 days'
                      : 'Required',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _leaveType.requiresAttachment
              ? 'A supporting document is required for this leave type (e.g. medical certificate, birth certificate). PDF, JPG, PNG (max 10MB).'
              : 'Supporting attachment: optional. PDF, JPG, PNG (max 10MB).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (requestId == null || requestId.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save draft first to upload an attachment.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (hasAttachment)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.attach_file, color: AppTheme.primaryNavy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      current!.attachmentName!,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: (_busy || _attachmentUploading)
                    ? null
                    : _pickAndUploadAttachment,
                icon: _attachmentUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(hasAttachment ? 'Replace File' : 'Upload File'),
              ),
              if (hasAttachment) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: (_busy || _attachmentUploading)
                      ? null
                      : _removeAttachment,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickAndUploadAttachment() async {
    final current = _savedRequest ?? widget.initialRequest;
    final requestId = current?.id;
    if (requestId == null || requestId.isEmpty) {
      _showMessage('Save draft first to add an attachment.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null)
      return;
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes!;
    final name = file.name;
    if (name.isEmpty) return;

    setState(() => _attachmentUploading = true);
    try {
      final provider = context.read<LeaveProvider>();
      final updated = await provider.attachFile(
        requestId: requestId,
        fileBytes: bytes,
        fileName: name,
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _savedRequest = updated;
          _attachmentUploading = false;
        });
        _showMessage('Attachment uploaded.');
      } else {
        setState(() => _attachmentUploading = false);
        _showMessage(provider.error ?? 'Upload failed.');
      }
    } catch (e) {
      if (mounted) setState(() => _attachmentUploading = false);
      _showMessage('Upload failed: $e');
    }
  }

  Future<void> _removeAttachment() async {
    final current = _savedRequest ?? widget.initialRequest;
    final requestId = current?.id;
    if (requestId == null || requestId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: const Text(
          'Are you sure you want to remove the uploaded file?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _attachmentUploading = true);
    try {
      final provider = context.read<LeaveProvider>();
      final updated = await provider.removeAttachment(requestId);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _savedRequest = updated;
          _attachmentUploading = false;
        });
        _showMessage('Attachment removed.');
      } else {
        setState(() => _attachmentUploading = false);
        _showMessage(provider.error ?? 'Remove failed.');
      }
    } catch (e) {
      if (mounted) setState(() => _attachmentUploading = false);
      _showMessage('Remove failed: $e');
    }
  }
}
