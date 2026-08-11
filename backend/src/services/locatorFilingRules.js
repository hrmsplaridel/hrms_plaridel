const DEFAULT_LOCATOR_WORKING_DAYS = [1, 2, 3, 4, 5];
const LOCATOR_WEEKDAY_NAMES = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const LOCATOR_REQUIRED_FIELDS = Object.freeze([
  'slip date',
  'locator type',
  'office/destination',
  'reason',
  'at least one AM/PM IN/OUT marker',
]);

function parseLocatorDateOnly(value) {
  const raw = (value || '').toString().trim();
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  const utcDay = parsed.getUTCDay();
  return {
    dateStr: raw,
    isoWeekday: utcDay === 0 ? 7 : utcDay,
  };
}

function normalizeLocatorWorkingDays(value) {
  if (!Array.isArray(value)) return DEFAULT_LOCATOR_WORKING_DAYS;
  const days = value
    .map((day) => Number(day))
    .filter((day) => Number.isInteger(day) && day >= 1 && day <= 7);
  const unique = [...new Set(days)].sort((a, b) => a - b);
  return unique.length > 0 ? unique : DEFAULT_LOCATOR_WORKING_DAYS;
}

function evaluateLocatorWorkingDay({ dateInfo, assignment }) {
  if (!dateInfo) return { ok: false, error: 'Invalid slip_date' };
  if (!assignment || !assignment.shift_id || !assignment.shift_name) {
    return {
      ok: false,
      error:
        'You cannot file a locator request for this date because you have no shift assignment effective on this date.',
    };
  }

  const workingDays = normalizeLocatorWorkingDays(assignment.working_days);
  if (!workingDays.includes(dateInfo.isoWeekday)) {
    const weekdayName =
      LOCATOR_WEEKDAY_NAMES[dateInfo.isoWeekday - 1] || 'that day';
    return {
      ok: false,
      error:
        `You cannot file a locator request for ${weekdayName} because it is ` +
        'not included in your assigned shift working days.',
    };
  }
  return { ok: true };
}

async function validateLocatorWorkingDayForEmployee(
  client,
  employeeId,
  dateInfo
) {
  if (!dateInfo) return { ok: false, error: 'Invalid slip_date' };
  const result = await client.query(
    `SELECT a.id,
            a.shift_id,
            s.name AS shift_name,
            s.working_days
     FROM assignments a
     LEFT JOIN shifts s ON s.id = a.shift_id
     WHERE a.employee_id = $1::uuid
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
     LIMIT 1`,
    [employeeId, dateInfo.dateStr]
  );
  return evaluateLocatorWorkingDay({
    dateInfo,
    assignment: result.rows[0],
  });
}

function validateLocatorRequiredFields({
  slipDate,
  requestType,
  office,
  reason,
  slots = {},
}) {
  if (!(slipDate || '').toString().trim()) {
    return { valid: false, error: 'slip_date is required' };
  }
  if (!parseLocatorDateOnly(slipDate)) {
    return { valid: false, error: 'Invalid slip_date' };
  }
  if (!(requestType || '').toString().trim()) {
    return { valid: false, error: 'Invalid request_type' };
  }
  if (!(office || '').toString().trim()) {
    return { valid: false, error: 'office is required' };
  }
  if (!(reason || '').toString().trim()) {
    return { valid: false, error: 'reason is required' };
  }
  if (![slots.amIn, slots.amOut, slots.pmIn, slots.pmOut].some(Boolean)) {
    return {
      valid: false,
      error: 'At least one AM/PM IN/OUT marker is required',
    };
  }
  return { valid: true };
}

function locatorAttachmentRequiredError(locatorType, hasAttachment) {
  if (locatorType?.requires_attachment === true && !hasAttachment) {
    return 'Attachment is required for this locator type.';
  }
  return null;
}

function canModifyLocatorAttachment(status) {
  return status === 'returned_for_correction';
}

function validateLocatorAttachmentForReview({
  locatorType,
  attachmentPath,
  attachmentFileExists,
}) {
  if (locatorType?.requires_attachment !== true) return null;
  if (!(attachmentPath || '').toString().trim()) {
    return 'This locator type requires an attachment. Return the request to the employee for correction.';
  }
  if (attachmentFileExists !== true) {
    return 'The required attachment file is missing. Return the request to the employee for correction.';
  }
  return null;
}

module.exports = {
  canModifyLocatorAttachment,
  DEFAULT_LOCATOR_WORKING_DAYS,
  LOCATOR_REQUIRED_FIELDS,
  evaluateLocatorWorkingDay,
  validateLocatorWorkingDayForEmployee,
  locatorAttachmentRequiredError,
  normalizeLocatorWorkingDays,
  parseLocatorDateOnly,
  validateLocatorAttachmentForReview,
  validateLocatorRequiredFields,
};
