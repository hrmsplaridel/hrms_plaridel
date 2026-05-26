/**
 * Leave type rules based on CSC Application for Leave form instructions.
 * Used for validation in draft/submit/update endpoints.
 *
 * Fields:
 * - employee_can_file: Employee may file this leave type
 * - admin_only: Only admin/HR can create; blocks employee submission
 * - allows_past_dates: Past-date filing allowed
 * - requires_attachment: Supporting document required (TODO: enforce when upload is implemented)
 * - requires_attachment_when_over_days: Sick leave only — medical certificate required if working days >= this value (default 5)
 * - max_days: Maximum working days for this leave type (null = no limit)
 * - minimum_advance_days: Minimum calendar days before start date for employee filing (null = no limit)
 * - special_process_only: Not normal DTR leave; HR/admin process (e.g. monetization, terminal)
 * - special_process_purposes: For "others" type, purposes that are special-process-only
 * - affects_dtr_normally: When approved, marks DTR as on_leave (default true for employee-fileable)
 * - sex_eligibility: any | female | male
 */

const LEAVE_TYPE_RULES = {
  vacationLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: false,
    requires_attachment: false,
    max_days: null,
    minimum_advance_days: 5,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  mandatoryForcedLeave: {
    employee_can_file: false,
    admin_only: true,
    allows_past_dates: true,
    requires_attachment: false,
    max_days: 5,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  sickLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: false,
    requires_attachment_when_over_days: 5,
    max_days: null,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  maternityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 105,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'female',
  },
  paternityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 7,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'male',
  },
  specialPrivilegeLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: false,
    requires_attachment: false,
    max_days: 3,
    minimum_advance_days: 7,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  soloParentLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 7,
    minimum_advance_days: 5,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  studyLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 180,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  tenDayVawcLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 10,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'female',
  },
  rehabilitationPrivilege: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 180,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  specialLeaveBenefitsForWomen: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 60,
    minimum_advance_days: 5,
    affects_dtr_normally: true,
    sex_eligibility: 'female',
  },
  specialEmergencyCalamityLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: 5,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
    // TODO: If field exists, validate within 30 days from calamity occurrence
  },
  adoptionLeave: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: null,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
  },
  others: {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    max_days: null,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: 'any',
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

function todayIsoDateInTimeZone(timeZone = 'Asia/Manila') {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const get = (type) => parts.find((part) => part.type === type)?.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function isoDateToUtcDayMs(value) {
  const text = (value || '').toString().slice(0, 10);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return null;
  }
  return Date.UTC(year, month - 1, day);
}

function calendarDayDifference(startDateStr, baseDateStr = todayIsoDateInTimeZone()) {
  const startMs = isoDateToUtcDayMs(startDateStr);
  const baseMs = isoDateToUtcDayMs(baseDateStr);
  if (startMs == null || baseMs == null) return null;
  return Math.round((startMs - baseMs) / (24 * 60 * 60 * 1000));
}

function normalizeMaternityDeliveryType(value) {
  const normalized = (value || '')
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[\s_\-/()]/g, '');
  if (!normalized) return null;
  if (
    normalized === 'cs' ||
    normalized === 'csection' ||
    normalized === 'cesarean' ||
    normalized === 'cesareansection' ||
    normalized === 'caesarean' ||
    normalized === 'caesareansection'
  ) {
    return 'caesareanSection';
  }
  if (
    normalized === 'normal' ||
    normalized === 'nsc' ||
    normalized === 'noncs' ||
    normalized === 'notcs' ||
    normalized === 'normaldelivery'
  ) {
    return 'normalDelivery';
  }
  return null;
}

function maternityMaxDaysForDeliveryType(value) {
  return normalizeMaternityDeliveryType(value) === 'caesareanSection' ? 115 : 105;
}

function effectiveMaxDaysForRule({ rule, leaveType, maternityDeliveryType }) {
  if (leaveType === 'maternityLeave') {
    return maternityMaxDaysForDeliveryType(maternityDeliveryType);
  }
  const maxDays = rule?.max_days;
  if (maxDays == null || maxDays === '') return null;
  const parsed = parseFloat(maxDays);
  return Number.isFinite(parsed) ? parsed : null;
}

function minimumAdvanceDaysFilingError({ rule, leaveType, leaveTypeLabel, startDateStr }) {
  const raw = rule?.minimum_advance_days ?? rule?.minimumAdvanceDays;
  if (raw == null || raw === '') return null;
  const minimumDays = parseInt(raw, 10);
  if (!Number.isFinite(minimumDays) || minimumDays <= 0 || !startDateStr) return null;
  const diff = calendarDayDifference(startDateStr);
  if (diff == null || diff >= minimumDays) return null;
  const label = (leaveTypeLabel || rule?.display_name || leaveType || 'This leave type')
    .toString()
    .trim();
  const unit = minimumDays === 1 ? 'day' : 'days';
  return `${label} must be filed at least ${minimumDays} ${unit} before the intended leave date.`;
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
  const {
    leaveType,
    otherPurpose,
    startDateStr,
    endDateStr,
    numberOfDays,
    hasAttachment = false,
    maternityDeliveryType,
  } = opts;
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
    const today = todayIsoDateInTimeZone();
    if (startDateStr < today) {
      return {
        valid: false,
        error: 'Past-date filing is not allowed for this leave type. Please file in advance.',
      };
    }
  }

  const advanceError = minimumAdvanceDaysFilingError({
    rule,
    leaveType,
    startDateStr,
  });
  if (advanceError) {
    return { valid: false, error: advanceError };
  }

  // Max days check
  const maxDays = effectiveMaxDaysForRule({
    rule,
    leaveType,
    maternityDeliveryType,
  });
  if (maxDays != null && numberOfDays != null) {
    const days = parseFloat(numberOfDays);
    if (!Number.isNaN(days) && days > maxDays) {
      return {
        valid: false,
        error: `This leave type allows a maximum of ${maxDays} working days. Requested: ${days.toFixed(1)}.`,
      };
    }
  }

  return { valid: true };
}

/**
 * True if submission should be rejected because a required attachment is missing.
 * @param {object|null} rule - from getRule()
 * @param {string} leaveType
 * @param {number} days - working days requested
 * @param {boolean} hasAttachment
 */
function mustBlockMissingAttachment(rule, leaveType, days, hasAttachment) {
  if (hasAttachment) return false;
  if (!rule) return false;
  const d = parseFloat(days);
  if (leaveType === 'sickLeave') {
    const threshold = rule.requires_attachment_when_over_days ?? 5;
    if (Number.isNaN(d)) return false;
    return d >= threshold;
  }
  return !!rule.requires_attachment;
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
  SPECIAL_PROCESS_PURPOSES,
  getRule,
  validateEmployeeLeaveRequest,
  minimumAdvanceDaysFilingError,
  normalizeMaternityDeliveryType,
  maternityMaxDaysForDeliveryType,
  effectiveMaxDaysForRule,
  isEmployeeFileable,
  mustBlockMissingAttachment,
};
