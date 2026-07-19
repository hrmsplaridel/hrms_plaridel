import 'leave_type.dart';

/// Workflow status for one leave request.
enum LeaveRequestStatus {
  draft,
  pending, // legacy alias for pendingHr
  pendingDepartmentHead, // awaiting department head
  pendingHr, // awaiting HR/admin
  rejectedByDepartmentHead, // department head rejected
  rejectedByHr, // HR/admin rejected
  returned,
  approved,
  rejected, // legacy single-stage rejection
  cancelled,
}

extension LeaveRequestStatusExtension on LeaveRequestStatus {
  /// Return the snake_case value for API serialization.
  String get value => switch (this) {
    LeaveRequestStatus.draft => 'draft',
    LeaveRequestStatus.pending => 'pending',
    LeaveRequestStatus.pendingDepartmentHead => 'pending_department_head',
    LeaveRequestStatus.pendingHr => 'pending_hr',
    LeaveRequestStatus.rejectedByDepartmentHead =>
      'rejected_by_department_head',
    LeaveRequestStatus.rejectedByHr => 'rejected_by_hr',
    LeaveRequestStatus.returned => 'returned',
    LeaveRequestStatus.approved => 'approved',
    LeaveRequestStatus.rejected => 'rejected',
    LeaveRequestStatus.cancelled => 'cancelled',
  };

  String get displayName => switch (this) {
    LeaveRequestStatus.draft => 'Draft',
    LeaveRequestStatus.pending => 'Pending',
    LeaveRequestStatus.pendingDepartmentHead => 'Pending Department Head',
    LeaveRequestStatus.pendingHr => 'Pending HR',
    LeaveRequestStatus.rejectedByDepartmentHead =>
      'Rejected by Department Head',
    LeaveRequestStatus.rejectedByHr => 'Rejected by HR',
    LeaveRequestStatus.returned => 'Returned',
    LeaveRequestStatus.approved => 'Approved',
    LeaveRequestStatus.rejected => 'Rejected',
    LeaveRequestStatus.cancelled => 'Cancelled',
  };

  /// Whether this status is any kind of pending (useful for filtering).
  bool get isPending =>
      this == LeaveRequestStatus.pending ||
      this == LeaveRequestStatus.pendingDepartmentHead ||
      this == LeaveRequestStatus.pendingHr;

  /// Whether this status is any kind of rejection.
  bool get isRejected =>
      this == LeaveRequestStatus.rejected ||
      this == LeaveRequestStatus.rejectedByDepartmentHead ||
      this == LeaveRequestStatus.rejectedByHr;
}

LeaveRequestStatus leaveRequestStatusFromString(String? s) {
  if (s == null || s.isEmpty) return LeaveRequestStatus.pending;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in LeaveRequestStatus.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '');
    if (enumName == normalized || label == normalized) return e;
  }
  return LeaveRequestStatus.pending;
}

/// Section 6.D in the official form.
enum LeaveCommutationOption { notRequested, requested }

extension LeaveCommutationOptionExtension on LeaveCommutationOption {
  String get value => name;

  String get displayName => switch (this) {
    LeaveCommutationOption.notRequested => 'Not Requested',
    LeaveCommutationOption.requested => 'Requested',
  };
}

LeaveCommutationOption leaveCommutationOptionFromString(String? s) {
  if (s == null || s.isEmpty) {
    return LeaveCommutationOption.notRequested;
  }
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in LeaveCommutationOption.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '');
    if (enumName == normalized || label == normalized) return e;
  }
  return LeaveCommutationOption.notRequested;
}

/// One employee leave request, modeled after the CSC Application for Leave form.
class LeaveRequest {
  const LeaveRequest({
    this.id,
    required this.userId,
    this.employeeName,
    this.officeDepartment,
    this.positionTitle,
    this.salary,
    this.dateFiled,
    required this.leaveType,
    this.leaveTypeName,
    this.leaveTypeDisplayName,
    this.customLeaveTypeText,
    this.startDate,
    this.endDate,
    this.workingDaysApplied,
    this.reason,
    this.locationOption,
    this.locationDetails,
    this.sickLeaveNature,
    this.sickIllnessDetails,
    this.maternityDeliveryType,
    this.expectedDeliveryDate,
    this.childDeliveryDate,
    this.accidentDate,
    this.calamityDate,
    this.adoptionParentRole,
    this.adoptionPlacementDate,
    this.vawcSupportDocumentType,
    this.vawcCaseDetails,
    this.soloParentIdNumber,
    this.soloParentIdExpiryDate,
    this.womenIllnessDetails,
    this.studyPurpose,
    this.studyPurposeDetails,
    this.otherPurpose,
    this.otherPurposeDetails,
    this.commutation = LeaveCommutationOption.notRequested,
    this.attachmentPath,
    this.attachmentName,
    this.status = LeaveRequestStatus.pending,
    this.hrRemarks,
    this.recommendationRemarks,
    this.disapprovalReason,
    this.approvedDaysWithPay,
    this.approvedDaysWithoutPay,
    this.approvedOtherDetails,
    this.reviewerId,
    this.reviewerName,
    this.reviewerRole,
    this.reviewerTitle,
    this.reviewedAt,
    this.departmentHeadReviewerId,
    this.departmentHeadReviewerName,
    this.departmentHeadReviewedAt,
    this.departmentHeadRemarks,
    this.departmentHeadAction,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String userId;

  /// Snapshot fields copied from employee profile for the printable form.
  final String? employeeName;
  final String? officeDepartment;
  final String? positionTitle;
  final double? salary;
  final DateTime? dateFiled;

  /// Section 6.A and 6.B details.
  final LeaveType leaveType;
  final String? leaveTypeName;
  final String? leaveTypeDisplayName;
  final String? customLeaveTypeText;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? workingDaysApplied;
  final String? reason;

  final LeaveLocationOption? locationOption;
  final String? locationDetails;
  final SickLeaveNature? sickLeaveNature;
  final String? sickIllnessDetails;
  final MaternityDeliveryType? maternityDeliveryType;
  final DateTime? expectedDeliveryDate;
  final DateTime? childDeliveryDate;
  final DateTime? accidentDate;
  final DateTime? calamityDate;
  final AdoptionParentRole? adoptionParentRole;
  final DateTime? adoptionPlacementDate;
  final VawcSupportDocumentType? vawcSupportDocumentType;
  final String? vawcCaseDetails;
  final String? soloParentIdNumber;
  final DateTime? soloParentIdExpiryDate;
  final String? womenIllnessDetails;
  final StudyLeavePurpose? studyPurpose;
  final String? studyPurposeDetails;
  final LeaveOtherPurpose? otherPurpose;
  final String? otherPurposeDetails;
  final LeaveCommutationOption commutation;

  /// Supporting documents uploaded by the employee.
  final String? attachmentPath;
  final String? attachmentName;

  /// Review / approval state.
  final LeaveRequestStatus status;
  final String? hrRemarks;
  final String? recommendationRemarks;
  final String? disapprovalReason;
  final double? approvedDaysWithPay;
  final double? approvedDaysWithoutPay;
  final String? approvedOtherDetails;
  final String? reviewerId;
  final String? reviewerName;
  final String? reviewerRole;
  final String? reviewerTitle;
  final DateTime? reviewedAt;
  final String? departmentHeadReviewerId;
  final String? departmentHeadReviewerName;
  final DateTime? departmentHeadReviewedAt;
  final String? departmentHeadRemarks;
  final String? departmentHeadAction;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const String tableName = 'leave_requests';
  static const String storageBucket = 'leave-attachments';

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id']?.toString(),
      userId: json['user_id'] as String? ?? '',
      employeeName: json['employee_name']?.toString(),
      officeDepartment: json['office_department']?.toString(),
      positionTitle: json['position_title']?.toString(),
      salary: _parseDouble(json['salary']),
      dateFiled: _parseDate(json['date_filed']),
      leaveType: leaveTypeFromString(json['leave_type']?.toString()),
      leaveTypeName: json['leave_type']?.toString(),
      leaveTypeDisplayName: json['leave_type_display_name']?.toString(),
      customLeaveTypeText: json['custom_leave_type_text']?.toString(),
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
      workingDaysApplied: _parseDouble(json['working_days_applied']),
      reason: json['reason']?.toString(),
      locationOption: leaveLocationOptionFromString(
        json['location_option']?.toString(),
      ),
      locationDetails: json['location_details']?.toString(),
      sickLeaveNature: sickLeaveNatureFromString(
        json['sick_leave_nature']?.toString(),
      ),
      sickIllnessDetails: json['sick_illness_details']?.toString(),
      maternityDeliveryType: maternityDeliveryTypeFromString(
        json['maternity_delivery_type']?.toString() ??
            json['maternityDeliveryType']?.toString(),
      ),
      expectedDeliveryDate: _parseDate(
        json['expected_delivery_date'] ?? json['expectedDeliveryDate'],
      ),
      childDeliveryDate: _parseDate(
        json['child_delivery_date'] ??
            json['childDeliveryDate'] ??
            json['delivery_date'] ??
            json['deliveryDate'],
      ),
      accidentDate: _parseDate(json['accident_date'] ?? json['accidentDate']),
      calamityDate: _parseDate(
        json['calamity_date'] ??
            json['calamityDate'] ??
            json['calamity_occurrence_date'] ??
            json['calamityOccurrenceDate'],
      ),
      adoptionParentRole: adoptionParentRoleFromString(
        json['adoption_parent_role']?.toString() ??
            json['adoptionParentRole']?.toString() ??
            json['adoptive_parent_role']?.toString() ??
            json['adoptiveParentRole']?.toString(),
      ),
      adoptionPlacementDate: _parseDate(
        json['adoption_placement_date'] ??
            json['adoptionPlacementDate'] ??
            json['adoption_finalization_date'] ??
            json['adoptionFinalizationDate'] ??
            json['papa_date'] ??
            json['papaDate'],
      ),
      vawcSupportDocumentType: vawcSupportDocumentTypeFromString(
        json['vawc_support_document_type']?.toString() ??
            json['vawcSupportDocumentType']?.toString() ??
            json['vawc_document_type']?.toString() ??
            json['vawcDocumentType']?.toString(),
      ),
      vawcCaseDetails:
          json['vawc_case_details']?.toString() ??
          json['vawcCaseDetails']?.toString() ??
          json['vawc_protection_order_details']?.toString() ??
          json['vawcProtectionOrderDetails']?.toString(),
      soloParentIdNumber:
          json['solo_parent_id_number']?.toString() ??
          json['soloParentIdNumber']?.toString() ??
          json['solo_parent_id']?.toString() ??
          json['soloParentId']?.toString(),
      soloParentIdExpiryDate: _parseDate(
        json['solo_parent_id_expiry_date'] ??
            json['soloParentIdExpiryDate'] ??
            json['solo_parent_id_valid_until'] ??
            json['soloParentIdValidUntil'],
      ),
      womenIllnessDetails: json['women_illness_details']?.toString(),
      studyPurpose: studyLeavePurposeFromString(
        json['study_purpose']?.toString(),
      ),
      studyPurposeDetails: json['study_purpose_details']?.toString(),
      otherPurpose: leaveOtherPurposeFromString(
        json['other_purpose']?.toString(),
      ),
      otherPurposeDetails: json['other_purpose_details']?.toString(),
      commutation: leaveCommutationOptionFromString(
        json['commutation']?.toString(),
      ),
      attachmentPath: json['attachment_path']?.toString(),
      attachmentName: json['attachment_name']?.toString(),
      status: leaveRequestStatusFromString(json['status']?.toString()),
      hrRemarks: json['hr_remarks']?.toString(),
      recommendationRemarks: json['recommendation_remarks']?.toString(),
      disapprovalReason: json['disapproval_reason']?.toString(),
      approvedDaysWithPay: _parseDouble(json['approved_days_with_pay']),
      approvedDaysWithoutPay: _parseDouble(json['approved_days_without_pay']),
      approvedOtherDetails: json['approved_other_details']?.toString(),
      reviewerId: json['reviewer_id']?.toString(),
      reviewerName: json['reviewer_name']?.toString(),
      reviewerRole: json['reviewer_role']?.toString(),
      reviewerTitle: json['reviewer_title']?.toString(),
      reviewedAt: _parseDateTime(json['reviewed_at']),
      departmentHeadReviewerId: json['department_head_reviewer_id']?.toString(),
      departmentHeadReviewerName: json['department_head_reviewer_name']
          ?.toString(),
      departmentHeadReviewedAt: _parseDateTime(
        json['department_head_reviewed_at'],
      ),
      departmentHeadRemarks: json['department_head_remarks']?.toString(),
      departmentHeadAction: json['department_head_action']?.toString(),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'employee_name': _trimOrNull(employeeName),
      'office_department': _trimOrNull(officeDepartment),
      'position_title': _trimOrNull(positionTitle),
      'salary': salary,
      'date_filed': _dateOnly(dateFiled),
      'leave_type': effectiveLeaveTypeName,
      'leave_type_display_name': _trimOrNull(leaveTypeLabel),
      'custom_leave_type_text': _trimOrNull(customLeaveTypeText),
      'start_date': _dateOnly(startDate),
      'end_date': _dateOnly(endDate),
      'working_days_applied': workingDaysApplied,
      'reason': _trimOrNull(reason),
      'location_option': locationOption?.value,
      'location_details': _trimOrNull(locationDetails),
      'sick_leave_nature': sickLeaveNature?.value,
      'sick_illness_details': _trimOrNull(sickIllnessDetails),
      'maternity_delivery_type': maternityDeliveryType?.value,
      'expected_delivery_date': _dateOnly(expectedDeliveryDate),
      'child_delivery_date': _dateOnly(childDeliveryDate),
      'accident_date': _dateOnly(accidentDate),
      'calamity_date': _dateOnly(calamityDate),
      'adoption_parent_role': adoptionParentRole?.value,
      'adoption_placement_date': _dateOnly(adoptionPlacementDate),
      'vawc_support_document_type': vawcSupportDocumentType?.value,
      'vawc_case_details': _trimOrNull(vawcCaseDetails),
      'solo_parent_id_number': _trimOrNull(soloParentIdNumber),
      'solo_parent_id_expiry_date': _dateOnly(soloParentIdExpiryDate),
      'women_illness_details': _trimOrNull(womenIllnessDetails),
      'study_purpose': studyPurpose?.value,
      'study_purpose_details': _trimOrNull(studyPurposeDetails),
      'other_purpose': otherPurpose?.value,
      'other_purpose_details': _trimOrNull(otherPurposeDetails),
      'commutation': commutation.value,
      'attachment_path': attachmentPath,
      'attachment_name': attachmentName,
      'status': status.value,
      'hr_remarks': _trimOrNull(hrRemarks),
      'recommendation_remarks': _trimOrNull(recommendationRemarks),
      'disapproval_reason': _trimOrNull(disapprovalReason),
      'approved_days_with_pay': approvedDaysWithPay,
      'approved_days_without_pay': approvedDaysWithoutPay,
      'approved_other_details': _trimOrNull(approvedOtherDetails),
      'reviewer_id': reviewerId,
      'reviewer_name': _trimOrNull(reviewerName),
      'reviewer_role': _trimOrNull(reviewerRole),
      'reviewer_title': _trimOrNull(reviewerTitle),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'department_head_reviewer_id': departmentHeadReviewerId,
      'department_head_reviewer_name': _trimOrNull(departmentHeadReviewerName),
      'department_head_reviewed_at': departmentHeadReviewedAt
          ?.toIso8601String(),
      'department_head_remarks': _trimOrNull(departmentHeadRemarks),
      'department_head_action': _trimOrNull(departmentHeadAction),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  LeaveRequest copyWith({
    String? id,
    String? userId,
    String? employeeName,
    String? officeDepartment,
    String? positionTitle,
    double? salary,
    DateTime? dateFiled,
    LeaveType? leaveType,
    String? leaveTypeName,
    String? leaveTypeDisplayName,
    String? customLeaveTypeText,
    DateTime? startDate,
    DateTime? endDate,
    double? workingDaysApplied,
    String? reason,
    LeaveLocationOption? locationOption,
    String? locationDetails,
    SickLeaveNature? sickLeaveNature,
    String? sickIllnessDetails,
    MaternityDeliveryType? maternityDeliveryType,
    DateTime? expectedDeliveryDate,
    DateTime? childDeliveryDate,
    DateTime? accidentDate,
    DateTime? calamityDate,
    AdoptionParentRole? adoptionParentRole,
    DateTime? adoptionPlacementDate,
    VawcSupportDocumentType? vawcSupportDocumentType,
    String? vawcCaseDetails,
    String? soloParentIdNumber,
    DateTime? soloParentIdExpiryDate,
    String? womenIllnessDetails,
    StudyLeavePurpose? studyPurpose,
    String? studyPurposeDetails,
    LeaveOtherPurpose? otherPurpose,
    String? otherPurposeDetails,
    LeaveCommutationOption? commutation,
    String? attachmentPath,
    String? attachmentName,
    LeaveRequestStatus? status,
    String? hrRemarks,
    String? recommendationRemarks,
    String? disapprovalReason,
    double? approvedDaysWithPay,
    double? approvedDaysWithoutPay,
    String? approvedOtherDetails,
    String? reviewerId,
    String? reviewerName,
    String? reviewerRole,
    String? reviewerTitle,
    DateTime? reviewedAt,
    String? departmentHeadReviewerId,
    String? departmentHeadReviewerName,
    DateTime? departmentHeadReviewedAt,
    String? departmentHeadRemarks,
    String? departmentHeadAction,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LeaveRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      employeeName: employeeName ?? this.employeeName,
      officeDepartment: officeDepartment ?? this.officeDepartment,
      positionTitle: positionTitle ?? this.positionTitle,
      salary: salary ?? this.salary,
      dateFiled: dateFiled ?? this.dateFiled,
      leaveType: leaveType ?? this.leaveType,
      leaveTypeName: leaveTypeName ?? this.leaveTypeName,
      leaveTypeDisplayName: leaveTypeDisplayName ?? this.leaveTypeDisplayName,
      customLeaveTypeText: customLeaveTypeText ?? this.customLeaveTypeText,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      workingDaysApplied: workingDaysApplied ?? this.workingDaysApplied,
      reason: reason ?? this.reason,
      locationOption: locationOption ?? this.locationOption,
      locationDetails: locationDetails ?? this.locationDetails,
      sickLeaveNature: sickLeaveNature ?? this.sickLeaveNature,
      sickIllnessDetails: sickIllnessDetails ?? this.sickIllnessDetails,
      maternityDeliveryType:
          maternityDeliveryType ?? this.maternityDeliveryType,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      childDeliveryDate: childDeliveryDate ?? this.childDeliveryDate,
      accidentDate: accidentDate ?? this.accidentDate,
      calamityDate: calamityDate ?? this.calamityDate,
      adoptionParentRole: adoptionParentRole ?? this.adoptionParentRole,
      adoptionPlacementDate:
          adoptionPlacementDate ?? this.adoptionPlacementDate,
      vawcSupportDocumentType:
          vawcSupportDocumentType ?? this.vawcSupportDocumentType,
      vawcCaseDetails: vawcCaseDetails ?? this.vawcCaseDetails,
      soloParentIdNumber: soloParentIdNumber ?? this.soloParentIdNumber,
      soloParentIdExpiryDate:
          soloParentIdExpiryDate ?? this.soloParentIdExpiryDate,
      womenIllnessDetails: womenIllnessDetails ?? this.womenIllnessDetails,
      studyPurpose: studyPurpose ?? this.studyPurpose,
      studyPurposeDetails: studyPurposeDetails ?? this.studyPurposeDetails,
      otherPurpose: otherPurpose ?? this.otherPurpose,
      otherPurposeDetails: otherPurposeDetails ?? this.otherPurposeDetails,
      commutation: commutation ?? this.commutation,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      attachmentName: attachmentName ?? this.attachmentName,
      status: status ?? this.status,
      hrRemarks: hrRemarks ?? this.hrRemarks,
      recommendationRemarks:
          recommendationRemarks ?? this.recommendationRemarks,
      disapprovalReason: disapprovalReason ?? this.disapprovalReason,
      approvedDaysWithPay: approvedDaysWithPay ?? this.approvedDaysWithPay,
      approvedDaysWithoutPay:
          approvedDaysWithoutPay ?? this.approvedDaysWithoutPay,
      approvedOtherDetails: approvedOtherDetails ?? this.approvedOtherDetails,
      reviewerId: reviewerId ?? this.reviewerId,
      reviewerName: reviewerName ?? this.reviewerName,
      reviewerRole: reviewerRole ?? this.reviewerRole,
      reviewerTitle: reviewerTitle ?? this.reviewerTitle,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      departmentHeadReviewerId:
          departmentHeadReviewerId ?? this.departmentHeadReviewerId,
      departmentHeadReviewerName:
          departmentHeadReviewerName ?? this.departmentHeadReviewerName,
      departmentHeadReviewedAt:
          departmentHeadReviewedAt ?? this.departmentHeadReviewedAt,
      departmentHeadRemarks:
          departmentHeadRemarks ?? this.departmentHeadRemarks,
      departmentHeadAction: departmentHeadAction ?? this.departmentHeadAction,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  String get effectiveLeaveTypeName {
    final raw = leaveTypeName?.trim();
    return raw == null || raw.isEmpty ? leaveType.value : raw;
  }

  String get leaveTypeLabel {
    final display = leaveTypeDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    if (leaveType == LeaveType.others) {
      final custom = customLeaveTypeText?.trim();
      if (custom != null && custom.isNotEmpty) return custom;
    }
    return leaveType.displayName;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    // Pure YYYY-MM-DD check.
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      try {
        final p = s.split('-').map(int.parse).toList();
        return DateTime(p[0], p[1], p[2]);
      } catch (_) {}
    }
    return DateTime.tryParse(s);
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static String? _dateOnly(DateTime? value) {
    return value?.toIso8601String().split('T').first;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
