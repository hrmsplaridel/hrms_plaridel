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

const MATERNITY_MINIMUM_NOTICE_DAYS = 30;

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

function calendarDaySpan(fromDateStr, toDateStr) {
  return calendarDayDifference(toDateStr, fromDateStr);
}

function normalizeIsoDateString(value) {
  const text = (value || '').toString().trim().slice(0, 10);
  return isoDateToUtcDayMs(text) == null ? null : text;
}

function readDetailValue(details, keys) {
  if (!details || typeof details !== 'object') return null;
  for (const key of keys) {
    const value = details[key];
    if (value != null && `${value}`.trim() !== '') return `${value}`.trim();
  }
  return null;
}

function normalizeSickLeaveNature(value) {
  const normalized = (value || '')
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[\s_\-/()]/g, '');
  if (normalized === 'inhospital' || normalized === 'hospital') {
    return 'inHospital';
  }
  if (normalized === 'outpatient' || normalized === 'outpatientcare') {
    return 'outPatient';
  }
  return null;
}

function normalizeLeaveLocationOption(value) {
  const normalized = (value || '')
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[\s_\-/()]/g, '');
  if (
    normalized === 'withinphilippines' ||
    normalized === 'philippines' ||
    normalized === 'local'
  ) {
    return 'withinPhilippines';
  }
  if (normalized === 'abroad' || normalized === 'foreign' || normalized === 'outsidephilippines') {
    return 'abroad';
  }
  return null;
}

function requiredLeaveDetailsFilingError({ leaveType, leaveTypeLabel, details = {} }) {
  const label = (leaveTypeLabel || leaveType || 'This leave type').toString().trim();

  if (leaveType === 'sickLeave') {
    const nature = normalizeSickLeaveNature(
      readDetailValue(details, ['sick_leave_nature', 'sickLeaveNature'])
    );
    if (!nature) {
      return `${label} requires the sick leave nature (In Hospital or Out Patient).`;
    }
    const illnessDetails = readDetailValue(details, [
      'sick_illness_details',
      'sickIllnessDetails',
      'illness_details',
      'illnessDetails',
    ]);
    if (!illnessDetails) {
      return `${label} requires illness details.`;
    }
  }

  if (leaveType === 'vacationLeave' || leaveType === 'specialPrivilegeLeave') {
    const location = normalizeLeaveLocationOption(
      readDetailValue(details, ['location_option', 'locationOption'])
    );
    if (!location) {
      return `${label} requires a location option (Within the Philippines or Abroad).`;
    }
    const locationDetails = readDetailValue(details, [
      'location_details',
      'locationDetails',
    ]);
    if (!locationDetails) {
      return `${label} requires location details.`;
    }
  }

  return null;
}

function leaveEventDateFilingError({
  leaveType,
  leaveTypeLabel,
  startDateStr,
  endDateStr,
  eventDates = {},
}) {
  const label = (leaveTypeLabel || leaveType || 'This leave type').toString().trim();
  const start = normalizeIsoDateString(startDateStr);
  const end = normalizeIsoDateString(endDateStr || startDateStr);
  if (!start || !end) return null;

  if (leaveType === 'maternityLeave') {
    const expected = normalizeIsoDateString(eventDates.expectedDeliveryDate);
    if (!expected) {
      return `${label} requires the expected delivery date.`;
    }
    const noticeDays = calendarDayDifference(expected);
    if (noticeDays != null && noticeDays < MATERNITY_MINIMUM_NOTICE_DAYS) {
      return `${label} must be filed at least ${MATERNITY_MINIMUM_NOTICE_DAYS} days before the expected delivery date.`;
    }
    return null;
  }

  if (leaveType === 'paternityLeave') {
    const delivery = normalizeIsoDateString(eventDates.childDeliveryDate);
    if (!delivery) {
      return `${label} requires the child delivery or miscarriage date.`;
    }
    const startDiff = calendarDaySpan(delivery, start);
    const endDiff = calendarDaySpan(delivery, end);
    if (startDiff == null || endDiff == null) return 'Invalid child delivery date.';
    if (startDiff < 0) {
      return `${label} cannot start before the child delivery date.`;
    }
    if (endDiff > 60) {
      return `${label} must be availed within 60 days from delivery.`;
    }
    return null;
  }

  if (leaveType === 'rehabilitationPrivilege') {
    const accident = normalizeIsoDateString(eventDates.accidentDate);
    if (!accident) return `${label} requires the accident date.`;
    const filingDiff = calendarDaySpan(accident, todayIsoDateInTimeZone());
    if (filingDiff == null) return 'Invalid accident date.';
    if (filingDiff < 0) return 'Accident date cannot be in the future.';
    if (filingDiff > 7) {
      return `${label} must be filed within 1 week from the accident. Contact HR if a longer period is warranted.`;
    }
    return null;
  }

  if (leaveType === 'specialEmergencyCalamityLeave') {
    const calamity = normalizeIsoDateString(eventDates.calamityDate);
    if (!calamity) {
      return `${label} requires the calamity/disaster occurrence date.`;
    }
    const startDiff = calendarDaySpan(calamity, start);
    const endDiff = calendarDaySpan(calamity, end);
    if (startDiff == null || endDiff == null) {
      return 'Invalid calamity/disaster occurrence date.';
    }
    if (startDiff < 0) {
      return `${label} cannot start before the calamity date.`;
    }
    if (endDiff > 30) {
      return `${label} must be used within 30 days from the calamity occurrence.`;
    }
    return null;
  }

  return null;
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
    eventDates,
    details,
    enforceRequiredDetails = true,
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

  if (enforceRequiredDetails) {
    const requiredDetailsError = requiredLeaveDetailsFilingError({
      leaveType,
      leaveTypeLabel: rule.display_name,
      details,
    });
    if (requiredDetailsError) {
      return { valid: false, error: requiredDetailsError };
    }
  }

  const eventDateError = leaveEventDateFilingError({
    leaveType,
    leaveTypeLabel: rule.display_name,
    startDateStr,
    endDateStr,
    eventDates,
  });
  if (eventDateError) {
    return { valid: false, error: eventDateError };
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
  leaveEventDateFilingError,
  normalizeMaternityDeliveryType,
  maternityMaxDaysForDeliveryType,
  effectiveMaxDaysForRule,
  requiredLeaveDetailsFilingError,
  isEmployeeFileable,
  mustBlockMissingAttachment,
};
