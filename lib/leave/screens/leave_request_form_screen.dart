import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../leave_provider.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';

typedef LeaveRequestAction = Future<bool> Function(LeaveRequest request);

/// Employee leave request form based on the CSC Application for Leave.
///
/// This screen focuses on collecting structured data first. File attachment
/// upload can be added later once the storage/backend implementation is ready.
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

  late final TextEditingController _officeDepartmentController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _positionTitleController;
  late final TextEditingController _salaryController;
  late final TextEditingController _customLeaveTypeController;
  late final TextEditingController _reasonController;
  late final TextEditingController _locationDetailsController;
  late final TextEditingController _sickIllnessController;
  late final TextEditingController _womenIllnessController;
  late final TextEditingController _studyPurposeDetailsController;
  late final TextEditingController _otherPurposeDetailsController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRequest;
    _leaveType = initial?.leaveType ?? LeaveType.vacationLeave;
    _locationOption = initial?.locationOption;
    _sickLeaveNature = initial?.sickLeaveNature;
    _studyPurpose = initial?.studyPurpose;
    _otherPurpose = initial?.otherPurpose;
    _commutation = initial?.commutation ?? LeaveCommutationOption.notRequested;
    _startDate = initial?.startDate;
    _endDate = initial?.endDate;

    _officeDepartmentController = TextEditingController(
      text: initial?.officeDepartment ?? '',
    );
    final authName = context.read<AuthProvider>().displayName;
    final nameParts = _parseNameToLastFirstMiddle(
      authName.isNotEmpty ? authName : (initial?.employeeName ?? ''),
    );
    _lastNameController = TextEditingController(text: nameParts.last);
    _firstNameController = TextEditingController(text: nameParts.first);
    _middleNameController = TextEditingController(text: nameParts.middle);
    _positionTitleController = TextEditingController(
      text: initial?.positionTitle ?? '',
    );
    _salaryController = TextEditingController(
      text: initial?.salary?.toString() ?? '',
    );
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadEmployeeAssignmentPrefill(),
    );
  }

  Future<void> _loadEmployeeAssignmentPrefill() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments?employee_id=$userId&status=Active',
      );
      final data = res.data;
      if (data == null || data.isEmpty) return;
      final first = data.first as Map<String, dynamic>;
      final departmentName = first['department_name'] as String?;
      final positionName = first['position_name'] as String?;
      if (!mounted) return;
      if ((departmentName ?? '').trim().isNotEmpty &&
          _officeDepartmentController.text.trim().isEmpty) {
        _officeDepartmentController.text = departmentName!.trim();
      }
      if ((positionName ?? '').trim().isNotEmpty &&
          _positionTitleController.text.trim().isEmpty) {
        _positionTitleController.text = positionName!.trim();
      }
      setState(() {});
    } catch (_) {
      // Pre-fill is best-effort; leave fields editable
    }
  }

  @override
  void dispose() {
    _officeDepartmentController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _positionTitleController.dispose();
    _salaryController.dispose();
    _customLeaveTypeController.dispose();
    _reasonController.dispose();
    _locationDetailsController.dispose();
    _sickIllnessController.dispose();
    _womenIllnessController.dispose();
    _studyPurposeDetailsController.dispose();
    _otherPurposeDetailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.displayName.isNotEmpty ? auth.displayName : 'Employee';
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1200;
    final isTablet = width >= 900;
    final compact = !isTablet;
    final formMaxWidth = isDesktop ? 1180.0 : (isTablet ? 1000.0 : 760.0);
    final outerPadding = isDesktop ? 28.0 : (isTablet ? 20.0 : 16.0);
    final sheetPadding = isDesktop ? 16.0 : 12.0;

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(title: const Text('Leave Request Form')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(outerPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: formMaxWidth),
                    child: RepaintBoundary(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          border: Border.all(color: Colors.black, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: isDesktop ? 20 : 16),
                            Text(
                              'APPLICATION FOR LEAVE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: isDesktop ? 30 : 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            SizedBox(height: isDesktop ? 18 : 14),
                            _buildTopInformationSection(name, compact: compact),
                            _paperSectionHeader('6. DETAILS OF APPLICATION'),
                            Padding(
                              padding: EdgeInsets.all(sheetPadding),
                              child: compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildLeaveTypePanel(),
                                        const SizedBox(height: 12),
                                        _buildDetailsOfLeavePanel(),
                                      ],
                                    )
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _buildLeaveTypePanel(),
                                          ),
                                          const SizedBox(width: 0),
                                          Expanded(
                                            child: _buildDetailsOfLeavePanel(),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                sheetPadding,
                                0,
                                sheetPadding,
                                sheetPadding,
                              ),
                              child: compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildWorkingDaysPanel(),
                                        const SizedBox(height: 12),
                                        _buildCommutationPanel(),
                                      ],
                                    )
                                  : IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: _buildWorkingDaysPanel(),
                                          ),
                                          const SizedBox(width: 0),
                                          Expanded(
                                            child: _buildCommutationPanel(
                                              showSignature: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            if (compact)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  sheetPadding,
                                  0,
                                  sheetPadding,
                                  sheetPadding,
                                ),
                                child: _buildApplicantSignatureBox(),
                              ),
                            _paperSectionHeader(
                              '7. DETAILS OF ACTION ON APPLICATION',
                            ),
                            Padding(
                              padding: EdgeInsets.all(sheetPadding),
                              child: compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildCertificationPanel(),
                                        const SizedBox(height: 12),
                                        _buildRecommendationPanel(),
                                        const SizedBox(height: 12),
                                        _buildApprovedDisapprovedSection(
                                          compact: true,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child:
                                                    _buildCertificationPanel(),
                                              ),
                                              const SizedBox(width: 0),
                                              Expanded(
                                                child:
                                                    _buildRecommendationPanel(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 0),
                                        _buildApprovedDisapprovedSection(
                                          compact: false,
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: formMaxWidth),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isDesktop ? 18 : 16),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.06),
                        ),
                      ),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    _leaveType.requiresAttachment
                                        ? 'Supporting attachment: this leave type usually requires a supporting document. Upload wiring will be added next.'
                                        : 'Supporting attachment: optional for this leave type. Upload wiring will be added next.',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _busy ? null : _saveDraft,
                                          child: const Text('Save Draft'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: _busy
                                              ? null
                                              : _submitRequest,
                                          child: Text(
                                            _busy
                                                ? 'Processing...'
                                                : 'Submit Request',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _leaveType.requiresAttachment
                                      ? 'Supporting attachment: this leave type usually requires a supporting document. Upload wiring will be added next.'
                                      : 'Supporting attachment: optional for this leave type. Upload wiring will be added next.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _busy ? null : _saveDraft,
                                        child: const Text('Save Draft'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : _submitRequest,
                                        child: Text(
                                          _busy
                                              ? 'Processing...'
                                              : 'Submit Request',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopInformationSection(String name, {required bool compact}) {
    final dateStr = _formatDate(
      widget.initialRequest?.dateFiled ?? DateTime.now(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          // Row 1: 1. OFFICE/DEPARTMENT | 2. NAME (Last) (First) (Middle)
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _paperFieldRow1Left(
                      child: TextFormField(
                        controller: _officeDepartmentController,
                        validator: _requiredValidator,
                        decoration: _paperUnderlineDecoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _paperFieldRow1Right(
                      child: Row(
                        children: [
                          Expanded(
                            child: _paperNameField(
                              hint: 'Last',
                              controller: _lastNameController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _paperNameField(
                              hint: 'First',
                              controller: _firstNameController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _paperNameField(
                              hint: 'Middle',
                              controller: _middleNameController,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _paperFieldRow1Left(
                          child: TextFormField(
                            controller: _officeDepartmentController,
                            validator: _requiredValidator,
                            decoration: _paperUnderlineDecoration(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 7,
                        child: _paperFieldRow1Right(
                          child: Row(
                            children: [
                              Expanded(
                                child: _paperNameField(
                                  hint: 'Last',
                                  controller: _lastNameController,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _paperNameField(
                                  hint: 'First',
                                  controller: _firstNameController,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _paperNameField(
                                  hint: 'Middle',
                                  controller: _middleNameController,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 10),
          // Row 2: 3. DATE OF FILING | 4. POSITION | 5. SALARY P
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _paperFieldRow2Item(
                      label: '3. DATE OF FILING',
                      child: _paperUnderlineReadOnly(dateStr),
                    ),
                    const SizedBox(height: 10),
                    _paperFieldRow2Item(
                      label: '4. POSITION',
                      child: TextFormField(
                        controller: _positionTitleController,
                        validator: _requiredValidator,
                        decoration: _paperUnderlineDecoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _paperFieldRow2Item(
                      label: '5. SALARY P',
                      child: TextFormField(
                        controller: _salaryController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) return 'Required';
                          if (double.tryParse(value!.trim()) == null) {
                            return 'Invalid amount';
                          }
                          return null;
                        },
                        decoration: _paperUnderlineDecoration(),
                      ),
                    ),
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _paperFieldRow2Item(
                          label: '3. DATE OF FILING',
                          child: _paperUnderlineReadOnly(dateStr),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4,
                        child: _paperFieldRow2Item(
                          label: '4. POSITION',
                          child: TextFormField(
                            controller: _positionTitleController,
                            validator: _requiredValidator,
                            decoration: _paperUnderlineDecoration(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: _paperFieldRow2Item(
                          label: '5. SALARY P',
                          child: TextFormField(
                            controller: _salaryController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty)
                                return 'Required';
                              if (double.tryParse(value!.trim()) == null) {
                                return 'Invalid amount';
                              }
                              return null;
                            },
                            decoration: _paperUnderlineDecoration(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildLeaveTypePanel() {
    return _paperPanel(
      title: '6.A TYPE OF LEAVE TO BE AVAILED OF',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...LeaveType.values
              .where((type) => type != LeaveType.others)
              .map(
                (type) => _paperCheckRow(
                  selected: _leaveType == type,
                  label: type.displayName,
                  onTap: () => setState(() {
                    _leaveType = type;
                    _resetConditionalSelectionsForType(type);
                  }),
                ),
              ),
          const SizedBox(height: 10),
          Text(
            'Others:',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          _paperCheckRow(
            selected: _leaveType == LeaveType.others,
            label: 'Select "Others" and specify below',
            onTap: () => setState(() {
              _leaveType = LeaveType.others;
            }),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _customLeaveTypeController,
            label: 'Specify other leave type',
            validator: _leaveType.requiresCustomDescription
                ? _requiredValidator
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsOfLeavePanel() {
    return _paperPanel(
      title: '6.B DETAILS OF LEAVE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paperSubheading('In case of Vacation/Special Privilege Leave:'),
          _paperCheckRow(
            selected: _locationOption == LeaveLocationOption.withinPhilippines,
            label: 'Within the Philippines',
            enabled: _usesLocationDetails,
            onTap: _usesLocationDetails
                ? () => setState(
                    () =>
                        _locationOption = LeaveLocationOption.withinPhilippines,
                  )
                : null,
          ),
          _paperCheckRow(
            selected: _locationOption == LeaveLocationOption.abroad,
            label: 'Abroad (Specify)',
            enabled: _usesLocationDetails,
            onTap: _usesLocationDetails
                ? () => setState(
                    () => _locationOption = LeaveLocationOption.abroad,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _locationDetailsController,
            label: 'Location details',
            validator: _usesLocationDetails ? _requiredValidator : null,
            enabled: _usesLocationDetails,
          ),
          const SizedBox(height: 16),
          _paperSubheading('In case of Sick Leave:'),
          _paperCheckRow(
            selected: _sickLeaveNature == SickLeaveNature.inHospital,
            label: 'In Hospital (Specify Illness)',
            enabled: _leaveType == LeaveType.sickLeave,
            onTap: _leaveType == LeaveType.sickLeave
                ? () => setState(
                    () => _sickLeaveNature = SickLeaveNature.inHospital,
                  )
                : null,
          ),
          _paperCheckRow(
            selected: _sickLeaveNature == SickLeaveNature.outPatient,
            label: 'Out Patient (Specify Illness)',
            enabled: _leaveType == LeaveType.sickLeave,
            onTap: _leaveType == LeaveType.sickLeave
                ? () => setState(
                    () => _sickLeaveNature = SickLeaveNature.outPatient,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _sickIllnessController,
            label: 'Specify illness',
            validator: _leaveType == LeaveType.sickLeave
                ? _requiredValidator
                : null,
            enabled: _leaveType == LeaveType.sickLeave,
          ),
          const SizedBox(height: 16),
          _paperSubheading('In case of Special Leave Benefits for Women:'),
          _buildTextField(
            controller: _womenIllnessController,
            label: 'Specify illness',
            validator: _leaveType == LeaveType.specialLeaveBenefitsForWomen
                ? _requiredValidator
                : null,
            enabled: _leaveType == LeaveType.specialLeaveBenefitsForWomen,
          ),
          const SizedBox(height: 16),
          _paperSubheading('In case of Study Leave:'),
          _paperCheckRow(
            selected:
                _studyPurpose == StudyLeavePurpose.completionOfMastersDegree,
            label: "Completion of Master's Degree",
            enabled: _leaveType == LeaveType.studyLeave,
            onTap: _leaveType == LeaveType.studyLeave
                ? () => setState(
                    () => _studyPurpose =
                        StudyLeavePurpose.completionOfMastersDegree,
                  )
                : null,
          ),
          _paperCheckRow(
            selected:
                _studyPurpose == StudyLeavePurpose.barBoardExaminationReview,
            label: 'BAR/Board Examination Review',
            enabled: _leaveType == LeaveType.studyLeave,
            onTap: _leaveType == LeaveType.studyLeave
                ? () => setState(
                    () => _studyPurpose =
                        StudyLeavePurpose.barBoardExaminationReview,
                  )
                : null,
          ),
          _paperCheckRow(
            selected: _studyPurpose == StudyLeavePurpose.otherPurpose,
            label: 'Other purpose',
            enabled: _leaveType == LeaveType.studyLeave,
            onTap: _leaveType == LeaveType.studyLeave
                ? () => setState(
                    () => _studyPurpose = StudyLeavePurpose.otherPurpose,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _studyPurposeDetailsController,
            label: 'Specify other study purpose',
            validator:
                _leaveType == LeaveType.studyLeave &&
                    _studyPurpose == StudyLeavePurpose.otherPurpose
                ? _requiredValidator
                : null,
            enabled: _leaveType == LeaveType.studyLeave,
          ),
          const SizedBox(height: 16),
          _paperSubheading('Other purpose:'),
          _paperCheckRow(
            selected:
                _otherPurpose == LeaveOtherPurpose.monetizationOfLeaveCredits,
            label: 'Monetization of Leave Credits',
            enabled: _leaveType == LeaveType.others,
            onTap: _leaveType == LeaveType.others
                ? () => setState(
                    () => _otherPurpose =
                        LeaveOtherPurpose.monetizationOfLeaveCredits,
                  )
                : null,
          ),
          _paperCheckRow(
            selected: _otherPurpose == LeaveOtherPurpose.terminalLeave,
            label: 'Terminal Leave',
            enabled: _leaveType == LeaveType.others,
            onTap: _leaveType == LeaveType.others
                ? () => setState(
                    () => _otherPurpose = LeaveOtherPurpose.terminalLeave,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _otherPurposeDetailsController,
            label: 'Additional details / reason',
            maxLines: 2,
            enabled: _leaveType == LeaveType.others,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingDaysPanel() {
    return _paperPanel(
      title: '6.C NUMBER OF WORKING DAYS APPLIED FOR',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReadOnlyField(
            label: 'Working Days',
            value: _workingDaysApplied != null
                ? '${_workingDaysApplied!.toStringAsFixed(1)} day(s)'
                : 'Will be computed from selected dates',
          ),
          const SizedBox(height: 10),
          Text(
            'INCLUSIVE DATES',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Start Date',
                  value: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: 'End Date',
                  value: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommutationPanel({bool showSignature = false}) {
    return _paperPanel(
      title: '6.D COMMUTATION',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paperCheckRow(
            selected: _commutation == LeaveCommutationOption.notRequested,
            label: 'Not Requested',
            onTap: () => setState(
              () => _commutation = LeaveCommutationOption.notRequested,
            ),
          ),
          _paperCheckRow(
            selected: _commutation == LeaveCommutationOption.requested,
            label: 'Requested',
            onTap: () =>
                setState(() => _commutation = LeaveCommutationOption.requested),
          ),
          if (showSignature) ...[
            const SizedBox(height: 28),
            _buildApplicantSignatureBox(),
          ],
        ],
      ),
    );
  }

  Widget _buildApplicantSignatureBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Container(height: 1, color: Colors.black54),
        const SizedBox(height: 6),
        Text(
          '(Signature of Applicant)',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildCertificationPanel() {
    return _paperPanel(
      title: '7.A CERTIFICATION OF LEAVE CREDITS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'As of ____________',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(color: Colors.black54, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: const [
              TableRow(
                children: [
                  _TableCell(text: ''),
                  _TableCell(text: 'Vacation Leave', bold: true),
                  _TableCell(text: 'Sick Leave', bold: true),
                ],
              ),
              TableRow(
                children: [
                  _TableCell(text: 'Total Earned'),
                  _TableCell(text: '—'),
                  _TableCell(text: '—'),
                ],
              ),
              TableRow(
                children: [
                  _TableCell(text: 'Less this application'),
                  _TableCell(text: '—'),
                  _TableCell(text: '—'),
                ],
              ),
              TableRow(
                children: [
                  _TableCell(text: 'Balance'),
                  _TableCell(text: '—'),
                  _TableCell(text: '—'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(height: 1, color: Colors.black54),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '(Authorized HR Officer)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationPanel() {
    return _paperPanel(
      title: '7.B RECOMMENDATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paperStaticCheckRow(label: 'For approval'),
          const SizedBox(height: 8),
          _paperStaticCheckRow(label: 'For disapproval due to'),
          const SizedBox(height: 10),
          _section7TextDisplay(
            widget.initialRequest?.recommendationRemarks,
            minLines: 3,
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.black54),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '(Authorized Officer)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedDisapprovedSection({required bool compact}) {
    final req = widget.initialRequest;
    final withPay = req?.approvedDaysWithPay;
    final withoutPay = req?.approvedDaysWithoutPay;
    final others = req?.approvedOtherDetails;
    final approvedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _approvalLine(
          withPay != null
              ? '${withPay.toStringAsFixed(1)} days with pay'
              : '_______ days with pay',
        ),
        const SizedBox(height: 8),
        _approvalLine(
          withoutPay != null
              ? '${withoutPay.toStringAsFixed(1)} days without pay'
              : '_______ days without pay',
        ),
        const SizedBox(height: 8),
        _approvalLine(
          others != null && others.isNotEmpty
              ? '$others'
              : '_______ others (Specify)',
        ),
      ],
    );
    final disapprovedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section7TextDisplay(
          widget.initialRequest?.disapprovalReason,
          minLines: 4,
        ),
      ],
    );
    final signatureBlock = Column(
      children: [
        const SizedBox(height: 24),
        Container(height: 1, color: Colors.black54),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '(Approving Authority)',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paperPanel(title: '7.C APPROVED FOR', child: approvedContent),
          const SizedBox(height: 12),
          _paperPanel(
            title: '7.D DISAPPROVED DUE TO',
            child: disapprovedContent,
          ),
          signatureBlock,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _paperPanelSection(
                    title: '7.C APPROVED FOR',
                    child: approvedContent,
                  ),
                ),
                Expanded(
                  child: _paperPanelSection(
                    title: '7.D DISAPPROVED DUE TO',
                    child: disapprovedContent,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: signatureBlock),
        ],
      ),
    );
  }

  Widget _paperPanelSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            border: const Border(
              bottom: BorderSide(color: Colors.black, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(10), child: child),
      ],
    );
  }

  Widget _paperPanel({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: const Border(
                bottom: BorderSide(color: Colors.black, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }

  Widget _paperFieldRow1Left({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. OFFICE/DEPARTMENT - DISTRICT/SCHOOL',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _paperFieldRow1Right({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. NAME (Last) (First) (Middle)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _paperFieldRow2Item({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  InputDecoration _paperUnderlineDecoration() {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.black, width: 1.2),
      ),
    );
  }

  Widget _paperUnderlineReadOnly(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 1)),
      ),
      child: Text(
        value,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      ),
    );
  }

  Widget _paperNameField({
    required String hint,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _paperUnderlineDecoration().copyWith(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.black45, fontSize: 12),
      ),
    );
  }

  Widget _paperSectionHeader(String title) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        border: const Border.symmetric(
          horizontal: BorderSide(color: Colors.black, width: 1),
        ),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _paperCheckRow({
    required bool selected,
    required String label,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final textColor = enabled ? AppTheme.textPrimary : Colors.black45;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54, width: 1),
                color: selected ? AppTheme.primaryNavy.withOpacity(0.15) : null,
              ),
              child: selected
                  ? Icon(Icons.check, size: 12, color: AppTheme.primaryNavyDark)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paperStaticCheckRow({required String label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black54, width: 1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _paperSubheading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _placeholderLines(int count) {
    return Column(
      children: List.generate(
        count,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 1,
          color: Colors.black45,
        ),
      ),
    );
  }

  /// Displays section 7 admin text (recommendation/disapproval) when present,
  /// otherwise placeholder lines for the paper form layout.
  Widget _section7TextDisplay(String? text, {required int minLines}) {
    final hasText = text != null && text.trim().isNotEmpty;
    if (hasText) {
      return SelectableText(
        text.trim(),
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12.5,
          height: 1.4,
        ),
      );
    }
    return _placeholderLines(minLines);
  }

  Widget _approvalLine(String text) {
    return Text(
      text,
      style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _saveDraft() async {
    final request = _buildRequest(status: LeaveRequestStatus.draft);
    if (request == null) return;
    if (widget.onSaveDraft == null) {
      _showMessage('Draft is ready. Wire the save callback next.');
      return;
    }
    await _runAction(
      action: () => widget.onSaveDraft!(request),
      successMessage: 'Leave request draft saved.',
    );
  }

  Future<void> _submitRequest() async {
    if (!_validateForm()) return;
    final request = _buildRequest(status: LeaveRequestStatus.pending);
    if (request == null) return;
    if (widget.onSubmitRequest == null) {
      _showMessage('Request is valid. Wire the submit callback next.');
      return;
    }
    await _runAction(
      action: () => widget.onSubmitRequest!(request),
      successMessage: 'Leave request submitted.',
    );
  }

  Future<void> _runAction({
    required Future<bool> Function() action,
    required String successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        _showMessage(successMessage);
        Navigator.of(context).pop(true);
      } else {
        final providerError = context.read<LeaveProvider>().error;
        _showMessage(
          providerError != null && providerError.trim().isNotEmpty
              ? providerError
              : 'Action could not be completed.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validateForm() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return false;
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select both start and end dates.');
      return false;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showMessage('End date cannot be earlier than start date.');
      return false;
    }
    if (_usesLocationDetails && _locationOption == null) {
      _showMessage('Please choose the location for this leave request.');
      return false;
    }
    if (_leaveType == LeaveType.sickLeave && _sickLeaveNature == null) {
      _showMessage('Please choose the sick leave nature.');
      return false;
    }
    if (_leaveType == LeaveType.studyLeave && _studyPurpose == null) {
      _showMessage('Please choose the study leave purpose.');
      return false;
    }
    return true;
  }

  LeaveRequest? _buildRequest({required LeaveRequestStatus status}) {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      _showMessage('No logged-in user found.');
      return null;
    }

    final fullName = [
      _lastNameController.text.trim(),
      _firstNameController.text.trim(),
      _middleNameController.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return LeaveRequest(
      id: widget.initialRequest?.id,
      userId: user.id,
      employeeName: fullName.isNotEmpty ? fullName : auth.displayName,
      officeDepartment: _officeDepartmentController.text.trim(),
      positionTitle: _positionTitleController.text.trim(),
      salary: double.tryParse(_salaryController.text.trim()),
      dateFiled: widget.initialRequest?.dateFiled ?? DateTime.now(),
      leaveType: _leaveType,
      customLeaveTypeText: _leaveType.requiresCustomDescription
          ? _trimOrNull(_customLeaveTypeController.text)
          : null,
      startDate: _startDate,
      endDate: _endDate,
      workingDaysApplied: _workingDaysApplied,
      reason: _trimOrNull(_reasonController.text),
      locationOption: _locationOption,
      locationDetails: _usesLocationDetails
          ? _trimOrNull(_locationDetailsController.text)
          : null,
      sickLeaveNature: _leaveType == LeaveType.sickLeave
          ? _sickLeaveNature
          : null,
      sickIllnessDetails: _leaveType == LeaveType.sickLeave
          ? _trimOrNull(_sickIllnessController.text)
          : null,
      womenIllnessDetails: _leaveType == LeaveType.specialLeaveBenefitsForWomen
          ? _trimOrNull(_womenIllnessController.text)
          : null,
      studyPurpose: _leaveType == LeaveType.studyLeave ? _studyPurpose : null,
      studyPurposeDetails: _leaveType == LeaveType.studyLeave
          ? _trimOrNull(_studyPurposeDetailsController.text)
          : null,
      otherPurpose: _leaveType == LeaveType.others ? _otherPurpose : null,
      otherPurposeDetails: _leaveType == LeaveType.others
          ? _trimOrNull(_otherPurposeDetailsController.text)
          : null,
      attachmentPath: widget.initialRequest?.attachmentPath,
      attachmentName: widget.initialRequest?.attachmentName,
      commutation: _commutation,
      status: status,
      createdAt: widget.initialRequest?.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  double? get _workingDaysApplied {
    if (_startDate == null || _endDate == null) return null;
    if (_endDate!.isBefore(_startDate!)) return null;
    var current = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
    );
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    var count = 0;
    while (!current.isAfter(end)) {
      if (current.weekday != DateTime.saturday &&
          current.weekday != DateTime.sunday) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  ({String last, String first, String middle}) _parseNameToLastFirstMiddle(
    String displayName,
  ) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (last: '', first: '', middle: '');
    if (parts.length == 1) return (last: '', first: parts[0], middle: '');
    if (parts.length == 2) return (last: parts[1], first: parts[0], middle: '');
    return (
      last: parts.sublist(2).join(' '),
      first: parts[0],
      middle: parts[1],
    );
  }

  bool get _usesLocationDetails =>
      _leaveType == LeaveType.vacationLeave ||
      _leaveType == LeaveType.specialPrivilegeLeave;

  String? _requiredValidator(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  void _resetConditionalSelectionsForType(LeaveType value) {
    if (value != LeaveType.vacationLeave &&
        value != LeaveType.specialPrivilegeLeave) {
      _locationOption = null;
      _locationDetailsController.clear();
    }
    if (value != LeaveType.sickLeave) {
      _sickLeaveNature = null;
      _sickIllnessController.clear();
    }
    if (value != LeaveType.specialLeaveBenefitsForWomen) {
      _womenIllnessController.clear();
    }
    if (value != LeaveType.studyLeave) {
      _studyPurpose = null;
      _studyPurposeDetailsController.clear();
    }
    if (value != LeaveType.others) {
      _otherPurpose = null;
      _otherPurposeDetailsController.clear();
      _customLeaveTypeController.clear();
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: const BorderSide(color: Colors.black54),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: const BorderSide(color: Colors.black54),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: AppTheme.primaryNavyDark, width: 1.2),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: !enabled,
      decoration: _inputDecoration(label).copyWith(enabled: enabled),
    );
  }

  Widget _buildReadOnlyField({required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppTheme.offWhite,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
        ),
        child: Text(
          value == null ? 'Select date' : _formatDate(value!),
          style: TextStyle(
            color: value == null
                ? AppTheme.textSecondary
                : AppTheme.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.text, this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}
