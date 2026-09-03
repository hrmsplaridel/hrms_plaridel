abstract final class LeaveEntitlementBasis {
  static const accrual = 'accrual';
  static const annual = 'annual';
  static const perEvent = 'per_event';
  static const perRequest = 'per_request';
  static const compliance = 'compliance';

  static const values = {accrual, annual, perEvent, perRequest, compliance};

  static String forLeaveType(String leaveTypeName) {
    return switch (leaveTypeName.trim()) {
      'vacationLeave' || 'sickLeave' => accrual,
      'specialPrivilegeLeave' ||
      'soloParentLeave' ||
      'tenDayVawcLeave' => annual,
      'mandatoryForcedLeave' => compliance,
      'maternityLeave' ||
      'paternityLeave' ||
      'rehabilitationPrivilege' ||
      'specialLeaveBenefitsForWomen' ||
      'specialEmergencyCalamityLeave' ||
      'adoptionLeave' => perEvent,
      _ => perRequest,
    };
  }

  static String normalize(String? value, String leaveTypeName) {
    final normalized = (value ?? '').trim().toLowerCase();
    return values.contains(normalized)
        ? normalized
        : forLeaveType(leaveTypeName);
  }

  static String label(String value) {
    return switch (value) {
      accrual => 'Accrued credit balance',
      annual => 'Annual entitlement',
      perEvent => 'Per qualifying event',
      compliance => 'Compliance requirement',
      _ => 'Per request',
    };
  }
}
