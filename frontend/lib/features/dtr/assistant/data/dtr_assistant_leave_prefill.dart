import 'package:hrms_plaridel/features/dtr/assistant/data/dtr_assistant_message_model.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

LeaveRequest leaveRequestFromAssistantAction(
  DtrAssistantAction action,
  String userId,
) {
  final payload = action.payload;
  final leaveType = _leaveTypeFromPayload(payload['leaveType']?.toString());
  final startDate = _dateFromPayload(payload['startDate']);
  final endDate = _dateFromPayload(payload['endDate']) ?? startDate;

  return LeaveRequest(
    userId: userId,
    leaveType: leaveType,
    leaveTypeName: leaveType.value,
    leaveTypeDisplayName: leaveType.displayName,
    startDate: startDate,
    endDate: endDate,
    workingDaysApplied: _calendarDayEstimate(startDate, endDate),
    reason: _textFromPayload(payload['reason']),
    locationOption: _locationOptionFromPayload(
      payload['locationOption']?.toString(),
    ),
    locationDetails: _textFromPayload(payload['locationDetails']),
    sickLeaveNature: sickLeaveNatureFromString(
      payload['sickLeaveNature']?.toString(),
    ),
    sickIllnessDetails: _textFromPayload(payload['sickIllnessDetails']),
    maternityDeliveryType: maternityDeliveryTypeFromString(
      payload['maternityDeliveryType']?.toString(),
    ),
    expectedDeliveryDate: _dateFromPayload(payload['expectedDeliveryDate']),
    childDeliveryDate: _dateFromPayload(payload['childDeliveryDate']),
    accidentDate: _dateFromPayload(payload['accidentDate']),
    calamityDate: _dateFromPayload(payload['calamityDate']),
    adoptionParentRole: adoptionParentRoleFromString(
      payload['adoptionParentRole']?.toString(),
    ),
    adoptionPlacementDate: _dateFromPayload(
      payload['adoptionPlacementDate'] ?? payload['adoptionFinalizationDate'],
    ),
    vawcSupportDocumentType: vawcSupportDocumentTypeFromString(
      payload['vawcSupportDocumentType']?.toString(),
    ),
    vawcCaseDetails: _textFromPayload(payload['vawcCaseDetails']),
    soloParentIdNumber: _textFromPayload(payload['soloParentIdNumber']),
    soloParentIdExpiryDate: _dateFromPayload(payload['soloParentIdExpiryDate']),
    womenIllnessDetails: _textFromPayload(payload['womenIllnessDetails']),
    studyPurpose: studyLeavePurposeFromString(
      payload['studyPurpose']?.toString(),
    ),
    studyPurposeDetails: _textFromPayload(
      payload['studyPurposeDetails'] ?? payload['studyDetails'],
    ),
    otherPurpose: leaveOtherPurposeFromString(
      payload['otherPurpose']?.toString(),
    ),
    otherPurposeDetails: _textFromPayload(payload['otherPurposeDetails']),
    commutation: leaveCommutationOptionFromString(
      payload['commutation']?.toString(),
    ),
    status: LeaveRequestStatus.draft,
  );
}

LeaveLocationOption? _locationOptionFromPayload(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'abroad') return LeaveLocationOption.abroad;
  if (normalized == 'within_philippines' || normalized == 'withinphilippines') {
    return LeaveLocationOption.withinPhilippines;
  }
  return leaveLocationOptionFromString(value);
}

LeaveType _leaveTypeFromPayload(String? value) {
  if (value == null || value.trim().isEmpty) {
    return LeaveType.vacationLeave;
  }
  final normalized = value.trim().toLowerCase();
  const aliases = <String, LeaveType>{
    'vawc': LeaveType.tenDayVawcLeave,
    '10-day vawc': LeaveType.tenDayVawcLeave,
    'calamity': LeaveType.specialEmergencyCalamityLeave,
    'special emergency': LeaveType.specialEmergencyCalamityLeave,
    'special leave for women': LeaveType.specialLeaveBenefitsForWomen,
    'forced leave': LeaveType.mandatoryForcedLeave,
    'spl': LeaveType.specialPrivilegeLeave,
  };
  return aliases[normalized] ?? leaveTypeFromString(value.trim());
}

String? _textFromPayload(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateFromPayload(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double? _calendarDayEstimate(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  final startOnly = DateTime(start.year, start.month, start.day);
  final endOnly = DateTime(end.year, end.month, end.day);
  if (endOnly.isBefore(startOnly)) return null;
  return endOnly.difference(startOnly).inDays + 1.0;
}
