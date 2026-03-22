/**
 * Leave type rules based on CSC Application for Leave form instructions.
 * Used for validation in draft/submit/update endpoints.
 *
 * Fields:
 * - employee_can_file: Employee may file this leave type
 * - admin_only: Only admin/HR can create; blocks employee submission
 * - allows_past_dates: Past-date filing allowed
 * - requires_attachment: Supporting document required (TODO: enforce when upload is implemented)
 * - requires_attachment_when_over_days: If days > this, attachment required (e.g. sick leave > 5)
 * - max_days: Maximum working days for this leave type (null = no limit)
 * - special_process_only: Not normal DTR leave; HR/admin process (e.g. monetization, terminal)
 * - special_process_purposes: For "others" type, purposes that are special-process-only
 * - affects_dtr_normally: When approved, marks DTR as on_leave (default true for employee-fileable)
 */

const LEAVE_TYPE_RULES = {
  vacationLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: false,
    requires_attachment: false,
    max_days: null,
    affects_dtr_normally: true,
  },
  mandatoryForcedLeave: {
    employee_can_file: false,
    admin_only: true,
    allows_past_dates: true,
    requires_attachment: false,
    max_days: 5,
    affects_dtr_normally: true,
  },
  sickLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: false,
    requires_attachment_when_over_days: 5,
    max_days: null,
    affects_dtr_normally: true,
  },
  maternityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 105,
    affects_dtr_normally: true,
  },
  paternityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 7,
    affects_dtr_normally: true,
  },
  specialPrivilegeLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: false,
    requires_attachment: false,
    max_days: 3,
    affects_dtr_normally: true,
  },
  soloParentLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 7,
    affects_dtr_normally: true,
  },
  studyLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 180,
    affects_dtr_normally: true,
  },
  tenDayVawcLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 10,
    affects_dtr_normally: true,
  },
  rehabilitationPrivilege: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 180,
    affects_dtr_normally: true,
  },
  specialLeaveBenefitsForWomen: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 60,
    affects_dtr_normally: true,
  },
  specialEmergencyCalamityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 5,
    affects_dtr_normally: true,
    // TODO: If field exists, validate within 30 days from calamity occurrence
  },
  adoptionLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: null,
    affects_dtr_normally: true,
  },
  others: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: null,
    affects_dtr_normally: true,
    // Monetization and Terminal Leave are special HR processes, not normal employee filing
    special_process_purposes: ['monetizationOfLeaveCredits', 'terminalLeave'],
  },
};

/** Purposes under "others" that block employee filing (HR/admin process only). */
const SPECIAL_PROCESS_PURPOSES = ['monetizationOfLeaveCredits', 'terminalLeave'];

function getRule(leaveTypeName) {
  const name = (leaveTypeName || '').toString().trim();
  return LEAVE_TYPE_RULES[name] || null;
}

/**
 * Validate leave request for employee filing (draft/submit/put).
 * @param {object} opts
 * @param {string} opts.leaveType - leave type name (e.g. vacationLeave)
 * @param {string} opts.otherPurpose - for "others" type, the other_purpose value
 * @param {string} opts.startDateStr - YYYY-MM-DD
 * @param {string} opts.endDateStr - YYYY-MM-DD
 * @param {number} opts.numberOfDays - computed working days
 * @param {boolean} opts.hasAttachment - whether attachment was provided (TODO: when implemented)
 * @returns {{ valid: boolean, error?: string }}
 */
function validateEmployeeLeaveRequest(opts) {
  const { leaveType, otherPurpose, startDateStr, endDateStr, numberOfDays, hasAttachment = false } = opts;
  const rule = getRule(leaveType);

  if (!rule) {
    return { valid: true }; // unknown type, skip rule-based validation
  }

  // Admin-only: employee cannot file
  if (rule.admin_only) {
    return { valid: false, error: 'This leave type cannot be filed by employees. It is admin-assigned only.' };
  }

  // Special process: monetization/terminal under "others"
  if (leaveType === 'others' && otherPurpose) {
    const purpose = String(otherPurpose).trim();
    if (SPECIAL_PROCESS_PURPOSES.some((p) => purpose.toLowerCase().includes(p.toLowerCase().replace(/_/g, '')))) {
      return {
        valid: false,
        error: 'Monetization of Leave Credits and Terminal Leave are HR/admin processes. Please contact HR.',
      };
    }
  }

  if (rule.employee_can_file === false) {
    return { valid: false, error: 'This leave type is not available for employee filing.' };
  }

  // Past-date check
  if (rule.allows_past_dates === false && startDateStr) {
    const today = new Date().toISOString().slice(0, 10);
    if (startDateStr < today) {
      return {
        valid: false,
        error: 'Past-date filing is not allowed for this leave type. Please file in advance.',
      };
    }
  }

  // Max days check
  if (rule.max_days != null && Number.isFinite(rule.max_days) && numberOfDays != null) {
    const days = parseFloat(numberOfDays);
    if (!Number.isNaN(days) && days > rule.max_days) {
      return {
        valid: false,
        error: `This leave type allows a maximum of ${rule.max_days} working days. Requested: ${days.toFixed(1)}.`,
      };
    }
  }

  // TODO: When attachment upload is implemented, enforce:
  // - rule.requires_attachment -> block if !hasAttachment
  // - rule.requires_attachment_when_over_days (sick leave > 5 days) -> block if days > threshold && !hasAttachment
  // For now we do not block; UI shows a note for attachment-required types.

  return { valid: true };
}

/**
 * Check if leave type is employee-fileable (for UI filtering).
 */
function isEmployeeFileable(leaveTypeName, otherPurpose) {
  const rule = getRule(leaveTypeName);
  if (!rule) return true;
  if (rule.admin_only || rule.employee_can_file === false) return false;
  if (leaveTypeName === 'others' && otherPurpose) {
    const p = String(otherPurpose).trim().toLowerCase();
    if (SPECIAL_PROCESS_PURPOSES.some((sp) => p.includes(sp.toLowerCase().replace(/_/g, '')))) {
      return false;
    }
  }
  return true;
}

module.exports = {
  LEAVE_TYPE_RULES,
  getRule,
  validateEmployeeLeaveRequest,
  isEmployeeFileable,
};
