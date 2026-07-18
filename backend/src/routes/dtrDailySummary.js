const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin, requireAdminOrSupervisor } = require('../middleware/rbac');
const {
  expandNonRecurringToWindow,
  expandRecurringToWindow,
  dateInRecurringRange,
} = require('../services/holidayRangeUtils');
const { broadcastBiometricUpdate } = require('../websockets/biometricStream');
const {
  ensureShiftPunchModeColumn,
  getShiftType: resolveShiftType,
  getExpectedWorkMinutes: resolveExpectedWorkMinutes,
  getExpectedLogsForDay: resolveExpectedLogsForDay,
  computeTotalHoursFromRecord,
} = require('../services/shiftAttendance');

const router = express.Router();
const protect = [authMiddleware];
function normalizeLocatorRequestType(value) {
  const type = (value || 'locator').toString().trim().toLowerCase();
  return /^[a-z0-9_][a-z0-9_-]{1,63}$/.test(type) ? type : 'locator';
}

function isTruthyQueryFlag(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value || '').trim().toLowerCase());
}

function locatorRequestTypeLabel(value) {
  switch (normalizeLocatorRequestType(value)) {
    case 'pass_slip':
      return 'Pass Slip';
    case 'work_from_home':
      return 'WFH';
    case 'locator':
      return 'Locator Slip';
    default:
      return normalizeLocatorRequestType(value)
        .split(/[_-]+/)
        .filter(Boolean)
        .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
        .join(' ') || 'Locator Slip';
  }
}

function locatorAttendanceRemark(locator) {
  if (normalizeLocatorRequestType(locator?.request_type) === 'work_from_home') {
    return 'WFH';
  }
  const segText =
    locator?.segments && locator.segments.length > 0
      ? ` (${locator.segments.join(', ')})`
      : '';
  return `${locatorRequestTypeLabel(locator?.request_type)}${segText}`;
}

/** Parse time value to minutes from midnight. Returns null if invalid. */
function timeToMinutes(timeStr) {
  if (!timeStr) return null;
  if (timeStr instanceof Date) {
    const h = timeStr.getHours();
    const m = timeStr.getMinutes();
    if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
    return Math.min(24 * 60 - 1, Math.max(0, h * 60 + m));
  }
  const s = String(timeStr).trim();
  // Accept "HH:MM", "HH:MM:SS", "HH:MM:SS.ssssss"
  const m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/);
  if (!m) return null;
  const h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  if (!Number.isFinite(h) || !Number.isFinite(min)) return null;
  return Math.min(24 * 60 - 1, Math.max(0, h * 60 + min));
}

/** Format minutes from midnight as "HH:MM". */
function minutesToTimeStr(mins) {
  const h = Math.floor(mins / 60) % 24;
  const m = mins % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** Noon in minutes from midnight. */
const NOON_MINUTES = 12 * 60;

/** Default timezone for interpreting shift rules vs log timestamps. */
const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

/**
 * Returns today's date string (YYYY-MM-DD) in HRMS_TIMEZONE, not UTC.
 * Prevents off-by-one issues when the server runs in UTC but the business
 * timezone is e.g. Asia/Manila (+08:00).
 */
function todayInHrmsTimezone() {
  const now = new Date();
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: HRMS_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const y = parts.find((p) => p.type === 'year')?.value ?? '';
  const m = parts.find((p) => p.type === 'month')?.value ?? '';
  const d = parts.find((p) => p.type === 'day')?.value ?? '';
  return `${y}-${m}-${d}`;
}

/**
 * Returns current minutes-from-midnight (0-1439) in HRMS_TIMEZONE.
 * Uses the same Intl machinery as minutesFromMidnightInTimeZone() so
 * the result is consistent with shift boundary comparisons throughout.
 */
function nowMinutesInHrmsTimezone() {
  return minutesFromMidnightInTimeZone(new Date(), HRMS_TIMEZONE) ?? 0;
}

const ATTENDANCE_POLICY_CACHE_TTL_MS = 60 * 1000;
let _cachedAttendancePolicy = null;
let _cachedAttendancePolicyAt = 0;
const _policyByEmployeeDateCache = new Map();

function _normalizePolicy(row) {
  return {
    id: row?.id || null,
    workHoursPerDay: row?.work_hours_per_day != null ? parseFloat(row.work_hours_per_day) : 8,
    deductLate: row?.deduct_late ?? true,
    maxLateMinutesPerMonth:
      row?.max_late_minutes_per_month != null ? parseInt(row.max_late_minutes_per_month, 10) : null,
    convertLateToEquivalentDay: row?.convert_late_to_equivalent_day ?? false,
    deductUndertime: row?.deduct_undertime ?? true,
    convertUndertimeToEquivalentDay: row?.convert_undertime_to_equivalent_day ?? false,
    absentEqualsFullDayDeduction: row?.absent_equals_full_day_deduction ?? true,
    combineLateAndUndertime: row?.combine_late_and_undertime ?? false,
    deductionMultiplier: row?.deduction_multiplier != null ? parseFloat(row.deduction_multiplier) : 1,
  };
}

async function getActiveDefaultAttendancePolicy() {
  const now = Date.now();
  if (_cachedAttendancePolicy && now - _cachedAttendancePolicyAt < ATTENDANCE_POLICY_CACHE_TTL_MS) {
    return _cachedAttendancePolicy;
  }
  const result = await pool.query(
    `SELECT id, work_hours_per_day, deduct_late, max_late_minutes_per_month,
            convert_late_to_equivalent_day, deduct_undertime, convert_undertime_to_equivalent_day,
            absent_equals_full_day_deduction, combine_late_and_undertime, deduction_multiplier
     FROM attendance_policies
     WHERE (is_active IS NULL OR is_active = true)
     ORDER BY is_default DESC, updated_at DESC, created_at DESC
     LIMIT 1`
  );
  _cachedAttendancePolicy = _normalizePolicy(result.rows[0]);
  _cachedAttendancePolicyAt = now;
  return _cachedAttendancePolicy;
}

async function getAttendancePolicyForEmployeeDate(employeeId, dateStr) {
  if (!employeeId || !dateStr) return getActiveDefaultAttendancePolicy();
  const cacheKey = `${employeeId}|${dateStr}`;
  const now = Date.now();
  const cached = _policyByEmployeeDateCache.get(cacheKey);
  if (cached && now - cached.at < ATTENDANCE_POLICY_CACHE_TTL_MS) return cached.value;

  const result = await pool.query(
    `WITH eff AS (
       SELECT a.department_id, a.shift_id
       FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND (a.is_active IS NULL OR a.is_active = true)
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     )
     SELECT p.id, p.work_hours_per_day, p.deduct_late, p.max_late_minutes_per_month,
            p.convert_late_to_equivalent_day, p.deduct_undertime, p.convert_undertime_to_equivalent_day,
            p.absent_equals_full_day_deduction, p.combine_late_and_undertime, p.deduction_multiplier
     FROM policy_assignments pa
     JOIN attendance_policies p ON p.id = pa.attendance_policy_id
     LEFT JOIN eff e ON true
     WHERE (pa.is_active IS NULL OR pa.is_active = true)
       AND (p.is_active IS NULL OR p.is_active = true)
       AND pa.effective_from <= $2::date
       AND (pa.effective_to IS NULL OR pa.effective_to >= $2::date)
       AND (
         pa.employee_id = $1::uuid
         OR (pa.department_id IS NOT NULL AND pa.department_id = e.department_id)
         OR (pa.shift_id IS NOT NULL AND pa.shift_id = e.shift_id)
       )
     ORDER BY CASE
                WHEN pa.employee_id = $1::uuid THEN 1
                WHEN pa.department_id IS NOT NULL AND pa.department_id = e.department_id THEN 2
                WHEN pa.shift_id IS NOT NULL AND pa.shift_id = e.shift_id THEN 3
                ELSE 4
              END,
              pa.effective_from DESC,
              pa.created_at DESC
     LIMIT 1`,
    [employeeId, dateStr]
  );
  const resolved = result.rows[0] ? _normalizePolicy(result.rows[0]) : await getActiveDefaultAttendancePolicy();
  _policyByEmployeeDateCache.set(cacheKey, { at: now, value: resolved });
  return resolved;
}

function applyPolicyConversion(minutes, convertToEquivalentDay, workHoursPerDay, multiplier) {
  if (!Number.isFinite(minutes) || minutes <= 0) return 0;
  const mult = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  if (!convertToEquivalentDay) return Math.round(minutes * mult);
  const workMinutes = Math.max(1, Math.round((Number.isFinite(workHoursPerDay) ? workHoursPerDay : 8) * 60));
  const dayValue = minutes / workMinutes;
  return Math.round(dayValue * mult * workMinutes);
}

async function applyAttendancePolicyPenalties(employeeId, dateStr, rawLateMinutes, rawUndertimeMinutes) {
  const policy = await getAttendancePolicyForEmployeeDate(employeeId, dateStr);
  let late = policy.deductLate ? Math.max(0, rawLateMinutes || 0) : 0;
  let under = policy.deductUndertime ? Math.max(0, rawUndertimeMinutes || 0) : 0;

  if (policy.maxLateMinutesPerMonth != null && policy.maxLateMinutesPerMonth >= 0 && late > 0) {
    const used = await pool.query(
      `SELECT COALESCE(SUM(late_minutes), 0) AS total
       FROM dtr_daily_summary
       WHERE employee_id = $1::uuid
         AND date_trunc('month', attendance_date) = date_trunc('month', $2::date)
         AND attendance_date < $2::date`,
      [employeeId, dateStr]
    );
    const consumed = parseInt(used.rows[0]?.total ?? 0, 10) || 0;
    const remaining = Math.max(0, policy.maxLateMinutesPerMonth - consumed);
    late = Math.min(late, remaining);
  }

  if (policy.combineLateAndUndertime) {
    under += late;
    late = 0;
  }

  late = applyPolicyConversion(late, policy.convertLateToEquivalentDay, policy.workHoursPerDay, policy.deductionMultiplier);
  under = applyPolicyConversion(
    under,
    policy.convertUndertimeToEquivalentDay,
    policy.workHoursPerDay,
    policy.deductionMultiplier
  );
  return { lateMinutes: late, undertimeMinutes: under, policy };
}

/** Get minutes-from-midnight in a specific IANA timezone from a Date/ISO value. */
function minutesFromMidnightInTimeZone(val, timeZone = HRMS_TIMEZONE) {
  if (!val) return null;
  const d = val instanceof Date ? val : new Date(val);
  if (isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(d);
  const hh = parseInt(parts.find((p) => p.type === 'hour')?.value ?? '0', 10);
  const mm = parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
  return hh * 60 + mm;
}

/** Normalize date value to YYYY-MM-DD for PostgreSQL. Handles Date objects and ISO strings. */
function toIsoDateStr(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  const s = String(val);
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? m[0] : null;
}

/** Return calendar date YYYY-MM-DD for API responses (avoids timezone shift when JSON serializes Date as UTC). */
function toDateOnlyResponse(val) {
  if (!val) return null;
  const s = String(val);
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? m[0] : null;
}
/** 1 PM in minutes. */
const ONE_PM_MINUTES = 13 * 60;

/**
 * Derive shift type from assignment shift info.
 * Returns 'am_only' | 'pm_only' | 'full_day' | 'single_session' | null (no shift).
 * - pm_only: shift starts at or after noon (startMinutes >= 720)
 * - am_only: no break_end and shift ends by 1 PM
 * - full_day: otherwise (has both AM and PM periods)
 */
function getShiftType(shiftInfo) {
  return resolveShiftType(shiftInfo);
}

/** Expected net work minutes for a shift (exclude lunch on full-day shifts). */
function getExpectedWorkMinutes(shiftInfo) {
  return resolveExpectedWorkMinutes(shiftInfo);
}

/**
 * Get which logs are expected for the shift.
 * Returns { needsAm: boolean, needsPm: boolean, needsInOut: boolean }.
 * needsAm: expects time_in + break_out
 * needsPm: expects break_in + time_out
 */
function getShiftExpectedLogs(shiftInfo) {
  return resolveExpectedLogsForDay(shiftInfo, null);
}

/**
 * Get expected logs for a day considering holiday/suspension coverage.
 * holidayInfo: { holiday_type, coverage } or null.
 * - whole_day or regular/special/local: no logs required.
 * - am_only (work_suspension): only PM required.
 * - pm_only (work_suspension): only AM required.
 */
function getExpectedLogsForDay(shiftInfo, holidayInfo) {
  return resolveExpectedLogsForDay(shiftInfo, holidayInfo);
}

/**
 * Get employee's assignment for a date (effective_from <= date <= effective_to, is_active).
 * Returns { startMinutes, endMinutes, graceMinutes, breakEndMinutes } or null if no assignment/shift.
 * breakEndMinutes: PM shift start (when late is checked for break_in). Null = no PM late check.
 * endMinutes: shift end time in minutes from midnight (for validating clock-in outside shift).
 */
async function getAssignmentShiftForDate(employeeId, dateStr) {
  await ensureShiftPunchModeColumn(pool);
  const result = await pool.query(
    `SELECT a.override_start_time::text AS override_start_time,
            a.override_end_time::text AS override_end_time,
            a.override_break_end::text AS override_break_end,
            a.effective_from, a.effective_to,
            s.start_time::text AS shift_start,
            s.end_time::text AS shift_end,
            s.break_end::text AS shift_break_end,
            s.punch_mode,
            s.grace_period_minutes
     FROM assignments a
     LEFT JOIN shifts s ON a.shift_id = s.id
     WHERE a.employee_id = $1
       AND (a.is_active IS NULL OR a.is_active = true)
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
     LIMIT 1`,
    [employeeId, dateStr]
  );
  const row = result.rows[0];
  if (!row) return null;
  const startTimeStr = row.override_start_time || row.shift_start;
  if (!startTimeStr) return null;
  const startMinutes = timeToMinutes(startTimeStr);
  if (startMinutes == null) return null;
  const endTimeStr = row.override_end_time || row.shift_end;
  const endMinutes = endTimeStr ? timeToMinutes(endTimeStr) : null;
  const graceMinutes = row.grace_period_minutes != null ? parseInt(row.grace_period_minutes, 10) : 0;
  const breakEndStr = row.override_break_end || row.shift_break_end;
  const breakEndMinutes = breakEndStr ? timeToMinutes(breakEndStr) : null;
  return {
    startMinutes,
    endMinutes,
    graceMinutes,
    breakEndMinutes,
    punchMode: row.punch_mode || 'auto',
  };
}

/**
 * Compute AM status from shift: 'late' if time_in is after start_time + grace, else 'present'.
 * Returns 'present' if no assignment/shift.
 */
async function computeStatusFromShift(employeeId, dateStr, timeInIso) {
  if (!timeInIso) return 'present';
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo) return 'present';
  const { startMinutes, graceMinutes } = shiftInfo;
  const cutoffMinutes = startMinutes + graceMinutes;

  const localMins = minutesFromMidnightInTimeZone(timeInIso);
  if (localMins == null) return 'present';
  return localMins > cutoffMinutes ? 'late' : 'present';
}

/**
 * Compute PM status: 'late' if break_in is after break_end + grace, else 'present'.
 * Returns null if no break_in, or if no shift break_end configured (no PM late check).
 */
async function computePmLateStatus(employeeId, dateStr, breakInIso) {
  if (!breakInIso) return null;
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo || shiftInfo.breakEndMinutes == null) return 'present'; // no PM cutoff = present
  const { breakEndMinutes, graceMinutes } = shiftInfo;
  const cutoffMinutes = breakEndMinutes + graceMinutes;

  const localMins = minutesFromMidnightInTimeZone(breakInIso);
  if (localMins == null) return 'present';
  return localMins > cutoffMinutes ? 'late' : 'present';
}

/**
 * Compute total late minutes: AM late (time_in after start+grace) + PM late (break_in after pmStart+grace).
 * For full-day/AM: PM late uses breakEndMinutes. For PM-only: uses startMinutes (shift start = PM start).
 * Returns 0 for holiday/on_leave or when no shift. For partial-day suspension (coverage am_only/pm_only),
 * only the non-suspended half is evaluated. Seconds ignored.
 */
async function computeLateMinutes(employeeId, dateStr, timeInIso, breakInIso, status, holidayId, coverage) {
  if (status === 'on_leave') return 0;
  const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
  if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo) return 0;
  const { startMinutes, graceMinutes, breakEndMinutes } = shiftInfo;
  const type = getShiftType(shiftInfo);
  let total = 0;
  const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
  const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
  if (evalAm && timeInIso && type !== 'pm_only') {
    const localMins = minutesFromMidnightInTimeZone(timeInIso);
    if (localMins == null) return total;
    const cutoff = startMinutes + graceMinutes;
    if (localMins > cutoff) total += localMins - cutoff;
  }
  const pmStartMinutes = breakEndMinutes ?? startMinutes;
  if (evalPm && breakInIso && (type === 'pm_only' || pmStartMinutes != null)) {
    const localMins = minutesFromMidnightInTimeZone(breakInIso);
    if (localMins == null) return total;
    const cutoff = pmStartMinutes + graceMinutes;
    if (localMins > cutoff) total += localMins - cutoff;
  }
  return total;
}

/**
 * Compute undertime minutes: minutes before shift end when clocking out.
 * - AM-only: uses break_out (AM end) vs end_time
 * - PM-only / full-day: uses time_out vs end_time
 * Returns 0 for holiday/on_leave or when no shift. For partial-day suspension (coverage am_only/pm_only),
 * only the non-suspended half is evaluated. Seconds ignored.
 */
async function computeUndertimeMinutes(
  employeeId,
  dateStr,
  timeOutIso,
  breakOutIso,
  status,
  holidayId,
  coverage,
  timeInIso,
  breakInIso,
  locatorSegments = []
) {
  if (status === 'on_leave') return 0;
  if (
    status === 'on_field' &&
    !timeInIso &&
    !breakOutIso &&
    !breakInIso &&
    !timeOutIso
  ) {
    return 0;
  }
  const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
  if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo || shiftInfo.endMinutes == null) return 0;
  const type = getShiftType(shiftInfo);
  const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
  const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
  const locatorSegSet = new Set(
    (Array.isArray(locatorSegments) ? locatorSegments : [])
      .map((s) => String(s).toUpperCase().trim())
  );
  // Use HRMS_TIMEZONE so "today" matches the business calendar date, not UTC.
  const todayStr = todayInHrmsTimezone();
  const nowMinutes = nowMinutesInHrmsTimezone();
  let amUndertimePenalty = 0;
  if (type === 'full_day' && evalAm && shiftInfo.startMinutes != null) {
    const hasAmLogs =
      (timeInIso != null || locatorSegSet.has('AM IN')) &&
      (breakOutIso != null || locatorSegSet.has('AM OUT'));
    const pmStartMinutes = shiftInfo.breakEndMinutes ?? NOON_MINUTES;
    const amWindowClosed =
      dateStr < todayStr || (dateStr === todayStr && nowMinutes >= pmStartMinutes);
    if (!hasAmLogs && amWindowClosed) {
      amUndertimePenalty = Math.max(0, pmStartMinutes - shiftInfo.startMinutes);
    }
  }
  let clockOutMins = null;
  if (evalAm && type === 'am_only' && breakOutIso) {
    clockOutMins = minutesFromMidnightInTimeZone(breakOutIso);
  } else if (evalPm && timeOutIso) {
    clockOutMins = minutesFromMidnightInTimeZone(timeOutIso);
  }
  if (clockOutMins == null) {
    // Incomplete record: employee clocked in but never clocked out.
    // Compute undertime as full shift duration only if:
    //   - The date is in the past, OR
    //   - Today but shift has already ended.
    const hasClockIn = !!(timeInIso || breakInIso);
    if (!hasClockIn) return 0;
    const isPast = dateStr < todayStr;
    const isShiftOver = dateStr === todayStr && nowMinutes > shiftInfo.endMinutes;
    if (isPast || isShiftOver) {
      // For full-day shifts, undertime baseline is net work minutes (exclude lunch),
      // not raw elapsed span (e.g. 8-5 should be 480, not 540).
      const startMinutes = shiftInfo.startMinutes != null ? shiftInfo.startMinutes : 0;
      const spanMinutes = Math.max(0, shiftInfo.endMinutes - startMinutes);
      if (type === 'full_day') {
        const lunchMinutes =
          shiftInfo.breakEndMinutes != null
            ? Math.max(0, shiftInfo.breakEndMinutes - NOON_MINUTES)
            : 60;
        return Math.max(0, spanMinutes - lunchMinutes) + amUndertimePenalty;
      }
      return spanMinutes + amUndertimePenalty;
    }
    return 0;
  }
  const endMinutes = shiftInfo.endMinutes;
  if (clockOutMins >= endMinutes) return 0;
  return (endMinutes - clockOutMins) + amUndertimePenalty;
}

/**
 * Compute attendance remark. Priority: 1) Holiday/Suspension 2) Leave 3) Absent 4) Incomplete 5) Late+Undertime 6) Late 7) Undertime 8) On Time.
 * holidayInfo: { name, holiday_type, coverage } or null.
 */
async function computeAttendanceRemark(
  record,
  shiftInfo,
  holidayId,
  leaveRequestId,
  holidayInfo,
  locatorSegments = []
) {
  if (record.holiday_id != null || holidayId != null || record.status === 'holiday') {
    const name = (holidayInfo && holidayInfo.name) || record.holiday_name || 'Holiday';
    const cov = (holidayInfo && holidayInfo.coverage) || record.coverage;
    if (cov === 'am_only') return `${name} (AM)`;
    if (cov === 'pm_only') return `${name} (PM)`;
    return name;
  }
  if (record.leave_request_id != null || leaveRequestId != null || record.status === 'on_leave') {
    return (record.leave_type_name && String(record.leave_type_name).trim()) || 'Leave';
  }
  const locatorSegSet = new Set(
    (Array.isArray(locatorSegments) ? locatorSegments : [])
      .map((s) => String(s).toUpperCase().trim())
  );
  const hasPhysicalLog =
    record.time_in ||
    record.break_out ||
    record.break_in ||
    record.time_out;
  const hasAnyLog =
    hasPhysicalLog || locatorSegSet.size > 0;
  if (!hasAnyLog) return 'Absent';
  if (record.status === 'invalid') return 'Invalid Log';
  if (record.status === 'on_field' && !hasPhysicalLog) {
    if (
      normalizeLocatorRequestType(record.locator_slip_request_type) ===
      'work_from_home'
    ) {
      return 'WFH';
    }
    const segments = Array.from(locatorSegSet);
    const segText = segments.length > 0 ? ` (${segments.join(', ')})` : '';
    return `${locatorRequestTypeLabel(record.locator_slip_request_type)}${segText}`;
  }

  const expected = getExpectedLogsForDay(shiftInfo, holidayInfo);
  const hasAm =
    (record.time_in != null || locatorSegSet.has('AM IN')) &&
    (record.break_out != null || locatorSegSet.has('AM OUT'));
  const hasPm =
    (record.break_in != null || locatorSegSet.has('PM IN')) &&
    (record.time_out != null || locatorSegSet.has('PM OUT'));
  const hasInOut = record.time_in != null && record.time_out != null;
  const missingRequired =
    (expected.needsAm && !hasAm) ||
    (expected.needsPm && !hasPm) ||
    (expected.needsInOut && !hasInOut);
  if (missingRequired) return 'Incomplete';

  const late = (record.late_minutes ?? 0) > 0;
  const under = (record.undertime_minutes ?? 0) > 0;
  if (late && under) return 'Late + Undertime';
  if (late) return 'Late';
  if (under) return 'Undertime';
  return 'On Time';
}

/** YYYY-MM-DD from pg date (avoid TZ shift). */
function holidayDateToStr(v) {
  if (v == null) return null;
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.split('T')[0];
  if (v instanceof Date) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, '0');
    const d = String(v.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(v).split('T')[0];
}

/** Get all active holiday dates in [startStr, endStr]. Returns array of { dateStr, id, name, holiday_type, coverage }. Tolerates missing coverage column. */
async function getHolidaysInRange(startStr, endStr) {
  if (!startStr || !endStr) return [];
  const hasCoverage = await _holidaysHasCoverageColumn();
  const cov = hasCoverage ? ', coverage' : '';
  const nonRecur = await pool.query(
    `SELECT id, name, holiday_type, date_from, date_to, recurring${cov}
     FROM holidays
     WHERE (is_active IS NULL OR is_active = true)
       AND recurring = false
       AND date_from <= $2::date AND date_to >= $1::date`,
    [startStr, endStr]
  );
  const recur = await pool.query(
    `SELECT id, name, holiday_type, date_from, date_to, recurring${cov}
     FROM holidays
     WHERE (is_active IS NULL OR is_active = true) AND recurring = true`
  );
  if (!hasCoverage) {
    for (const r of nonRecur.rows) r.coverage = 'whole_day';
    for (const r of recur.rows) r.coverage = 'whole_day';
  }
  const byDate = new Map();
  function pushDate(ds, r) {
    if (byDate.has(ds)) return;
    byDate.set(ds, {
      dateStr: ds,
      id: r.id,
      name: r.name,
      holiday_type: r.holiday_type,
      coverage: r.coverage || 'whole_day',
    });
  }
  for (const r of nonRecur.rows) {
    const dates = expandNonRecurringToWindow(
      holidayDateToStr(r.date_from),
      holidayDateToStr(r.date_to),
      startStr,
      endStr
    );
    for (const ds of dates) pushDate(ds, r);
  }
  for (const r of recur.rows) {
    const dates = expandRecurringToWindow(
      holidayDateToStr(r.date_from),
      holidayDateToStr(r.date_to),
      startStr,
      endStr
    );
    for (const ds of dates) pushDate(ds, r);
  }
  return Array.from(byDate.values()).sort((a, b) => a.dateStr.localeCompare(b.dateStr));
}

/** Get approved leave dates in [startStr, endStr] for employees. Returns Set of "employeeId|YYYY-MM-DD". */
async function getApprovedLeaveKeysInRange(employeeIds, startStr, endStr) {
  if (!startStr || !endStr) return new Set();
  if (!employeeIds || employeeIds.length === 0) return new Set();
  const res = await pool.query(
    `SELECT employee_id, start_date::text AS start_str, end_date::text AS end_str
     FROM leave_requests
     WHERE status = 'approved'
       AND employee_id = ANY($1::uuid[])
       AND start_date <= $3::date
       AND end_date >= $2::date`,
    [employeeIds, startStr, endStr]
  );
  const out = new Set();
  for (const r of res.rows) {
    const empId = r.employee_id;
    const s = String(r.start_str).slice(0, 10);
    const e = String(r.end_str).slice(0, 10);
    let cur = new Date(`${s}T00:00:00`);
    const end = new Date(`${e}T00:00:00`);
    while (cur <= end) {
      const dStr = cur.toISOString().slice(0, 10);
      if (dStr >= startStr && dStr <= endStr) out.add(`${empId}|${dStr}`);
      cur.setDate(cur.getDate() + 1);
    }
  }
  return out;
}

/**
 * Get approved locator slips in [startStr, endStr] for employees.
 * Returns Map key "employeeId|YYYY-MM-DD" -> metadata object.
 */
async function getApprovedLocatorByDateInRange(employeeIds, startStr, endStr) {
  const out = new Map();
  if (!startStr || !endStr) return out;
  if (!employeeIds || employeeIds.length === 0) return out;
  const res = await pool.query(
    `SELECT id, employee_id, slip_date::text AS slip_date_str,
            am_in, am_out, pm_in, pm_out, request_type, office, reason
     FROM locator_slips
     WHERE status = 'approved'
       AND employee_id = ANY($1::uuid[])
       AND slip_date >= $2::date
       AND slip_date <= $3::date
     ORDER BY updated_at DESC, created_at DESC`,
    [employeeIds, startStr, endStr]
  );
  for (const r of res.rows) {
    const dateStr = String(r.slip_date_str).slice(0, 10);
    const key = `${r.employee_id}|${dateStr}`;
    if (out.has(key)) continue;
    const segments = [];
    if (r.am_in) segments.push('AM IN');
    if (r.am_out) segments.push('AM OUT');
    if (r.pm_in) segments.push('PM IN');
    if (r.pm_out) segments.push('PM OUT');
    out.set(key, {
      id: r.id,
      request_type: normalizeLocatorRequestType(r.request_type),
      office: r.office || null,
      reason: r.reason || null,
      segments,
    });
  }
  return out;
}

/**
 * Get assignments+shift info for employees that overlap [startStr, endStr].
 * Returns Map employeeId -> array of { effective_from, effective_to, startMinutes, endMinutes, breakEndMinutes, graceMinutes, workingDays } sorted by effective_from desc.
 */
async function getAssignmentsForEmployeesInRange(employeeIds, startStr, endStr) {
  const map = new Map();
  if (!employeeIds || employeeIds.length === 0) return map;
  if (!startStr || !endStr) return map;
  await ensureShiftPunchModeColumn(pool);
  const res = await pool.query(
    `SELECT a.employee_id,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to,
            COALESCE(a.override_start_time, s.start_time) AS start_time,
            COALESCE(a.override_end_time, s.end_time) AS end_time,
            COALESCE(a.override_break_end, s.break_end) AS break_end,
            s.punch_mode,
            s.grace_period_minutes,
            s.working_days
     FROM assignments a
     LEFT JOIN shifts s ON s.id = a.shift_id
     WHERE a.employee_id = ANY($1::uuid[])
       AND (a.is_active IS NULL OR a.is_active = true)
       AND a.effective_from <= $3::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.employee_id, a.effective_from DESC`,
    [employeeIds, startStr, endStr]
  );
  for (const r of res.rows) {
    const empId = r.employee_id;
    const startTimeStr = r.start_time;
    if (!startTimeStr) continue;
    const shift = {
      effective_from: String(r.effective_from).slice(0, 10),
      effective_to: r.effective_to ? String(r.effective_to).slice(0, 10) : null,
      startMinutes: timeToMinutes(startTimeStr),
      endMinutes: r.end_time ? timeToMinutes(r.end_time) : null,
      breakEndMinutes: r.break_end ? timeToMinutes(r.break_end) : null,
      punchMode: r.punch_mode || 'auto',
      graceMinutes: r.grace_period_minutes != null ? parseInt(r.grace_period_minutes, 10) : 0,
      workingDays: Array.isArray(r.working_days)
        ? r.working_days.map((x) => parseInt(x, 10)).filter((x) => Number.isFinite(x))
        : null,
    };
    const arr = map.get(empId) || [];
    arr.push(shift);
    map.set(empId, arr);
  }
  return map;
}

/** Find applicable assignment shift info for employeeId on dateStr using pre-fetched assignments. */
function getShiftInfoForDateFromAssignments(assignmentsByEmployee, employeeId, dateStr) {
  const list = assignmentsByEmployee.get(employeeId);
  if (!list || list.length === 0) return null;
  for (const a of list) {
    if (a.effective_from <= dateStr && (!a.effective_to || a.effective_to >= dateStr)) return a;
  }
  return null;
}

/** ISO weekday (1=Mon..7=Sun) from YYYY-MM-DD. */
function isoWeekdayFromDateStr(dateStr) {
  const d = new Date(`${dateStr}T00:00:00`);
  const js = d.getDay(); // 0=Sun..6=Sat
  return js === 0 ? 7 : js;
}

/** True if holidays table has coverage column (work suspension migration applied). */
let _holidaysHasCoverageColumnCached = null;
async function _holidaysHasCoverageColumn() {
  if (_holidaysHasCoverageColumnCached != null) return _holidaysHasCoverageColumnCached;
  try {
    await pool.query('SELECT coverage FROM holidays LIMIT 1');
    _holidaysHasCoverageColumnCached = true;
  } catch {
    _holidaysHasCoverageColumnCached = false;
  }
  return _holidaysHasCoverageColumnCached;
}

/** Get active holiday for a date, if any. Non-recurring range match first, then recurring template. Returns { id, name, holiday_type, coverage } or null. Tolerates missing coverage column. */
async function getHolidayByDate(dateStr) {
  const hasCoverage = await _holidaysHasCoverageColumn();
  const cols = hasCoverage ? 'id, name, holiday_type, coverage' : 'id, name, holiday_type';
  const exact = await pool.query(
    `SELECT ${cols} FROM holidays
     WHERE (is_active IS NULL OR is_active = true) AND recurring = false
       AND date_from <= $1::date AND date_to >= $1::date
     ORDER BY date_from
     LIMIT 1`,
    [dateStr]
  );
  if (exact.rows[0]) {
    const r = exact.rows[0];
    return { ...r, coverage: r.coverage || 'whole_day' };
  }
  const recurring = await pool.query(
    `SELECT ${cols}, date_from, date_to FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)`
  );
  for (const r of recurring.rows) {
    if (dateInRecurringRange(dateStr, holidayDateToStr(r.date_from), holidayDateToStr(r.date_to))) {
      return { id: r.id, name: r.name, holiday_type: r.holiday_type, coverage: r.coverage || 'whole_day' };
    }
  }
  return null;
}

// GET /api/dtr-daily-summary - list for admin (filters: start_date, end_date, employee_id, department_id, limit, offset)
// - No date range: `limit` applies to SQL only (default 500, max 1000), e.g. dashboard "recent" list.
// - With start_date + end_date: SQL uses a high cap so merge/injection sees all dtr_daily_summary rows; optional
//   `limit` + `offset` slice the *final* merged array (omit `limit` to return everyone for that range, e.g. Time Logs "all").
router.get('/', protect, async (req, res) => {
  try {
    const { start_date, end_date, employee_id, department_id, limit: limitRaw, offset: offsetRaw } = req.query;
    const hasDateRange = !!(start_date && end_date);
    const recomputeExistingRows = isTruthyQueryFlag(req.query.recompute);
    const params = [];
    const conditions = [];
    let i = 1;
    const privileged = ['admin', 'hr', 'supervisor'].includes(req.user?.role);
    if (!privileged) {
      conditions.push(`d.employee_id = $${i++}`);
      params.push(req.user.id);
    }
    if (start_date) {
      conditions.push(`d.attendance_date >= $${i++}`);
      params.push(start_date);
    }
    if (end_date) {
      conditions.push(`d.attendance_date <= $${i++}`);
      params.push(end_date);
    }
    if (employee_id && privileged) {
      conditions.push(`d.employee_id = $${i++}`);
      params.push(employee_id);
    }
    if (department_id && start_date && end_date) {
      const depIdx = i;
      const endIdx = i + 1;
      const startIdx = i + 2;
      conditions.push(`d.employee_id IN (
        SELECT DISTINCT a.employee_id FROM assignments a
        WHERE a.department_id = $${depIdx}
          AND (a.is_active IS NULL OR a.is_active = true)
          AND a.effective_from <= $${endIdx}::date
          AND (a.effective_to IS NULL OR a.effective_to >= $${startIdx}::date)
      )`);
      params.push(department_id, end_date, start_date);
      i += 3;
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const sqlMaxRows = hasDateRange
      ? Math.min(parseInt(req.query.sql_cap, 10) || 100000, 250000)
      : Math.min(parseInt(limitRaw, 10) || 500, 1000);
    params.push(sqlMaxRows);

    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
      : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
    const result = await pool.query(
      `SELECT d.id, d.employee_id, d.attendance_date, d.attendance_date::text AS attendance_date_iso, d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours,
              d.late_minutes, d.undertime_minutes, d.status, d.pm_status, d.remarks, d.source, d.holiday_id, d.leave_request_id,
              d.created_at, d.updated_at,
              u.full_name AS employee_name,
              ${joinCols},
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       LEFT JOIN leave_requests lr ON lr.id = d.leave_request_id
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       ${where}
       ORDER BY d.attendance_date DESC, d.time_in DESC NULLS LAST
       LIMIT $${i}`,
      params
    );
    const rawRows = result.rows;
    if (!hasCoverage) for (const r of rawRows) r.holiday_coverage = 'whole_day';

    const startStr = start_date ? String(start_date).slice(0, 10) : null;
    const endStr = end_date ? String(end_date).slice(0, 10) : null;
    const rawEmployeeIds = [...new Set(rawRows.map((r) => r.employee_id).filter(Boolean))];
    const rawDateStrings = rawRows
      .map((r) => (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date))
      .filter(Boolean)
      .sort();
    const rawRangeStart = startStr || rawDateStrings[0] || null;
    const rawRangeEnd = endStr || rawDateStrings[rawDateStrings.length - 1] || null;
    const rawAssignmentsByEmployee =
      rawEmployeeIds.length > 0 && rawRangeStart && rawRangeEnd
        ? await getAssignmentsForEmployeesInRange(rawEmployeeIds, rawRangeStart, rawRangeEnd)
        : new Map();

    const rows = await Promise.all(rawRows.map(async (r) => {
      // Use the date-only text from SQL to avoid timezone shifting issues when JS receives Date objects.
      const dateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date);
      const shiftInfo = dateStr
        ? (
          getShiftInfoForDateFromAssignments(rawAssignmentsByEmployee, r.employee_id, dateStr) ||
          await getAssignmentShiftForDate(r.employee_id, dateStr)
        )
        : null;
      const coverage = r.holiday_coverage || 'whole_day';
      const isPartialSuspension = r.status === 'holiday' && (coverage === 'am_only' || coverage === 'pm_only');
      let lateMinutes = r.late_minutes != null ? parseInt(r.late_minutes, 10) : 0;
      let undertimeMinutes = r.undertime_minutes != null ? parseInt(r.undertime_minutes, 10) : 0;
      if (recomputeExistingRows && dateStr && r.status !== 'on_leave' && (r.status !== 'holiday' || isPartialSuspension)) {
        // Optional expensive path for after schedule/policy changes. The normal
        // Time Logs view uses stored summary values for fast reads.
        lateMinutes = await computeLateMinutes(
          r.employee_id,
          dateStr,
          r.time_in,
          r.break_in,
          r.status,
          r.holiday_id,
          coverage
        );
        undertimeMinutes = await computeUndertimeMinutes(
          r.employee_id,
          dateStr,
          r.time_out,
          r.break_out,
          r.status,
          r.holiday_id,
          coverage,
          r.time_in,
          r.break_in
        );
        const adjusted = await applyAttendancePolicyPenalties(
          r.employee_id,
          dateStr,
          lateMinutes,
          undertimeMinutes
        );
        lateMinutes = adjusted.lateMinutes;
        undertimeMinutes = adjusted.undertimeMinutes;
      }
      const recordForRemark = {
        time_in: r.time_in,
        break_out: r.break_out,
        break_in: r.break_in,
        time_out: r.time_out,
        late_minutes: lateMinutes,
        undertime_minutes: undertimeMinutes,
        status: r.status,
        holiday_id: r.holiday_id,
        leave_request_id: r.leave_request_id,
        leave_type_name: r.leave_type_name,
      };
      const holidayInfo = r.holiday_id ? { name: r.holiday_name, holiday_type: r.holiday_type, coverage } : null;
      let attendanceRemark = await computeAttendanceRemark(recordForRemark, shiftInfo, r.holiday_id, r.leave_request_id, holidayInfo);
      const recordDateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date);
      return {
        id: r.id,
        user_id: r.employee_id,
        record_date: recordDateStr,
        time_in: r.time_in,
        break_out: r.break_out,
        break_in: r.break_in,
        time_out: r.time_out,
        total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
        late_minutes: lateMinutes,
        undertime_minutes: undertimeMinutes,
        status: r.status,
        pm_status: r.pm_status,
        remarks: r.remarks,
        attendance_remark: attendanceRemark,
        holiday_id: r.holiday_id,
        leave_request_id: r.leave_request_id,
        holiday_name: r.holiday_name,
        holiday_type: r.holiday_type,
        coverage,
        leave_type_name: r.leave_type_name || null,
        source: r.source || null,
        created_at: r.created_at,
        updated_at: r.updated_at,
        employee_name: r.employee_name,
        shift_punch_mode: shiftInfo?.punchMode || 'auto',
      };
    }));

    // Inject synthetic holiday rows for dates with no record
    if (startStr && endStr) {
      const existingKeys = new Set(
        rawRows.map((r) => {
          const dateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date);
          return `${r.employee_id}|${dateStr}`;
        })
      );
      const userIdToName = {};
      for (const r of rawRows) {
        if (r.employee_id && r.employee_name) userIdToName[r.employee_id] = r.employee_name;
      }
      let employeeIds;
      if (employee_id) {
        employeeIds = [employee_id];
        if (!userIdToName[employee_id]) {
          const u = await pool.query(
            'SELECT full_name FROM users WHERE id = $1',
            [employee_id]
          );
          if (u.rows[0]) userIdToName[employee_id] = u.rows[0].full_name;
        }
      } else if (department_id && startStr && endStr) {
        const deptEmps = await pool.query(
          `SELECT DISTINCT u.id, u.full_name
           FROM assignments a
           JOIN users u ON u.id = a.employee_id AND u.is_active = true
           WHERE a.department_id = $1
             AND (a.is_active IS NULL OR a.is_active = true)
             AND a.effective_from <= $2::date
             AND (a.effective_to IS NULL OR a.effective_to >= $3::date)
           ORDER BY u.full_name`,
          [department_id, endStr, startStr]
        );
        employeeIds = deptEmps.rows.map((r) => r.id).filter(Boolean);
        for (const r of deptEmps.rows) {
          if (r.id && r.full_name) userIdToName[r.id] = r.full_name;
        }
      } else {
        // Employees with at least one active assignment overlapping the date range (not all active users).
        const assignedEmps = await pool.query(
          `SELECT DISTINCT u.id, u.full_name
           FROM assignments a
           JOIN users u ON u.id = a.employee_id AND u.is_active = true
           WHERE (a.is_active IS NULL OR a.is_active = true)
             AND a.effective_from <= $1::date
             AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
           ORDER BY u.full_name`,
          [endStr, startStr]
        );
        employeeIds = assignedEmps.rows.map((r) => r.id).filter(Boolean);
        for (const r of assignedEmps.rows) {
          if (r.id && r.full_name) userIdToName[r.id] = r.full_name;
        }
      }

      const assignmentsByEmployee = await getAssignmentsForEmployeesInRange(employeeIds, startStr, endStr);

      const holidaysInRange = await getHolidaysInRange(startStr, endStr);
      const holidayByDate = new Map();
      for (const h of holidaysInRange) holidayByDate.set(h.dateStr, h);

      // 1) Inject synthetic holiday rows for dates with no record — only for employees
      //    scheduled that calendar day (same working-day + assignment rules as absent injection).
      if (holidaysInRange.length > 0) {
        for (const h of holidaysInRange) {
          const cov = h.coverage || 'whole_day';
          let remark = h.name || 'Holiday';
          if (cov === 'am_only') remark = `${remark} (AM)`;
          else if (cov === 'pm_only') remark = `${remark} (PM)`;
          for (const empId of employeeIds) {
            const key = `${empId}|${h.dateStr}`;
            if (existingKeys.has(key)) continue;
            const shiftInfo = getShiftInfoForDateFromAssignments(
              assignmentsByEmployee,
              empId,
              h.dateStr
            );
            if (!shiftInfo) continue;
            const workingDays = shiftInfo.workingDays;
            if (!Array.isArray(workingDays) || workingDays.length === 0) continue;
            const isoDow = isoWeekdayFromDateStr(h.dateStr);
            if (!workingDays.includes(isoDow)) continue;
            existingKeys.add(key);
            rows.push({
              id: null,
              user_id: empId,
              record_date: h.dateStr,
              time_in: null,
              break_out: null,
              break_in: null,
              time_out: null,
              total_hours: null,
              late_minutes: 0,
              undertime_minutes: 0,
              status: 'holiday',
              pm_status: null,
              remarks: null,
              source: 'adjusted',
              attendance_remark: remark,
              holiday_id: h.id,
              leave_request_id: null,
              holiday_name: h.name,
              holiday_type: h.holiday_type,
              coverage: cov,
              created_at: null,
              updated_at: null,
              employee_name: userIdToName[empId] || null,
              shift_punch_mode: shiftInfo?.punchMode || 'auto',
            });
          }
        }
      }

      // 2) Inject synthetic "Absent" rows for working days with no record, only after shift end / for past dates
      // Use HRMS_TIMEZONE so "today" matches the business calendar date, not the server's UTC date.
      const todayStr = todayInHrmsTimezone();
      const nowMinutes = nowMinutesInHrmsTimezone();

      const leaveKeys = await getApprovedLeaveKeysInRange(employeeIds, startStr, endStr);
      const locatorByKey = await getApprovedLocatorByDateInRange(
        employeeIds,
        startStr,
        endStr
      );
      const hasFullDayLocatorCoverage = (locator) => {
        const locatorSegments = Array.isArray(locator?.segments)
          ? locator.segments.map((s) => String(s).toUpperCase().trim())
          : [];
        return ['AM IN', 'AM OUT', 'PM IN', 'PM OUT']
          .every((seg) => locatorSegments.includes(seg));
      };

      // Iterate by calendar date (YYYY-MM-DD) to avoid timezone shifting: e.g. "Day 14" must not show as March 13 in UTC+8.
      const startD = new Date(`${startStr}T12:00:00`); // noon avoids UTC date shift
      const endD = new Date(`${endStr}T12:00:00`);
      for (let d = new Date(startD); d <= endD; d.setDate(d.getDate() + 1)) {
        const dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
        if (dateStr > todayStr) continue; // no future absences

        const holiday = holidayByDate.get(dateStr) || null;
        const holidayCoverage = holiday?.coverage || 'whole_day';
        const isWholeDayHoliday = holiday != null && holidayCoverage === 'whole_day';
        if (isWholeDayHoliday) continue; // holiday row already injected (or exists)

        for (const empId of employeeIds) {
          const key = `${empId}|${dateStr}`;
          if (existingKeys.has(key)) continue;
          if (leaveKeys.has(key)) continue;
          const locator = locatorByKey.get(key);
          if (locator && hasFullDayLocatorCoverage(locator)) continue;

          const shiftInfo = getShiftInfoForDateFromAssignments(assignmentsByEmployee, empId, dateStr);
          if (!shiftInfo) continue; // no assignment/shift => can't determine working day

          const workingDays = shiftInfo.workingDays;
          if (!Array.isArray(workingDays) || workingDays.length === 0) continue;
          const isoDow = isoWeekdayFromDateStr(dateStr);
          if (!workingDays.includes(isoDow)) continue;

          // Only show "Absent" for today after shift end, or any past working day.
          if (dateStr === todayStr) {
            const endMinutes = shiftInfo.endMinutes != null ? shiftInfo.endMinutes : (24 * 60 - 1);
            if (nowMinutes <= endMinutes) continue;
          }

          // Absent = no rendered work; undertime baseline should be net expected
          // work minutes (exclude lunch for full-day shifts).
          const policyForDay = await getAttendancePolicyForEmployeeDate(empId, dateStr);
          const absentUndertime = policyForDay.absentEqualsFullDayDeduction
            ? getExpectedWorkMinutes(shiftInfo)
            : 0;

          existingKeys.add(key);
          rows.push({
            id: null,
            user_id: empId,
            record_date: dateStr,
            time_in: null,
            break_out: null,
            break_in: null,
            time_out: null,
            total_hours: null,
            late_minutes: 0,
            undertime_minutes: absentUndertime,
          status: 'absent',
          pm_status: null,
          remarks: null,
          source: null,
          attendance_remark: 'Absent',
          holiday_id: null,
          leave_request_id: null,
          holiday_name: null,
          holiday_type: null,
          coverage: null,
          created_at: null,
          updated_at: null,
          employee_name: userIdToName[empId] || null,
          shift_punch_mode: shiftInfo?.punchMode || 'auto',
          });
        }
      }

      // 3) Inject synthetic rows for approved locator slips with no existing DTR row.
      for (const [key, locator] of locatorByKey.entries()) {
        if (!hasFullDayLocatorCoverage(locator)) continue;
        if (existingKeys.has(key)) continue;
        const [empId, dateStr] = key.split('|');
        existingKeys.add(key);
        rows.push({
          id: null,
          user_id: empId,
          record_date: dateStr,
          time_in: null,
          break_out: null,
          break_in: null,
          time_out: null,
          total_hours: null,
          late_minutes: 0,
          undertime_minutes: 0,
          status: 'on_field',
          pm_status: null,
          remarks: null,
          source: 'adjusted',
          attendance_remark: locatorAttendanceRemark(locator),
          holiday_id: null,
          leave_request_id: null,
          locator_slip_id: locator.id || null,
          locator_slip_request_type: locator.request_type || 'locator',
          locator_slip_office: locator.office || null,
          locator_slip_reason: locator.reason || null,
          locator_slip_segments: locator.segments || [],
          holiday_name: null,
          holiday_type: null,
          coverage: null,
          created_at: null,
          updated_at: null,
          employee_name: userIdToName[empId] || null,
          shift_punch_mode: getShiftInfoForDateFromAssignments(assignmentsByEmployee, empId, dateStr)?.punchMode || 'auto',
        });
      }

      // 4) Annotate existing rows with locator metadata for transparency.
      for (const row of rows) {
        const rowKey = `${row.user_id}|${row.record_date}`;
        const locator = locatorByKey.get(rowKey);
        if (!locator) continue;
        row.locator_slip_id = locator.id || null;
        row.locator_slip_request_type = locator.request_type || 'locator';
        row.locator_slip_office = locator.office || null;
        row.locator_slip_reason = locator.reason || null;
        row.locator_slip_segments = locator.segments || [];

        const hasFullDayCoverage = hasFullDayLocatorCoverage(locator);

        // Only clear deductions when locator slip covers the full day.
        // Partial locator segments (e.g., AM IN only) should keep computed
        // late/undertime from other uncovered segments.
        if (
          hasFullDayCoverage &&
          row.status !== 'holiday' &&
          row.status !== 'on_leave'
        ) {
          row.late_minutes = 0;
          row.undertime_minutes = 0;
        }

        const hasAnyLog = !!(row.time_in || row.break_out || row.break_in || row.time_out);
        if (
          !hasAnyLog &&
          hasFullDayCoverage &&
          row.status !== 'holiday' &&
          row.status !== 'on_leave'
        ) {
          row.status = 'on_field';
          row.late_minutes = 0;
          row.undertime_minutes = 0;
          row.attendance_remark = locatorAttendanceRemark(locator);
        }

        // Re-evaluate remark/undertime with locator segment substitution so
        // partial approved locator segments (e.g., AM IN) can satisfy
        // completeness checks with existing punches.
        const rowDateStr = String(row.record_date).slice(0, 10);
        const holidayInfo = holidayByDate.get(rowDateStr) || null;
        const coverage = holidayInfo?.coverage || row.coverage || null;
        row.undertime_minutes = await computeUndertimeMinutes(
          row.user_id,
          rowDateStr,
          row.time_out,
          row.break_out,
          row.status,
          row.holiday_id,
          coverage,
          row.time_in,
          row.break_in,
          row.locator_slip_segments || []
        );
        const shiftInfo =
          getShiftInfoForDateFromAssignments(assignmentsByEmployee, row.user_id, rowDateStr) ||
          await getAssignmentShiftForDate(row.user_id, rowDateStr);
        row.attendance_remark = await computeAttendanceRemark(
          row,
          shiftInfo,
          row.holiday_id,
          row.leave_request_id,
          holidayInfo,
          row.locator_slip_segments || []
        );
      }

      rows.sort((a, b) => {
        const dA = a.record_date;
        const dB = b.record_date;
        if (dA !== dB) return String(dB).localeCompare(String(dA));
        // pg may return timestamptz as Date objects; localeCompare needs strings.
        const tInB = b.time_in != null ? String(b.time_in) : '';
        const tInA = a.time_in != null ? String(a.time_in) : '';
        return tInB.localeCompare(tInA);
      });
    }

    let payload = rows;
    if (hasDateRange && limitRaw != null && String(limitRaw).trim() !== '') {
      const off = Math.max(0, parseInt(offsetRaw, 10) || 0);
      const pageSize = Math.min(Math.max(1, parseInt(limitRaw, 10) || 500), 10000);
      res.setHeader('Access-Control-Expose-Headers', 'X-Total-Count');
      res.setHeader('X-Total-Count', String(rows.length));
      payload = rows.slice(off, off + pageSize);
    }

    res.json(payload);
  } catch (err) {
    console.error('[dtr-daily-summary GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR summary' });
  }
});

// GET /api/dtr-daily-summary/summary - counts for dashboard (DTR + leave pipeline)
router.get('/summary', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    const today = todayInHrmsTimezone();
    const present = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL`,
      [today]
    );
    const late = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL AND status = 'late'`,
      [today]
    );

    let onLeaveToday = 0;
    try {
      const onLeave = await pool.query(
        `SELECT COUNT(DISTINCT COALESCE(user_id, employee_id)) AS c
         FROM leave_requests
         WHERE status = 'approved'
           AND start_date <= $1::date
           AND end_date >= $1::date`,
        [today]
      );
      onLeaveToday = parseInt(onLeave.rows[0]?.c ?? 0, 10);
    } catch (leaveErr) {
      console.warn('[dtr-daily-summary/summary GET] on_leave_today:', leaveErr?.message || leaveErr);
    }

    let pendingApproval = 0;
    try {
      const pend = await pool.query(
        `SELECT COUNT(*) AS c FROM leave_requests
         WHERE status IN ('pending', 'pending_department_head', 'pending_hr')`
      );
      pendingApproval = parseInt(pend.rows[0]?.c ?? 0, 10);
    } catch (pendErr) {
      console.warn('[dtr-daily-summary/summary GET] pending_approval:', pendErr?.message || pendErr);
    }

    res.json({
      present_today: parseInt(present.rows[0]?.c ?? 0, 10),
      late_today: parseInt(late.rows[0]?.c ?? 0, 10),
      on_leave_today: onLeaveToday,
      pending_approval: pendingApproval,
    });
  } catch (err) {
    console.error('[dtr-daily-summary/summary GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR summary counts' });
  }
});

// GET /api/dtr-daily-summary/my-shift-today - current user's shift times for today (for PM In validation)
router.get('/my-shift-today', protect, async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const today = todayInHrmsTimezone();
    const shiftInfo = await getAssignmentShiftForDate(userId, today);
    if (!shiftInfo || shiftInfo.endMinutes == null) {
      return res.json({ start_time: null, end_time: null }); // no shift or no end = no restriction
    }
    res.json({
      start_time: shiftInfo.startMinutes != null ? minutesToTimeStr(shiftInfo.startMinutes) : null,
      start_minutes: shiftInfo.startMinutes != null ? shiftInfo.startMinutes : null,
      end_time: minutesToTimeStr(shiftInfo.endMinutes),
      end_minutes: shiftInfo.endMinutes,
    });
  } catch (err) {
    console.error('[dtr-daily-summary my-shift-today GET]', err);
    res.status(500).json({ error: 'Failed to fetch shift' });
  }
});

// GET /api/dtr-daily-summary/today - get today's record for current user (for clock in/out UI)
router.get('/today', protect, async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const today = todayInHrmsTimezone();
    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage
      ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
      : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
    const result = await pool.query(
      `SELECT d.id, d.employee_id, d.attendance_date, d.attendance_date::text AS attendance_date_iso, d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours, d.status, d.pm_status, d.remarks, d.source, d.holiday_id, d.created_at, d.updated_at,
              u.full_name AS employee_name,
              ${joinCols}
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.employee_id = $1 AND d.attendance_date = $2::date`,
      [userId, today]
    );
    const r = result.rows[0];
    if (r && !hasCoverage) r.holiday_coverage = 'whole_day';
    if (!r) return res.json(null);
    const todayRecordDateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || today;
    let pmStatus = r.pm_status;
    if (pmStatus == null && r.break_in != null && r.holiday_id == null) {
      const dateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date);
      pmStatus = dateStr ? await computePmLateStatus(r.employee_id, dateStr, r.break_in) : 'present';
    }
    res.json({
      id: r.id,
      user_id: r.employee_id,
      record_date: todayRecordDateStr,
      time_in: r.time_in,
      break_out: r.break_out,
      break_in: r.break_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      status: r.status,
      pm_status: pmStatus,
      remarks: r.remarks,
      source: r.source || null,
      holiday_id: r.holiday_id,
      holiday_name: r.holiday_name,
      holiday_type: r.holiday_type,
      coverage: r.holiday_coverage || 'whole_day',
      created_at: r.created_at,
      updated_at: r.updated_at,
      employee_name: r.employee_name,
    });
  } catch (err) {
    console.error('[dtr-daily-summary/today GET]', err);
    res.status(500).json({ error: 'Failed to fetch today record' });
  }
});

/** Compute total_hours from punch points. Supports full-day, AM/PM-only, and single-session records. */
function computeTotalHours(timeIn, breakOut, breakIn, timeOut, shiftInfo = null) {
  return computeTotalHoursFromRecord(
    {
      time_in: timeIn,
      break_out: breakOut,
      break_in: breakIn,
      time_out: timeOut,
    },
    shiftInfo
  );
}

// POST /api/dtr-daily-summary - clock in or create manual record (employee or admin)
router.post('/', protect, async (req, res) => {
  try {
    const { employee_id, attendance_date, time_in, break_out, break_in, time_out, total_hours, reason } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr' || req.user?.role === 'supervisor';
    const targetId = isAdmin && employee_id ? employee_id : userId;
    if (!targetId) return res.status(401).json({ error: 'Not authenticated' });
    if (!isAdmin && targetId !== userId) return res.status(403).json({ error: 'Can only create your own record' });

    const date = attendance_date || new Date().toISOString().slice(0, 10);
    const isAfternoonOnly = break_in && (time_in === null || time_in === undefined);
    const timeIn = isAfternoonOnly ? null : (time_in || new Date().toISOString());
    const holiday = await getHolidayByDate(date);
    const coverage = holiday ? (holiday.coverage || 'whole_day') : null;

    // Reject PM In (break_in) if after shift end time (skip for holidays)
    if (break_in && !holiday) {
      const shiftInfo = await getAssignmentShiftForDate(targetId, date);
      if (shiftInfo && shiftInfo.endMinutes != null) {
        const breakInMins = minutesFromMidnightInTimeZone(break_in);
        if (breakInMins != null && breakInMins > shiftInfo.endMinutes) {
          return res.status(400).json({
            error: `PM clock-in time is after shift end. Shift ends at ${minutesToTimeStr(shiftInfo.endMinutes)}. Clock-in not allowed.`,
          });
        }
      }
    }
    let status = holiday ? 'holiday' : (isAfternoonOnly ? 'absent' : await computeStatusFromShift(targetId, date, timeIn));
    let pmStatus = null;
    if (break_in && !holiday) {
      pmStatus = await computePmLateStatus(targetId, date, break_in);
    }
    const holidayId = holiday ? holiday.id : null;
    const total = total_hours != null ? parseFloat(total_hours) : computeTotalHours(timeIn, break_out, break_in, time_out);
    let lateMinutes = 0;
    let undertimeMinutes = 0;
    if ((!holiday || coverage === 'am_only' || coverage === 'pm_only') && status !== 'on_leave') {
      const rawLate = await computeLateMinutes(targetId, date, timeIn, break_in || null, status, holidayId, coverage);
      const rawUnder = await computeUndertimeMinutes(
        targetId,
        date,
        time_out || null,
        break_out || null,
        status,
        holidayId,
        coverage,
        timeIn || null,
        break_in || null
      );
      const adjusted = await applyAttendancePolicyPenalties(targetId, date, rawLate, rawUnder);
      lateMinutes = adjusted.lateMinutes;
      undertimeMinutes = adjusted.undertimeMinutes;
    }

    const sourceValue = (status === 'holiday' || holidayId) ? 'adjusted' : 'manual';

    const result = await pool.query(
      `INSERT INTO dtr_daily_summary (employee_id, attendance_date, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, holiday_id)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz, $7::numeric, $8, $9, $10, $11, $12, $13)
       RETURNING id, employee_id, attendance_date::text AS attendance_date_iso, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, created_at`,
      [targetId, date, timeIn, break_out || null, break_in || null, time_out || null, total, lateMinutes, undertimeMinutes, status, pmStatus, sourceValue, holidayId]
    );
    const r = result.rows[0];
    const recordDateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || date;

    broadcastBiometricUpdate('dtr_refresh', {
      action: 'manual_inserted',
      userId: String(r.employee_id),
      date: recordDateStr,
      userIds: [String(r.employee_id)],
      dates: [recordDateStr],
    });

    res.status(201).json({
      id: r.id,
      user_id: r.employee_id,
      record_date: recordDateStr,
      time_in: r.time_in,
      break_out: r.break_out,
      break_in: r.break_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      late_minutes: r.late_minutes != null ? parseInt(r.late_minutes, 10) : 0,
      undertime_minutes: r.undertime_minutes != null ? parseInt(r.undertime_minutes, 10) : 0,
      status: r.status,
      pm_status: r.pm_status,
      source: r.source || 'manual',
      created_at: r.created_at,
    });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Record already exists for this employee and date' });
    console.error('[dtr-daily-summary POST]', err);
    res.status(500).json({ error: 'Failed to create DTR record' });
  }
});

// PUT /api/dtr-daily-summary/:id - update (clock out or admin edit)
router.put('/:id', protect, async (req, res) => {
  try {
    const { id } = req.params;
    const { time_in, break_out, break_in, time_out, total_hours, status, remarks } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr' || req.user?.role === 'supervisor';

    const hasCoverage = await _holidaysHasCoverageColumn();
    const joinCols = hasCoverage ? 'h.coverage AS holiday_coverage' : 'NULL::text AS holiday_coverage';
    const check = await pool.query(
      `SELECT d.employee_id, d.attendance_date, d.holiday_id, d.status, d.time_in, d.break_out, d.break_in, d.time_out,
              ${joinCols}
       FROM dtr_daily_summary d
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id = $1`,
      [id]
    );
    if (check.rows.length === 0) return res.status(404).json({ error: 'Record not found' });
    if (!isAdmin && check.rows[0].employee_id !== userId) return res.status(403).json({ error: 'Not allowed to update this record' });

    const existing = check.rows[0];
    const existingCoverage = existing.holiday_coverage || 'whole_day';
    const employeeId = existing.employee_id;
    const dateStr = toIsoDateStr(existing.attendance_date);

    // Reject PM In (break_in) if after shift end time
    if (break_in !== undefined && break_in != null && existing.holiday_id == null) {
      const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
      if (shiftInfo && shiftInfo.endMinutes != null) {
        const breakInMins = minutesFromMidnightInTimeZone(break_in);
        if (breakInMins != null && breakInMins > shiftInfo.endMinutes) {
          return res.status(400).json({
            error: `PM clock-in time is after shift end. Shift ends at ${minutesToTimeStr(shiftInfo.endMinutes)}.`,
          });
        }
      }
    }

    const updates = [];
    const values = [];
    let i = 1;
    if (time_in !== undefined) { updates.push(`time_in = $${i++}`); values.push(time_in); }
    if (break_out !== undefined) { updates.push(`break_out = $${i++}`); values.push(break_out); }
    if (break_in !== undefined) { updates.push(`break_in = $${i++}`); values.push(break_in); }
    if (time_out !== undefined) { updates.push(`time_out = $${i++}`); values.push(time_out); }

    const ti = time_in !== undefined ? time_in : existing.time_in;
    const bo = break_out !== undefined ? break_out : existing.break_out;
    const bi = break_in !== undefined ? break_in : existing.break_in;
    const to = time_out !== undefined ? time_out : existing.time_out;
    const anyTimeChanged = time_in !== undefined || break_out !== undefined || break_in !== undefined || time_out !== undefined;
    const computedTotal = computeTotalHours(ti, bo, bi, to);
    if (total_hours !== undefined) {
      updates.push(`total_hours = $${i++}::numeric`);
      const parsedTotal = total_hours === null || total_hours === '' ? null : parseFloat(total_hours);
      values.push(Number.isFinite(parsedTotal) ? parsedTotal : computedTotal);
    }
    else if (anyTimeChanged) {
      updates.push(`total_hours = $${i++}::numeric`);
      values.push(computedTotal);
    }

    let resolvedStatus = status;
    if (time_in !== undefined) {
      if (existing.holiday_id != null) {
        resolvedStatus = 'holiday';
      } else {
        resolvedStatus = await computeStatusFromShift(employeeId, dateStr, time_in);
      }
    }
    if (resolvedStatus !== undefined) { updates.push(`status = $${i++}`); values.push(resolvedStatus); }

    let resolvedPmStatus = undefined;
    if (break_in !== undefined && existing.holiday_id == null) {
      resolvedPmStatus = bi ? await computePmLateStatus(employeeId, dateStr, bi) : null;
    }
    if (resolvedPmStatus !== undefined) { updates.push(`pm_status = $${i++}`); values.push(resolvedPmStatus); }
    if (remarks !== undefined) { updates.push(`remarks = $${i++}`); values.push(remarks); }

    const finalStatus = resolvedStatus !== undefined ? resolvedStatus : existing.status;
    const isHolidayOrLeave = existing.holiday_id != null || finalStatus === 'holiday' || finalStatus === 'on_leave';
    const isPartialSuspension = isHolidayOrLeave && (existingCoverage === 'am_only' || existingCoverage === 'pm_only');
    if (anyTimeChanged && (!isHolidayOrLeave || isPartialSuspension)) {
      const bo = break_out !== undefined ? break_out : existing.break_out;
      const rawLate = await computeLateMinutes(employeeId, dateStr, ti, bi, finalStatus, existing.holiday_id, existingCoverage);
      const rawUnder = await computeUndertimeMinutes(
        employeeId,
        dateStr,
        to,
        bo,
        finalStatus,
        existing.holiday_id,
        existingCoverage,
        ti,
        bi
      );
      const adjusted = await applyAttendancePolicyPenalties(
        employeeId,
        dateStr,
        rawLate,
        rawUnder
      );
      updates.push(`late_minutes = $${i++}`);
      values.push(adjusted.lateMinutes);
      updates.push(`undertime_minutes = $${i++}`);
      values.push(adjusted.undertimeMinutes);
    }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE dtr_daily_summary SET ${updates.join(', ')} WHERE id = $${i} RETURNING id, employee_id, attendance_date::text AS attendance_date_iso, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, updated_at`,
      values
    );
    const r = result.rows[0];
    const recordDateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(existing.attendance_date);

    broadcastBiometricUpdate('dtr_refresh', {
      action: 'manual_updated',
      userId: String(r.employee_id),
      date: recordDateStr,
      userIds: [String(r.employee_id)],
      dates: [recordDateStr],
    });

    res.json({
      id: r.id,
      user_id: r.employee_id,
      record_date: recordDateStr,
      time_in: r.time_in,
      break_out: r.break_out,
      break_in: r.break_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      late_minutes: r.late_minutes != null ? parseInt(r.late_minutes, 10) : 0,
      undertime_minutes: r.undertime_minutes != null ? parseInt(r.undertime_minutes, 10) : 0,
      status: r.status,
      pm_status: r.pm_status,
      source: r.source || null,
      updated_at: r.updated_at,
    });
  } catch (err) {
    console.error('[dtr-daily-summary PUT]', err);
    res.status(500).json({ error: 'Failed to update DTR record' });
  }
});

// DELETE /api/dtr-daily-summary/:id - admin only
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const target = await client.query(
      `SELECT id, employee_id, attendance_date::text AS attendance_date_iso, source
       FROM dtr_daily_summary
       WHERE id = $1`,
      [req.params.id]
    );
    if (target.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Record not found' });
    }

    const row = target.rows[0];
    await client.query('DELETE FROM dtr_daily_summary WHERE id = $1', [req.params.id]);

    // Biometric rows are rebuilt from biometric_attendance_logs during processing.
    // Delete matching raw logs for the same employee/date so the summary row does not return.
    if (row.source === 'system' && row.employee_id && row.attendance_date_iso) {
      const dateStr = String(row.attendance_date_iso).slice(0, 10);
      await client.query(
        `DELETE FROM biometric_attendance_logs
         WHERE user_id = $1::uuid
           AND logged_at >= $2::date
           AND logged_at < ($2::date + INTERVAL '1 day')`,
        [row.employee_id, dateStr]
      );
    }

    await client.query('COMMIT');
    const deletedDateStr = row.attendance_date_iso
      ? String(row.attendance_date_iso).slice(0, 10)
      : null;
    broadcastBiometricUpdate('dtr_refresh', {
      action: 'manual_deleted',
      userId: String(row.employee_id),
      date: deletedDateStr,
      userIds: [String(row.employee_id)],
      dates: deletedDateStr ? [deletedDateStr] : [],
    });
    res.status(204).send();
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('[dtr-daily-summary DELETE]', err);
    res.status(500).json({ error: 'Failed to delete DTR record' });
  } finally {
    client.release();
  }
});

// POST /api/dtr-daily-summary/sync-holidays - admin only; set holiday_id and status='holiday' for existing rows whose attendance_date falls in a holiday range (non-recurring or recurring template)
router.post('/sync-holidays', protect, requireAdmin, async (req, res) => {
  try {
    const { start_date, end_date } = req.body;
    const start = start_date || new Date().toISOString().slice(0, 10);
    const end = end_date || start;
    const exact = await pool.query(
      `UPDATE dtr_daily_summary d
       SET holiday_id = h.id, status = 'holiday', source = 'adjusted', updated_at = now()
       FROM holidays h
       WHERE h.recurring = false
         AND (h.is_active IS NULL OR h.is_active = true)
         AND d.attendance_date >= h.date_from AND d.attendance_date <= h.date_to
         AND d.attendance_date >= $1::date AND d.attendance_date <= $2::date
       RETURNING d.id`,
      [start, end]
    );
    let updated = exact.rowCount;
    const recurringRows = await pool.query(
      `SELECT id, date_from, date_to FROM holidays
       WHERE recurring = true AND (is_active IS NULL OR is_active = true)`
    );
    for (const h of recurringRows.rows) {
      const dates = expandRecurringToWindow(
        holidayDateToStr(h.date_from),
        holidayDateToStr(h.date_to),
        start,
        end
      );
      if (dates.length === 0) continue;
      const rUp = await pool.query(
        `UPDATE dtr_daily_summary
         SET holiday_id = $1, status = 'holiday', source = 'adjusted', updated_at = now()
         WHERE attendance_date = ANY($2::date[])
           AND attendance_date >= $3::date AND attendance_date <= $4::date
           AND holiday_id IS NULL`,
        [h.id, dates, start, end]
      );
      updated += rUp.rowCount;
    }
    if (updated > 0) {
      broadcastBiometricUpdate('dtr_refresh', {
        action: 'holidays_synced',
        updated,
        dateFrom: start,
        dateTo: end,
      });
    }
    res.json({ updated });
  } catch (err) {
    console.error('[dtr-daily-summary sync-holidays POST]', err);
    res.status(500).json({ error: 'Failed to sync holidays to DTR summary' });
  }
});

/**
 * Apply an approved DTR correction to `dtr_daily_summary` (insert or update).
 * Merges requested times with any existing row; recomputes hours/late/undertime like manual entry.
 * @param {import('pg').PoolClient} client
 * @param {object} correctionRow - Row from `dtr_corrections` (snake_case columns)
 * @returns {Promise<{ error?: string }>}
 */
async function applyApprovedCorrectionToSummary(client, correctionRow) {
  const employeeId = correctionRow.employee_id;
  const dateStr = toIsoDateStr(correctionRow.attendance_date);
  if (!dateStr) return { error: 'Invalid attendance date' };

  const reqIn = correctionRow.requested_time_in;
  const reqOut = correctionRow.requested_time_out;
  const reqBi = correctionRow.requested_break_in;
  const reqBo = correctionRow.requested_break_out;

  const hasAnyRequested =
    reqIn != null || reqOut != null || reqBi != null || reqBo != null;
  if (!hasAnyRequested) {
    return { error: 'Correction must include at least one requested time' };
  }

  const existingRes = await client.query(
    `SELECT id, time_in, break_out, break_in, time_out, holiday_id, status, leave_request_id, remarks
     FROM dtr_daily_summary
     WHERE employee_id = $1::uuid AND attendance_date = $2::date`,
    [employeeId, dateStr]
  );
  const existing = existingRes.rows[0] || null;

  const ti = reqIn != null ? reqIn : existing?.time_in;
  const bo = reqBo != null ? reqBo : existing?.break_out;
  const bi = reqBi != null ? reqBi : existing?.break_in;
  const to = reqOut != null ? reqOut : existing?.time_out;

  const hasAnyTime = ti || bo || bi || to;
  if (!hasAnyTime) {
    return {
      error: 'No time values to apply after merging with the existing record',
    };
  }

  const holiday = await getHolidayByDate(dateStr);
  const coverage = holiday ? (holiday.coverage || 'whole_day') : null;
  const isAfternoonOnly = Boolean(bi) && !ti;
  const timeIn = isAfternoonOnly ? null : ti;

  let status;
  let pmStatus = null;
  if (holiday && (!coverage || coverage === 'whole_day')) {
    status = 'holiday';
  } else {
    status = isAfternoonOnly
      ? 'absent'
      : await computeStatusFromShift(employeeId, dateStr, timeIn);
    if (bi && !holiday) {
      pmStatus = await computePmLateStatus(employeeId, dateStr, bi);
    }
  }

  const holidayId = holiday ? holiday.id : null;

  const total = computeTotalHours(timeIn, bo, bi, to);
  let lateMinutes = 0;
  let undertimeMinutes = 0;
  if (
    (!holiday || coverage === 'am_only' || coverage === 'pm_only') &&
    status !== 'on_leave'
  ) {
    const rawLate = await computeLateMinutes(
      employeeId,
      dateStr,
      timeIn,
      bi,
      status,
      holidayId,
      coverage
    );
    const rawUnder = await computeUndertimeMinutes(
      employeeId,
      dateStr,
      to,
      bo,
      status,
      holidayId,
      coverage,
      timeIn,
      bi
    );
    const adjusted = await applyAttendancePolicyPenalties(
      employeeId,
      dateStr,
      rawLate,
      rawUnder
    );
    lateMinutes = adjusted.lateMinutes;
    undertimeMinutes = adjusted.undertimeMinutes;
  }

  const remarkLine = `[DTR correction ${correctionRow.id}] applied.`;
  const newRemarks = existing?.remarks
    ? `${String(existing.remarks).trim()}\n${remarkLine}`
    : remarkLine;

  if (existing) {
    await client.query(
      `UPDATE dtr_daily_summary SET
         time_in = $1::timestamptz,
         break_out = $2::timestamptz,
         break_in = $3::timestamptz,
         time_out = $4::timestamptz,
         total_hours = $5::numeric,
         late_minutes = $6,
         undertime_minutes = $7,
         status = $8,
         pm_status = $9,
         source = 'adjusted',
         holiday_id = $10::uuid,
         leave_request_id = NULL,
         remarks = $11,
         overtime_minutes = 0,
         updated_at = now()
       WHERE id = $12::uuid`,
      [
        timeIn,
        bo,
        bi,
        to,
        total,
        lateMinutes,
        undertimeMinutes,
        status,
        pmStatus,
        holidayId,
        newRemarks,
        existing.id,
      ]
    );
  } else {
    await client.query(
      `INSERT INTO dtr_daily_summary (
         employee_id, attendance_date, time_in, break_out, break_in, time_out,
         total_hours, late_minutes, undertime_minutes, overtime_minutes,
         status, pm_status, source, holiday_id, remarks
       ) VALUES (
         $1::uuid, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz,
         $7::numeric, $8, $9, 0,
         $10, $11, 'adjusted', $12::uuid, $13
       )`,
      [
        employeeId,
        dateStr,
        timeIn,
        bo,
        bi,
        to,
        total,
        lateMinutes,
        undertimeMinutes,
        status,
        pmStatus,
        holidayId,
        newRemarks,
      ]
    );
  }

  return {};
}

module.exports = router;
module.exports.applyApprovedCorrectionToSummary = applyApprovedCorrectionToSummary;
