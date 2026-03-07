/// Main leave categories based on the CSC Application for Leave form.
enum LeaveType {
  vacationLeave,
  mandatoryForcedLeave,
  sickLeave,
  maternityLeave,
  paternityLeave,
  specialPrivilegeLeave,
  soloParentLeave,
  studyLeave,
  tenDayVawcLeave,
  rehabilitationPrivilege,
  specialLeaveBenefitsForWomen,
  specialEmergencyCalamityLeave,
  adoptionLeave,
  others,
}

extension LeaveTypeExtension on LeaveType {
  String get value => name;

  String get displayName => switch (this) {
        LeaveType.vacationLeave => 'Vacation Leave',
        LeaveType.mandatoryForcedLeave => 'Mandatory/Forced Leave',
        LeaveType.sickLeave => 'Sick Leave',
        LeaveType.maternityLeave => 'Maternity Leave',
        LeaveType.paternityLeave => 'Paternity Leave',
        LeaveType.specialPrivilegeLeave => 'Special Privilege Leave',
        LeaveType.soloParentLeave => 'Solo Parent Leave',
        LeaveType.studyLeave => 'Study Leave',
        LeaveType.tenDayVawcLeave => '10-Day VAWC Leave',
        LeaveType.rehabilitationPrivilege => 'Rehabilitation Privilege',
        LeaveType.specialLeaveBenefitsForWomen =>
          'Special Leave Benefits for Women',
        LeaveType.specialEmergencyCalamityLeave =>
          'Special Emergency (Calamity) Leave',
        LeaveType.adoptionLeave => 'Adoption Leave',
        LeaveType.others => 'Others',
      };

  /// Some leave types usually need a supporting document.
  bool get requiresAttachment => switch (this) {
        LeaveType.sickLeave => true,
        LeaveType.maternityLeave => true,
        LeaveType.paternityLeave => true,
        LeaveType.soloParentLeave => true,
        LeaveType.studyLeave => true,
        LeaveType.tenDayVawcLeave => true,
        LeaveType.rehabilitationPrivilege => true,
        LeaveType.specialLeaveBenefitsForWomen => true,
        LeaveType.specialEmergencyCalamityLeave => true,
        LeaveType.adoptionLeave => true,
        LeaveType.others => true,
        LeaveType.vacationLeave => false,
        LeaveType.mandatoryForcedLeave => false,
        LeaveType.specialPrivilegeLeave => false,
      };

  bool get requiresCustomDescription => this == LeaveType.others;
}

LeaveType leaveTypeFromString(String? s) {
  if (s == null || s.isEmpty) return LeaveType.vacationLeave;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in LeaveType.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '').replaceAll(
      '/',
      '',
    );
    if (enumName == normalized || label == normalized) return e;
  }
  return LeaveType.vacationLeave;
}

/// Detail options in the official form for vacation/special privilege leave.
enum LeaveLocationOption {
  withinPhilippines,
  abroad,
}

extension LeaveLocationOptionExtension on LeaveLocationOption {
  String get value => name;

  String get displayName => switch (this) {
        LeaveLocationOption.withinPhilippines => 'Within the Philippines',
        LeaveLocationOption.abroad => 'Abroad',
      };
}

LeaveLocationOption? leaveLocationOptionFromString(String? s) {
  if (s == null || s.isEmpty) return null;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in LeaveLocationOption.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '');
    if (enumName == normalized || label == normalized) return e;
  }
  return null;
}

/// Detail options in the official form for sick leave.
enum SickLeaveNature {
  inHospital,
  outPatient,
}

extension SickLeaveNatureExtension on SickLeaveNature {
  String get value => name;

  String get displayName => switch (this) {
        SickLeaveNature.inHospital => 'In Hospital',
        SickLeaveNature.outPatient => 'Out Patient',
      };
}

SickLeaveNature? sickLeaveNatureFromString(String? s) {
  if (s == null || s.isEmpty) return null;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in SickLeaveNature.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '');
    if (enumName == normalized || label == normalized) return e;
  }
  return null;
}

/// Detail options in the official form for study leave.
enum StudyLeavePurpose {
  completionOfMastersDegree,
  barBoardExaminationReview,
  otherPurpose,
}

extension StudyLeavePurposeExtension on StudyLeavePurpose {
  String get value => name;

  String get displayName => switch (this) {
        StudyLeavePurpose.completionOfMastersDegree =>
          "Completion of Master's Degree",
        StudyLeavePurpose.barBoardExaminationReview =>
          'BAR/Board Examination Review',
        StudyLeavePurpose.otherPurpose => 'Other purpose',
      };
}

StudyLeavePurpose? studyLeavePurposeFromString(String? s) {
  if (s == null || s.isEmpty) return null;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in StudyLeavePurpose.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('/', '')
        .replaceAll("'", '');
    if (enumName == normalized || label == normalized) return e;
  }
  return null;
}

/// "Other purpose" options shown in the official form.
enum LeaveOtherPurpose {
  monetizationOfLeaveCredits,
  terminalLeave,
}

extension LeaveOtherPurposeExtension on LeaveOtherPurpose {
  String get value => name;

  String get displayName => switch (this) {
        LeaveOtherPurpose.monetizationOfLeaveCredits =>
          'Monetization of Leave Credits',
        LeaveOtherPurpose.terminalLeave => 'Terminal Leave',
      };
}

LeaveOtherPurpose? leaveOtherPurposeFromString(String? s) {
  if (s == null || s.isEmpty) return null;
  final normalized = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  for (final e in LeaveOtherPurpose.values) {
    final enumName = e.name.toLowerCase().replaceAll('_', '');
    final label = e.displayName.toLowerCase().replaceAll(' ', '');
    if (enumName == normalized || label == normalized) return e;
  }
  return null;
}
