import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/leave_guidance_widgets.dart';

typedef LeaveRequestAction = Future<bool> Function(LeaveRequest request);
typedef LeaveRequestAttachmentAction =
    Future<bool> Function(
      LeaveRequest request,
      List<int> fileBytes,
      String fileName,
    );

/// Modern, digital-first employee leave request form.
class LeaveRequestFormScreen extends StatefulWidget {
  const LeaveRequestFormScreen({
    super.key,
    this.initialRequest,
    this.onSaveDraft,
    this.onSubmitRequest,
    this.onSubmitRequestWithAttachment,
  });

  final LeaveRequest? initialRequest;
  final LeaveRequestAction? onSaveDraft;
  final LeaveRequestAction? onSubmitRequest;
  final LeaveRequestAttachmentAction? onSubmitRequestWithAttachment;

  @override
  State<LeaveRequestFormScreen> createState() => _LeaveRequestFormScreenState();
}

class _LeaveRequestFormScreenState extends State<LeaveRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  static const int _maxAttachmentBytes = 10 * 1024 * 1024;
  static const int _maternityMinimumNoticeDays = 30;
  static const _annualQuotaTypes = {
    'specialPrivilegeLeave',
    'paternityLeave',
    'maternityLeave',
    'soloParentLeave',
    'tenDayVawcLeave',
    'specialEmergencyCalamityLeave',
    'specialLeaveBenefitsForWomen',
    'rehabilitationPrivilege',
    'studyLeave',
  };

  late LeaveType _leaveType;
  late String _leaveTypeName;
  List<LeaveTypeDefinition> _leaveTypeDefinitions = const [];
  List<LeaveBalance> _creditBalances = const [];
  List<LeaveRequest> _creditRequests = const [];
  bool _loadingLeaveTypes = false;
  bool _loadingCreditContext = false;
  LeaveLocationOption? _locationOption;
  SickLeaveNature? _sickLeaveNature;
  MaternityDeliveryType? _maternityDeliveryType;
  DateTime? _expectedDeliveryDate;
  DateTime? _childDeliveryDate;
  DateTime? _accidentDate;
  DateTime? _calamityDate;
  StudyLeavePurpose? _studyPurpose;
  LeaveOtherPurpose? _otherPurpose;
  LeaveCommutationOption _commutation = LeaveCommutationOption.notRequested;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _busy = false;
  LeaveRequest? _savedRequest;
  bool _attachmentUploading = false;
  List<int>? _pendingAttachmentBytes;
  String? _pendingAttachmentName;
  bool _workingDaysLoading = false;
  String? _workingDaysHelperText;
  int _workingDaysRequestSerial = 0;

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
    _leaveTypeName = initial?.effectiveLeaveTypeName ?? _leaveType.value;
    _locationOption = initial?.locationOption;
    _sickLeaveNature = initial?.sickLeaveNature;
    _maternityDeliveryType = initial?.maternityDeliveryType;
    _expectedDeliveryDate = initial?.expectedDeliveryDate;
    _childDeliveryDate = initial?.childDeliveryDate;
    _accidentDate = initial?.accidentDate;
    _calamityDate = initial?.calamityDate;
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
    _coerceSelectedLeaveTypeForAccount();
    _loadLeaveTypes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCreditContext();
      if (_startDate != null &&
          _endDate != null &&
          initial?.workingDaysApplied == null) {
        _syncWorkingDaysFromDates();
      }
    });
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
    final messenger = _messengerKey.currentState;
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _resetConditionalSelectionsForType(LeaveType type) {
    _locationOption = null;
    _sickLeaveNature = null;
    _maternityDeliveryType = null;
    _expectedDeliveryDate = null;
    _childDeliveryDate = null;
    _accidentDate = null;
    _calamityDate = null;
    _studyPurpose = null;
    _otherPurpose = null;
    _customLeaveTypeController.clear();
    _locationDetailsController.clear();
    _sickIllnessController.clear();
    _womenIllnessController.clear();
    _studyPurposeDetailsController.clear();
    _otherPurposeDetailsController.clear();
  }

  LeaveTypeDefinition? get _selectedLeaveTypeDefinition {
    for (final item in _leaveTypeDefinitions) {
      if (item.name == _leaveTypeName) return item;
    }
    return null;
  }

  String get _selectedLeaveTypeLabel {
    final def = _selectedLeaveTypeDefinition;
    if (def != null) return def.displayName;
    if (_leaveType == LeaveType.others) {
      final custom = _customLeaveTypeController.text.trim();
      if (custom.isNotEmpty) return custom;
    }
    return _leaveType.displayName;
  }

  bool get _selectedRequiresAttachment {
    final def = _selectedLeaveTypeDefinition;
    return def?.requiresAttachment ?? _leaveType.requiresAttachment;
  }

  bool get _selectedAllowsPastDates {
    final def = _selectedLeaveTypeDefinition;
    return def?.allowsPastDates ?? _leaveType.allowsPastDates;
  }

  double? get _selectedMaxDays {
    final maternityMaxDays = maxWorkingDaysForLeaveDetails(
      _leaveType,
      maternityDeliveryType: _maternityDeliveryType,
    );
    if (_leaveType == LeaveType.maternityLeave) {
      return maternityMaxDays?.toDouble();
    }
    final def = _selectedLeaveTypeDefinition;
    return def?.maxDays ?? _leaveType.maxDays?.toDouble();
  }

  int? get _selectedMinimumAdvanceDays {
    final days = _selectedLeaveTypeDefinition?.minimumAdvanceDays;
    if (days == null || days <= 0) return null;
    return days;
  }

  String? _normalizedAccountSex() {
    final sex = context.read<AuthProvider>().user?.sex?.trim().toLowerCase();
    if (sex == null || sex.isEmpty) return null;
    if (sex == 'f' || sex == 'female') return 'female';
    if (sex == 'm' || sex == 'male') return 'male';
    return sex;
  }

  String _defaultSexEligibilityForLeaveType(LeaveType type) {
    switch (type) {
      case LeaveType.maternityLeave:
      case LeaveType.specialLeaveBenefitsForWomen:
      case LeaveType.tenDayVawcLeave:
        return 'female';
      case LeaveType.paternityLeave:
        return 'male';
      default:
        return 'any';
    }
  }

  String? _accountEligibilityMessage({
    required String label,
    required String sexEligibility,
  }) {
    final sex = _normalizedAccountSex();
    final normalized = normalizeLeaveTypeSexEligibility(sexEligibility);
    if (normalized == 'female') {
      if (sex == null) {
        return '$label requires your profile sex to be set to Female. Please update your profile or contact HR.';
      }
      if (sex != 'female') {
        return '$label can only be filed by female accounts.';
      }
    }
    if (normalized == 'male') {
      if (sex == null) {
        return '$label requires your profile sex to be set to Male. Please update your profile or contact HR.';
      }
      if (sex != 'male') {
        return '$label can only be filed by male accounts.';
      }
    }
    return null;
  }

  String? _leaveTypeAccountEligibilityMessage(LeaveType type) {
    return _accountEligibilityMessage(
      label: type.displayName,
      sexEligibility: _defaultSexEligibilityForLeaveType(type),
    );
  }

  String? _leaveTypeDefinitionAccountEligibilityMessage(
    LeaveTypeDefinition definition,
  ) {
    return _accountEligibilityMessage(
      label: definition.displayName,
      sexEligibility: definition.sexEligibility,
    );
  }

  String? _selectedAccountEligibilityMessage() {
    final definition = _selectedLeaveTypeDefinition;
    if (definition != null) {
      return _leaveTypeDefinitionAccountEligibilityMessage(definition);
    }
    return _leaveTypeAccountEligibilityMessage(_leaveType);
  }

  bool _isLeaveTypeAllowedForAccount(LeaveType type) {
    return _leaveTypeAccountEligibilityMessage(type) == null;
  }

  bool _isLeaveTypeDefinitionAllowedForAccount(LeaveTypeDefinition definition) {
    return _leaveTypeDefinitionAccountEligibilityMessage(definition) == null;
  }

  void _coerceSelectedLeaveTypeForAccount() {
    if (_isLeaveTypeAllowedForAccount(_leaveType)) return;
    _leaveType = LeaveType.vacationLeave;
    _leaveTypeName = LeaveType.vacationLeave.value;
    _resetConditionalSelectionsForType(_leaveType);
  }

  Future<void> _loadLeaveTypes() async {
    setState(() => _loadingLeaveTypes = true);
    try {
      final items = await LeaveTypeDefinitionCache.instance
          .listActiveEmployeeTypes();
      if (!mounted) return;
      setState(() {
        final allowedItems = items
            .where(_isLeaveTypeDefinitionAllowedForAccount)
            .toList();
        _leaveTypeDefinitions = allowedItems;
        _loadingLeaveTypes = false;
        final selectedExists = allowedItems.any(
          (item) => item.name == _leaveTypeName,
        );
        if (!selectedExists && allowedItems.isNotEmpty) {
          final fallback = allowedItems.firstWhere(
            (item) => item.name == LeaveType.vacationLeave.value,
            orElse: () => allowedItems.first,
          );
          _selectLeaveTypeDefinition(fallback, resetDetails: false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLeaveTypes = false);
    }
  }

  Future<void> _loadCreditContext() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    setState(() => _loadingCreditContext = true);
    try {
      final repository = context.read<LeaveProvider>().repository;
      final balancesFuture = repository.getBalancesForUser(userId);
      final requestsFuture = repository.listMyRequests(userId, limit: 500);
      final balances = await balancesFuture;
      final requests = await requestsFuture;
      if (!mounted) return;
      setState(() {
        _creditBalances = balances;
        _creditRequests = requests;
        _loadingCreditContext = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCreditContext = false);
    }
  }

  void _selectLeaveTypeDefinition(
    LeaveTypeDefinition definition, {
    bool resetDetails = true,
  }) {
    final nextType = leaveTypeFromString(definition.name);
    _leaveTypeName = definition.name;
    _leaveType = nextType;
    if (nextType == LeaveType.others &&
        definition.name != LeaveType.others.value) {
      _customLeaveTypeController.text = definition.displayName;
    } else if (nextType != LeaveType.others) {
      _customLeaveTypeController.clear();
    }
    if (resetDetails) _resetConditionalSelectionsForType(nextType);
    if (nextType == LeaveType.others &&
        definition.name != LeaveType.others.value) {
      _customLeaveTypeController.text = definition.displayName;
    }
  }

  LeaveTypeDefinition? _definitionForName(String name) {
    for (final item in _leaveTypeDefinitions) {
      if (item.name == name) return item;
    }
    return null;
  }

  List<DropdownMenuItem<String>> _leaveTypeDropdownItems() {
    if (_leaveTypeDefinitions.isNotEmpty) {
      final items = _leaveTypeDefinitions
          .where(
            (item) =>
                _isLeaveTypeDefinitionAllowedForAccount(item) &&
                (item.employeeCanFile && !item.adminOnly),
          )
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.name,
              child: Text(item.displayName),
            ),
          )
          .toList();
      if (!items.any((item) => item.value == _leaveTypeName)) {
        items.add(
          DropdownMenuItem<String>(
            value: _leaveTypeName,
            child: Text(_selectedLeaveTypeLabel),
          ),
        );
      }
      return items;
    }
    return LeaveType.values
        .where((t) => t.employeeCanFile && _isLeaveTypeAllowedForAccount(t))
        .map(
          (t) => DropdownMenuItem<String>(
            value: t.value,
            child: Text(t.displayName),
          ),
        )
        .toList();
  }

  String get _selectedCreditPolicy {
    final raw = _selectedLeaveTypeDefinition?.balanceLedgerType.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return switch (_leaveType) {
      LeaveType.vacationLeave => 'vacationLeave',
      LeaveType.sickLeave => 'sickLeave',
      LeaveType.mandatoryForcedLeave => 'vacationLeave',
      _ => 'none',
    };
  }

  String get _selectedCreditBucket {
    final policy = _selectedCreditPolicy;
    return policy == 'ownBalance' ? _leaveTypeName : policy;
  }

  LeaveBalance? _balanceForBucket(String bucket) {
    for (final balance in _creditBalances) {
      if (balance.effectiveLeaveTypeName == bucket) return balance;
    }
    return null;
  }

  double _annualUsageForYear(
    String leaveTypeName,
    int year, {
    required bool pending,
  }) {
    final currentId = (_savedRequest ?? widget.initialRequest)?.id;
    return _creditRequests
        .where((request) {
          if (request.effectiveLeaveTypeName != leaveTypeName) {
            return false;
          }
          if (currentId != null &&
              currentId.isNotEmpty &&
              request.id == currentId) {
            return false;
          }
          final matchesStatus = pending
              ? request.status.isPending
              : request.status == LeaveRequestStatus.approved;
          if (!matchesStatus) {
            return false;
          }
          final start = request.startDate;
          final end = request.endDate;
          if (start == null || end == null) return false;
          return start.year <= year && end.year >= year;
        })
        .fold<double>(0, (total, request) {
          final days = _workingDaysInYear(
            request.startDate,
            request.endDate,
            year,
          );
          return total + (days > 0 ? days : request.workingDaysApplied ?? 0);
        });
  }

  double _workingDaysInYear(DateTime? start, DateTime? end, int year) {
    if (start == null || end == null) return 0;
    var d = DateTime(
      start.year < year ? year : start.year,
      start.year < year ? 1 : start.month,
      start.year < year ? 1 : start.day,
    );
    final last = DateTime(
      end.year > year ? year : end.year,
      end.year > year ? 12 : end.month,
      end.year > year ? 31 : end.day,
    );
    var count = 0;
    while (!d.isAfter(last)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        count += 1;
      }
      d = d.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  String _formatDays(double days) {
    return days % 1 == 0 ? days.toStringAsFixed(0) : days.toStringAsFixed(1);
  }

  Future<void> _saveDraft() async {
    if (!_formKey.currentState!.validate()) return;
    final accountEligibilityMessage = _selectedAccountEligibilityMessage();
    if (accountEligibilityMessage != null) {
      _showMessage(accountEligibilityMessage);
      return;
    }
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select date(s)');
      return;
    }
    if (!_validateSelectedDates()) return;
    if (_workingDaysLoading) {
      _showMessage('Please wait while working days are computed.');
      return;
    }
    await _submit(isDraft: true);
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    final accountEligibilityMessage = _selectedAccountEligibilityMessage();
    if (accountEligibilityMessage != null) {
      _showMessage(accountEligibilityMessage);
      return;
    }
    if (_startDate == null || _endDate == null) {
      _showMessage('Please select start and end dates');
      return;
    }
    if (!_validateSelectedDates()) return;

    if (_workingDaysLoading) {
      _showMessage('Please wait while working days are computed.');
      return;
    }
    final entered = _currentWorkingDaysApplied;
    if (entered == null) {
      _showMessage('Please enter a valid number of working days.');
      return;
    }
    if (entered <= 0) {
      _showMessage('Working days must be greater than 0.');
      return;
    }

    if (_leaveType == LeaveType.maternityLeave &&
        _maternityDeliveryType == null) {
      _showMessage('Please choose the maternity leave classification.');
      return;
    }
    if (!_validateEventDateRules()) return;
    if (_shouldShowAttachmentSection() && !_hasAttachment()) {
      _showMessage('Attachment is required for this leave type.');
      return;
    }

    await _submit(isDraft: false);
  }

  double? get _currentWorkingDaysApplied =>
      double.tryParse(_workingDaysController.text.trim());

  /// Local fallback only. The backend recomputes using assigned shift working
  /// days and holidays before saving/submitting.
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

  String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatWorkingDays(num days) =>
      days % 1 == 0 ? days.toStringAsFixed(0) : days.toStringAsFixed(1);

  Future<void> _syncWorkingDaysFromDates() async {
    final start = _startDate;
    final end = _endDate;
    final serial = ++_workingDaysRequestSerial;
    if (start == null || end == null || end.isBefore(start)) {
      if (!mounted) return;
      setState(() {
        _workingDaysLoading = false;
        _workingDaysHelperText = 'Select dates to auto-compute';
        _workingDaysController.clear();
      });
      return;
    }

    final fallback = _computeWorkingDays();
    setState(() {
      _workingDaysLoading = true;
      _workingDaysHelperText = 'Computing from assigned shift and holidays...';
      _workingDaysController.text = fallback?.toString() ?? '';
    });

    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/working-days',
        queryParameters: {
          'start_date': _dateOnly(start),
          'end_date': _dateOnly(end),
        },
      );
      final data = res.data ?? const <String, dynamic>{};
      final raw = data['working_days_applied'] ?? data['workingDaysApplied'];
      final days = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (!mounted || serial != _workingDaysRequestSerial) return;
      if (days == null) {
        setState(() {
          _workingDaysLoading = false;
          _workingDaysHelperText =
              'Could not compute from shift; using Mon-Fri fallback';
        });
        return;
      }
      final source = (data['schedule_source'] ?? '').toString();
      final helper = switch (source) {
        'shift' => 'Auto-applied from assigned shift and holidays',
        'assignment_fallback' =>
          'No shift working days found; used Mon-Fri and holidays',
        'fallback' => 'No active assignment found; used Mon-Fri and holidays',
        _ => 'Auto-applied from schedule and holidays',
      };
      setState(() {
        _workingDaysLoading = false;
        _workingDaysController.text = _formatWorkingDays(days);
        _workingDaysHelperText = '$helper: ${_formatWorkingDays(days)} day(s)';
      });
    } catch (_) {
      if (!mounted || serial != _workingDaysRequestSerial) return;
      setState(() {
        _workingDaysLoading = false;
        _workingDaysHelperText =
            'Server estimate unavailable; using Mon-Fri fallback';
      });
    }
  }

  bool _hasAttachment() {
    if ((_pendingAttachmentName ?? '').trim().isNotEmpty &&
        _pendingAttachmentBytes != null) {
      return true;
    }
    final current = _savedRequest ?? widget.initialRequest;
    return (current?.attachmentName ?? '').trim().isNotEmpty;
  }

  bool _hasLeaveRequestId() {
    final id = (_savedRequest ?? widget.initialRequest)?.id;
    return id != null && id.trim().isNotEmpty;
  }

  /// Visible only when an attachment is mandatory: sick leave ≥5 working days,
  /// or any non–sick type with [LeaveType.requiresAttachment].
  bool _shouldShowAttachmentSection() {
    if (_leaveType == LeaveType.sickLeave) {
      return (_currentWorkingDaysApplied ?? 0) >= 5;
    }
    return _selectedRequiresAttachment;
  }

  bool _validateSelectedDates() {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return false;
    if (end.isBefore(start)) {
      _showMessage('End date cannot be earlier than start date.');
      return false;
    }
    if (!_selectedAllowsPastDates) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOnly = DateTime(start.year, start.month, start.day);
      if (startOnly.isBefore(today)) {
        _showMessage(
          'Past-date filing is not allowed for $_selectedLeaveTypeLabel.',
        );
        return false;
      }
    }
    final minimumAdvanceDays = _selectedMinimumAdvanceDays;
    if (minimumAdvanceDays != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOnly = DateTime(start.year, start.month, start.day);
      final calendarDaysBeforeStart = startOnly.difference(today).inDays;
      if (calendarDaysBeforeStart < minimumAdvanceDays) {
        final unit = minimumAdvanceDays == 1 ? 'day' : 'days';
        _showMessage(
          '$_selectedLeaveTypeLabel must be filed at least '
          '$minimumAdvanceDays $unit before the intended leave date.',
        );
        return false;
      }
    }
    return true;
  }

  DateTime _onlyDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  int _calendarDaysFrom(DateTime from, DateTime to) =>
      _onlyDate(to).difference(_onlyDate(from)).inDays;

  bool _validateEventDateRules() {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return false;

    if (_leaveType == LeaveType.maternityLeave) {
      final expected = _expectedDeliveryDate;
      if (expected == null) {
        _showMessage('Please enter the expected delivery date.');
        return false;
      }
      final noticeDays = _calendarDaysFrom(DateTime.now(), expected);
      if (noticeDays < _maternityMinimumNoticeDays) {
        _showMessage(
          'Maternity Leave must be filed at least $_maternityMinimumNoticeDays days before the expected delivery date.',
        );
        return false;
      }
      return true;
    }

    if (_leaveType == LeaveType.paternityLeave) {
      final delivery = _childDeliveryDate;
      if (delivery == null) {
        _showMessage('Please enter the child delivery or miscarriage date.');
        return false;
      }
      final startDiff = _calendarDaysFrom(delivery, start);
      final endDiff = _calendarDaysFrom(delivery, end);
      if (startDiff < 0) {
        _showMessage(
          'Paternity Leave cannot start before the child delivery date.',
        );
        return false;
      }
      if (endDiff > 60) {
        _showMessage(
          'Paternity Leave must be availed within 60 days from delivery.',
        );
        return false;
      }
      return true;
    }

    if (_leaveType == LeaveType.rehabilitationPrivilege) {
      final accident = _accidentDate;
      if (accident == null) {
        _showMessage('Please enter the accident date.');
        return false;
      }
      final today = _onlyDate(DateTime.now());
      final filingDiff = _calendarDaysFrom(accident, today);
      if (filingDiff < 0) {
        _showMessage('Accident date cannot be in the future.');
        return false;
      }
      if (filingDiff > 7) {
        _showMessage(
          'Rehabilitation Privilege must be filed within 1 week from the accident. Contact HR if a longer period is warranted.',
        );
        return false;
      }
      return true;
    }

    if (_leaveType == LeaveType.specialEmergencyCalamityLeave) {
      final calamity = _calamityDate;
      if (calamity == null) {
        _showMessage('Please enter the calamity/disaster occurrence date.');
        return false;
      }
      final startDiff = _calendarDaysFrom(calamity, start);
      final endDiff = _calendarDaysFrom(calamity, end);
      if (startDiff < 0) {
        _showMessage(
          'Special Emergency Leave cannot start before the calamity date.',
        );
        return false;
      }
      if (endDiff > 30) {
        _showMessage(
          'Special Emergency Leave must be used within 30 days from the calamity occurrence.',
        );
        return false;
      }
      return true;
    }

    return true;
  }

  String _maternityExpectedDeliveryHelper() {
    final expected = _expectedDeliveryDate;
    if (expected == null) {
      return 'Submission requires at least 30 days before the expected delivery date.';
    }
    final diff = _calendarDaysFrom(DateTime.now(), expected);
    if (diff >= _maternityMinimumNoticeDays) {
      return 'Meets the 30-day HR notice window.';
    }
    return 'Less than 30 days before expected delivery; submission will be blocked.';
  }

  /// Fills CSC header fields (name, office, position, salary, date filed) from
  /// auth + active assignment + employee profile when the request does not
  /// already have them (e.g. first save).
  Future<
    ({
      String employeeName,
      String? officeDepartment,
      String? positionTitle,
      double? salary,
      DateTime dateFiled,
    })
  >
  _loadEmployeeHeaderSnapshot({
    required String userId,
    required AuthProvider auth,
  }) async {
    final authName = auth.user?.fullName?.trim();
    final display = auth.displayName.trim();
    var employeeName = (authName != null && authName.isNotEmpty)
        ? authName
        : display;

    String? officeDepartment;
    String? positionTitle;
    double? salary;

    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/assignments?employee_id=$userId&status=Active',
      );
      final data = res.data;
      if (data != null && data.isNotEmpty) {
        final first = data.first as Map<String, dynamic>;
        officeDepartment = (first['department_name'] as String?)?.trim();
        positionTitle = (first['position_name'] as String?)?.trim();
      }
    } catch (_) {
      // Best-effort; fields stay from auth or empty.
    }

    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/employees/$userId',
      );
      final data = res.data;
      if (data != null) {
        final full = data['full_name']?.toString().trim();
        if (full != null && full.isNotEmpty) {
          employeeName = full;
        }
        final sg = data['salary_grade']?.toString().trim();
        if (sg != null && sg.isNotEmpty) {
          final parsed = double.tryParse(sg);
          if (parsed != null) {
            salary = parsed;
          }
        }
      }
    } catch (_) {
      // Salary / name refinement optional.
    }

    final initial = widget.initialRequest;
    final existingFiled = _savedRequest?.dateFiled ?? initial?.dateFiled;
    final today = DateTime.now();
    final dateFiled = existingFiled != null
        ? DateTime(existingFiled.year, existingFiled.month, existingFiled.day)
        : DateTime(today.year, today.month, today.day);

    return (
      employeeName: employeeName,
      officeDepartment: officeDepartment,
      positionTitle: positionTitle,
      salary: salary,
      dateFiled: dateFiled,
    );
  }

  Future<void> _submit({required bool isDraft}) async {
    setState(() => _busy = true);
    try {
      final initial = widget.initialRequest;
      final auth = context.read<AuthProvider>();
      final userId = auth.user!.id;

      // FIX #4: prefer the ID from _savedRequest (set on first save) so that
      // subsequent "Save Draft" clicks do a PUT (update) rather than another POST.
      final existingId = _savedRequest?.id ?? initial?.id;

      final header = await _loadEmployeeHeaderSnapshot(
        userId: userId,
        auth: auth,
      );
      final prior = _savedRequest ?? initial;
      String? coalesceStr(String? saved, String? incoming) {
        final a = (saved ?? '').trim();
        if (a.isNotEmpty) return a;
        final b = (incoming ?? '').trim();
        return b.isEmpty ? null : b;
      }

      final req = LeaveRequest(
        id: existingId,
        userId: userId,
        employeeName: coalesceStr(prior?.employeeName, header.employeeName),
        officeDepartment: coalesceStr(
          prior?.officeDepartment,
          header.officeDepartment,
        ),
        positionTitle: coalesceStr(prior?.positionTitle, header.positionTitle),
        salary: prior?.salary ?? header.salary,
        dateFiled: header.dateFiled,
        leaveType: _leaveType,
        leaveTypeName: _leaveTypeName,
        leaveTypeDisplayName: _selectedLeaveTypeLabel,
        customLeaveTypeText: _leaveType == LeaveType.others
            ? _selectedLeaveTypeLabel
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
        maternityDeliveryType: _leaveType == LeaveType.maternityLeave
            ? _maternityDeliveryType
            : null,
        expectedDeliveryDate: _leaveType == LeaveType.maternityLeave
            ? _expectedDeliveryDate
            : null,
        childDeliveryDate: _leaveType == LeaveType.paternityLeave
            ? _childDeliveryDate
            : null,
        accidentDate: _leaveType == LeaveType.rehabilitationPrivilege
            ? _accidentDate
            : null,
        calamityDate: _leaveType == LeaveType.specialEmergencyCalamityLeave
            ? _calamityDate
            : null,
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
        if (success) {
          final provider = context.read<LeaveProvider>();
          final saved = provider.selectedRequest;
          if (saved != null &&
              saved.id != null &&
              saved.id!.trim().isNotEmpty) {
            setState(() => _savedRequest = saved);
            if (_pendingAttachmentBytes != null &&
                (_pendingAttachmentName ?? '').trim().isNotEmpty) {
              final uploaded = await _uploadPendingAttachmentToRequest(
                saved.id!,
              );
              if (!mounted) return;
              if (!uploaded) return;
            }
          }
          _showMessage('Draft saved.');
        }
      } else {
        final pendingBytes = _pendingAttachmentBytes;
        final pendingName = _pendingAttachmentName?.trim();
        final hasPendingAttachment =
            pendingBytes != null &&
            pendingName != null &&
            pendingName.isNotEmpty;
        final hasExistingRequestId = (req.id ?? '').trim().isNotEmpty;
        if (hasPendingAttachment && !hasExistingRequestId) {
          final action = widget.onSubmitRequestWithAttachment;
          if (action == null) {
            _showMessage('Could not submit the attachment directly.');
            return;
          }
          final success = await action(req, pendingBytes, pendingName);
          if (!mounted) return;
          if (success) {
            Navigator.of(context).pop(kLeaveFormResultSubmitted);
          } else {
            final err = context.read<LeaveProvider>().error;
            _showMessage(
              (err != null && err.trim().isNotEmpty) ? err : 'Submit failed.',
            );
          }
        } else {
          final action = widget.onSubmitRequest;
          if (action != null) {
            final success = await action(req);
            if (!mounted) return;
            if (success) {
              Navigator.of(context).pop(kLeaveFormResultSubmitted);
            } else {
              final err = context.read<LeaveProvider>().error;
              _showMessage(
                (err != null && err.trim().isNotEmpty) ? err : 'Submit failed.',
              );
            }
          }
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

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: AppTheme.dashCanvasOf(context),
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
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select the type of leave and provide the necessary details.',
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
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
                            DropdownButtonFormField<String>(
                              initialValue: _leaveTypeName,
                              isExpanded: true,
                              decoration: _inputDecoration('Select Leave Type'),
                              items: _leaveTypeDropdownItems(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    final def = _definitionForName(val);
                                    if (def != null) {
                                      _selectLeaveTypeDefinition(def);
                                    } else {
                                      _leaveTypeName = val;
                                      _leaveType = leaveTypeFromString(val);
                                      _resetConditionalSelectionsForType(
                                        _leaveType,
                                      );
                                    }
                                  });
                                }
                              },
                            ),
                            if (_loadingLeaveTypes) ...[
                              const SizedBox(height: 8),
                              const LinearProgressIndicator(minHeight: 2),
                            ],

                            // B. Dynamic leave-type guidance
                            const SizedBox(height: 14),
                            LeaveTypeGuidanceCard(
                              leaveType: _leaveType,
                              definition: _selectedLeaveTypeDefinition,
                            ),
                            const SizedBox(height: 12),
                            _buildCreditPolicyPanel(),

                            if (_leaveType == LeaveType.others &&
                                _leaveTypeName == LeaveType.others.value) ...[
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
                                    onChanged: (d) {
                                      setState(() {
                                        _startDate = d;
                                      });
                                      _syncWorkingDaysFromDates();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildDatePicker(
                                    label: 'End Date',
                                    value: _endDate,
                                    onChanged: (d) {
                                      setState(() {
                                        _endDate = d;
                                      });
                                      _syncWorkingDaysFromDates();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // FIX #7: Auto-fill working days from the backend schedule calculation.
                            Builder(
                              builder: (context) {
                                final applied = _currentWorkingDaysApplied;
                                return TextFormField(
                                  controller: _workingDaysController,
                                  readOnly: true,
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration:
                                      _inputDecoration(
                                        'Number of Working Days Applied For',
                                      ).copyWith(
                                        prefixIcon: const Icon(
                                          Icons.calculate_outlined,
                                        ),
                                        suffixIcon: _workingDaysLoading
                                            ? const Padding(
                                                padding: EdgeInsets.all(14),
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                            : null,
                                        helperText:
                                            _workingDaysHelperText ??
                                            (applied != null
                                                ? 'Auto-applied from selected dates: ${_formatWorkingDays(applied)} day(s)'
                                                : 'Select dates to auto-compute'),
                                      ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    final entered = double.tryParse(val.trim());
                                    if (entered == null) {
                                      return 'Must be a number';
                                    }
                                    if (entered <= 0) {
                                      return 'Must be greater than 0';
                                    }
                                    // Warn about max days for leave type
                                    final maxDays = _selectedMaxDays;
                                    if (maxDays != null && entered > maxDays) {
                                      return '$_selectedLeaveTypeLabel allows max ${maxDays.toStringAsFixed(maxDays % 1 == 0 ? 0 : 1)} days';
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
                                Expanded(
                                  child: Text(
                                    'Requested Commutation of Leave',
                                    style: TextStyle(
                                      color: AppTheme.dashTextPrimaryOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_shouldShowAttachmentSection()) ...[
                              const Divider(height: 32),
                              _buildAttachmentSection(),
                            ],
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
      ),
    );
  }

  Widget _buildCreditPolicyPanel() {
    final policy = _selectedCreditPolicy;
    final isAnnualQuota = _annualQuotaTypes.contains(_leaveTypeName);

    IconData icon = Icons.info_outline_rounded;
    String title = 'Credit handling';
    String message;

    if (isAnnualQuota) {
      final year = _startDate?.year ?? DateTime.now().year;
      final balance = _balanceForBucket(_leaveTypeName);
      final entitlement = balance?.earnedDays ?? _selectedMaxDays;
      final approved = _annualUsageForYear(
        _leaveTypeName,
        year,
        pending: false,
      );
      final pending = _annualUsageForYear(_leaveTypeName, year, pending: true);
      final remaining = entitlement == null
          ? null
          : (entitlement - approved - pending).clamp(0, entitlement).toDouble();
      icon = Icons.event_available_outlined;
      title = _selectedLeaveTypeLabel;
      message = _loadingCreditContext
          ? 'Checking yearly entitlement...'
          : entitlement == null || remaining == null
          ? 'No annual entitlement information is available for $year.'
          : 'Annual entitlement: ${_formatDays(entitlement)} day(s) for $year. '
                'Approved usage: ${_formatDays(approved)}. '
                'Pending usage: ${_formatDays(pending)}. '
                'Remaining entitlement: ${_formatDays(remaining)} day(s). '
                'This leave does not deduct VL or SL credits.';
    } else if (policy == 'none') {
      icon = Icons.remove_done_outlined;
      message =
          'No leave credits required. This request will not deduct Vacation or Sick Leave credits.';
    } else {
      final bucket = _selectedCreditBucket;
      final balance = _balanceForBucket(bucket);
      final bucketLabel = switch (bucket) {
        'vacationLeave' => 'Vacation Leave',
        'sickLeave' => 'Sick Leave',
        _ => _selectedLeaveTypeLabel,
      };
      icon = Icons.account_balance_wallet_outlined;
      message = balance == null
          ? 'Deducts from $bucketLabel credits. No balance row is available yet.'
          : 'Deducts from $bucketLabel credits. Available: ${balance.availableDays.toStringAsFixed(1)} day(s), pending: ${balance.pendingDays.toStringAsFixed(1)}.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
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
    return AppTheme.dashInputDecoration(
      context,
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      radius: 8,
    );
  }

  Widget _buildHelperText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 12,
          height: 1.35,
        ),
      ),
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
        Text(
          'Location Option',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        RadioGroup<LeaveLocationOption>(
          groupValue: _locationOption,
          onChanged: (v) => setState(() => _locationOption = v),
          child: const Column(
            children: [
              RadioListTile<LeaveLocationOption>(
                title: Text('Within Philippines'),
                value: LeaveLocationOption.withinPhilippines,
              ),
              RadioListTile<LeaveLocationOption>(
                title: Text('Abroad'),
                value: LeaveLocationOption.abroad,
              ),
            ],
          ),
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
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        RadioGroup<SickLeaveNature>(
          groupValue: _sickLeaveNature,
          onChanged: (v) => setState(() => _sickLeaveNature = v),
          child: const Column(
            children: [
              RadioListTile<SickLeaveNature>(
                title: Text('In Hospital'),
                value: SickLeaveNature.inHospital,
              ),
              RadioListTile<SickLeaveNature>(
                title: Text('Out Patient'),
                value: SickLeaveNature.outPatient,
              ),
            ],
          ),
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
    } else if (_leaveType == LeaveType.maternityLeave) {
      children.addAll([
        const SizedBox(height: 16),
        _buildDatePicker(
          label: 'Expected Delivery Date',
          value: _expectedDeliveryDate,
          onChanged: (d) => setState(() => _expectedDeliveryDate = d),
        ),
        _buildHelperText(_maternityExpectedDeliveryHelper()),
        const SizedBox(height: 16),
        Text(
          'Maternity Leave Classification',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        for (final option in MaternityDeliveryType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _maternityDeliveryType = option),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _maternityDeliveryType == option
                        ? AppTheme.primaryNavy
                        : AppTheme.dashHairlineOf(context),
                  ),
                  color: _maternityDeliveryType == option
                      ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                      : AppTheme.dashPanelOf(context),
                ),
                child: Row(
                  children: [
                    Icon(
                      _maternityDeliveryType == option
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _maternityDeliveryType == option
                          ? AppTheme.primaryNavy
                          : AppTheme.dashTextSecondaryOf(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(option.displayName)),
                  ],
                ),
              ),
            ),
          ),
      ]);
    } else if (_leaveType == LeaveType.paternityLeave) {
      children.addAll([
        const SizedBox(height: 16),
        _buildDatePicker(
          label: 'Child Delivery / Miscarriage Date',
          value: _childDeliveryDate,
          onChanged: (d) => setState(() => _childDeliveryDate = d),
        ),
        _buildHelperText(
          'Paternity Leave must be availed within 60 days from this date.',
        ),
      ]);
    } else if (_leaveType == LeaveType.rehabilitationPrivilege) {
      children.addAll([
        const SizedBox(height: 16),
        _buildDatePicker(
          label: 'Accident Date',
          value: _accidentDate,
          onChanged: (d) => setState(() => _accidentDate = d),
        ),
        _buildHelperText(
          'Employee filing is allowed within 1 week from the accident. Contact HR if a longer period is warranted.',
        ),
      ]);
    } else if (_leaveType == LeaveType.specialEmergencyCalamityLeave) {
      children.addAll([
        const SizedBox(height: 16),
        _buildDatePicker(
          label: 'Calamity / Disaster Occurrence Date',
          value: _calamityDate,
          onChanged: (d) => setState(() => _calamityDate = d),
        ),
        _buildHelperText(
          'Special Emergency Leave must be used within 30 days from this occurrence.',
        ),
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
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
        ),
        RadioGroup<StudyLeavePurpose>(
          groupValue: _studyPurpose,
          onChanged: (v) => setState(() => _studyPurpose = v),
          child: const Column(
            children: [
              RadioListTile<StudyLeavePurpose>(
                title: Text('Completion of Master\'s Degree'),
                value: StudyLeavePurpose.completionOfMastersDegree,
              ),
              RadioListTile<StudyLeavePurpose>(
                title: Text('BAR / Board Examination Review'),
                value: StudyLeavePurpose.barBoardExaminationReview,
              ),
            ],
          ),
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
    final pendingName = _pendingAttachmentName?.trim();
    final hasPendingAttachment =
        pendingName != null &&
        pendingName.isNotEmpty &&
        _pendingAttachmentBytes != null;
    final savedAttachmentName = current?.attachmentName?.trim();
    final hasSavedAttachment =
        savedAttachmentName != null && savedAttachmentName.isNotEmpty;
    final hasAttachment = hasSavedAttachment || hasPendingAttachment;
    final attachmentLabel = hasSavedAttachment
        ? savedAttachmentName
        : pendingName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Attachments',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppTheme.dashTextPrimaryOf(context),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text(
                'Required',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[800],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _leaveType == LeaveType.sickLeave
              ? 'Medical certificate is required for sick leave exceeding 5 days. '
                    'PDF, JPG, PNG (max 10MB).'
              : 'A supporting document is required for $_selectedLeaveTypeLabel '
                    '(e.g. medical certificate, birth certificate). '
                    'PDF, JPG, PNG (max 10MB).',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 13,
          ),
        ),
        if (!_hasLeaveRequestId()) ...[
          const SizedBox(height: 8),
          Text(
            'The selected file will be submitted together with this request.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (hasAttachment)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.attach_file, color: AppTheme.primaryNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attachmentLabel ?? 'Selected attachment',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
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
    );
  }

  Future<void> _pickAndUploadAttachment() async {
    if (!_shouldShowAttachmentSection()) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      return;
    }
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes!;
    final name = file.name;
    if (name.isEmpty) return;
    if (bytes.length > _maxAttachmentBytes) {
      _showMessage('File too large. Max 10MB.');
      return;
    }

    final current = _savedRequest ?? widget.initialRequest;
    final requestId = current?.id;
    if (requestId == null || requestId.isEmpty) {
      setState(() {
        _pendingAttachmentBytes = bytes;
        _pendingAttachmentName = name;
      });
      _showMessage('Attachment selected.');
      return;
    }

    await _uploadAttachmentToRequest(
      requestId: requestId,
      fileBytes: bytes,
      fileName: name,
    );
  }

  Future<bool> _uploadPendingAttachmentToRequest(String requestId) async {
    final bytes = _pendingAttachmentBytes;
    final name = _pendingAttachmentName?.trim();
    if (bytes == null || name == null || name.isEmpty) return true;
    return _uploadAttachmentToRequest(
      requestId: requestId,
      fileBytes: bytes,
      fileName: name,
      clearPendingOnSuccess: true,
    );
  }

  Future<bool> _uploadAttachmentToRequest({
    required String requestId,
    required List<int> fileBytes,
    required String fileName,
    bool clearPendingOnSuccess = false,
  }) async {
    setState(() => _attachmentUploading = true);
    try {
      final provider = context.read<LeaveProvider>();
      final updated = await provider.attachFile(
        requestId: requestId,
        fileBytes: fileBytes,
        fileName: fileName,
      );
      if (!mounted) return false;
      if (updated != null) {
        setState(() {
          _savedRequest = updated;
          if (clearPendingOnSuccess) {
            _pendingAttachmentBytes = null;
            _pendingAttachmentName = null;
          }
          _attachmentUploading = false;
        });
        _showMessage('Attachment uploaded.');
        return true;
      } else {
        setState(() => _attachmentUploading = false);
        _showMessage(provider.error ?? 'Upload failed.');
        return false;
      }
    } catch (e) {
      if (mounted) setState(() => _attachmentUploading = false);
      if (mounted) _showMessage('Upload failed: $e');
      return false;
    }
  }

  Future<void> _removeAttachment() async {
    if (!_shouldShowAttachmentSection()) return;

    final current = _savedRequest ?? widget.initialRequest;
    final requestId = current?.id;
    if (requestId == null || requestId.isEmpty) {
      if (_pendingAttachmentBytes != null ||
          (_pendingAttachmentName ?? '').trim().isNotEmpty) {
        setState(() {
          _pendingAttachmentBytes = null;
          _pendingAttachmentName = null;
        });
        _showMessage('Attachment removed.');
      }
      return;
    }

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

/// Pop value from [LeaveRequestFormScreen] after a successful draft save or submit.
const String kLeaveFormResultDraftSaved = 'leave_draft_saved';
const String kLeaveFormResultSubmitted = 'leave_submitted';

void showLeaveFormSuccessSnackBar(BuildContext context, String result) {
  final text = result == kLeaveFormResultDraftSaved
      ? 'Draft saved successfully.'
      : result == kLeaveFormResultSubmitted
      ? 'Leave request submitted successfully.'
      : null;
  if (text == null) return;
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
  );
}
