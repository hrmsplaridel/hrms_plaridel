const { pool } = require('../config/db');
const { dateInRecurringRange } = require('./holidayRangeUtils');
const { broadcastBiometricUpdate } = require('../websockets/biometricStream');
const {
  ensureShiftPunchModeColumn,
  getShiftType: resolveShiftType,
  interpretPunchesForShift,
  computeTotalHours: computeShiftTotalHours,
} = require('./shiftAttendance');

const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
const NOON_MINUTES = 12 * 60;
const ONE_PM_MINUTES = 13 * 60;
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

function timeToMinutes(timeStr) {
  if (!timeStr) return null;
  const s = String(timeStr).trim();
  const m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/);
  if (!m) return null;
  const h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  if (!Number.isFinite(h) || !Number.isFinite(min)) return null;
  return Math.min(24 * 60 - 1, Math.max(0, h * 60 + min));
}

async function getAssignmentShiftForDate(employeeId, dateStr) {
  await ensureShiftPunchModeColumn(pool);
  const result = await pool.query(
    `SELECT a.override_start_time::text AS override_start_time,
            a.override_end_time::text AS override_end_time,
            a.override_break_end::text AS override_break_end,
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
 * Approved leave that blocks biometric for this calendar day.
 * Single-day leave with fewer than 1 day (e.g. half-day) does not block — employee may still punch the other session.
 * Multi-day approved leave blocks each covered date.
 */
async function employeeHasBlockingApprovedLeave(employeeId, dateStr) {
  if (!employeeId || !dateStr || !/^\d{4}-\d{2}-\d{2}$/.test(String(dateStr))) return false;
  const res = await pool.query(
    `SELECT start_date::text AS sd, end_date::text AS ed,
            number_of_days, total_days
     FROM leave_requests
     WHERE employee_id = $1::uuid
       AND status = 'approved'
       AND start_date <= $2::date
       AND end_date >= $2::date`,
    [employeeId, dateStr]
  );
  for (const row of res.rows) {
    const sd = String(row.sd).slice(0, 10);
    const ed = String(row.ed).slice(0, 10);
    const singleDay = sd === ed;
    let days =
      row.number_of_days != null
        ? parseFloat(String(row.number_of_days), 10)
        : row.total_days != null
          ? parseFloat(String(row.total_days), 10)
          : null;
    if (singleDay) {
      if (days == null || Number.isNaN(days)) days = 1;
      if (days < 1) continue;
      return true;
    }
    return true;
  }
  return false;
}

/**
 * Gate biometric storage/processing: shift required; whole-day holidays block; approved full-day (or multi-day) leave blocks.
 * Partial-day holidays (am_only/pm_only) do not block — late/undertime logic still applies.
 * @returns {{ allowed: boolean, reason: null|'no_schedule'|'holiday'|'leave', shiftInfo: object|null }}
 */
async function evaluateBiometricDayGate(employeeId, dateStr) {
  if (!employeeId || !dateStr || !/^\d{4}-\d{2}-\d{2}$/.test(String(dateStr))) {
    return { allowed: false, reason: 'no_schedule', shiftInfo: null };
  }
  let shiftInfo = null;
  try {
    shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  } catch (err) {
    console.warn('[evaluateBiometricDayGate] Shift lookup failed:', { employeeId, dateStr, err });
  }
  if (!shiftInfo) {
    return { allowed: false, reason: 'no_schedule', shiftInfo: null };
  }
  let holidayRow = null;
  try {
    holidayRow = await getHolidayForDate(dateStr);
  } catch (err) {
    console.warn('[evaluateBiometricDayGate] Holiday lookup failed:', { dateStr, err });
  }
  const coverage = holidayRow ? holidayRow.coverage || 'whole_day' : null;
  if (holidayRow && coverage === 'whole_day') {
    return { allowed: false, reason: 'holiday', shiftInfo };
  }
  if (await employeeHasBlockingApprovedLeave(employeeId, dateStr)) {
    return { allowed: false, reason: 'leave', shiftInfo };
  }
  return { allowed: true, reason: null, shiftInfo };
}

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

function isPunchAfterShiftEnd(punchAt, shiftInfo, timeZone = HRMS_TIMEZONE) {
  if (!punchAt || !shiftInfo || shiftInfo.endMinutes == null) return false;
  const startMinutes = shiftInfo.startMinutes;
  const endMinutes = shiftInfo.endMinutes;
  if (
    startMinutes != null &&
    endMinutes <= startMinutes
  ) {
    // Overnight shifts need a different cross-date rule; do not reject them here.
    return false;
  }
  const punchMinutes = minutesFromMidnightInTimeZone(punchAt, timeZone);
  if (punchMinutes == null) return false;
  return punchMinutes > endMinutes;
}

function isFirstPunchAfterShiftEnd(punchList, shiftInfo, timeZone = HRMS_TIMEZONE) {
  return (
    Array.isArray(punchList) &&
    punchList.length > 0 &&
    isPunchAfterShiftEnd(punchList[0], shiftInfo, timeZone)
  );
}

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

async function getHolidayForDate(dateStr) {
  const exact = await pool.query(
    `SELECT id, COALESCE(coverage, 'whole_day') AS coverage
     FROM holidays
     WHERE (is_active IS NULL OR is_active = true) AND recurring = false
       AND date_from <= $1::date AND date_to >= $1::date
     ORDER BY date_from
     LIMIT 1`,
    [dateStr]
  );
  if (exact.rows[0]) return exact.rows[0];
  const recurring = await pool.query(
    `SELECT id, COALESCE(coverage, 'whole_day') AS coverage, date_from, date_to FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)`
  );
  for (const r of recurring.rows) {
    if (dateInRecurringRange(dateStr, holidayDateToStr(r.date_from), holidayDateToStr(r.date_to))) {
      return { id: r.id, coverage: r.coverage };
    }
  }
  return null;
}

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
    if (localMins != null) {
      const cutoff = startMinutes + graceMinutes;
      if (localMins > cutoff) total += localMins - cutoff;
    }
  }
  const pmStartMinutes = breakEndMinutes ?? startMinutes;
  if (evalPm && breakInIso && (type === 'pm_only' || pmStartMinutes != null)) {
    const localMins = minutesFromMidnightInTimeZone(breakInIso);
    if (localMins != null) {
      const cutoff = pmStartMinutes + graceMinutes;
      if (localMins > cutoff) total += localMins - cutoff;
    }
  }
  return total;
}

async function computeUndertimeMinutes(employeeId, dateStr, timeOutIso, breakOutIso, status, holidayId, coverage, timeInIso, breakInIso) {
  if (status === 'on_leave') return 0;
  const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
  if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo || shiftInfo.endMinutes == null) return 0;
  const type = getShiftType(shiftInfo);
  const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
  const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
  const todayStr = new Date().toISOString().slice(0, 10);
  const now = new Date();
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  let amUndertimePenalty = 0;
  if (type === 'full_day' && evalAm && shiftInfo.startMinutes != null) {
    const hasAmLogs = timeInIso != null && breakOutIso != null;
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

function getShiftType(shiftInfo) {
  return resolveShiftType(shiftInfo);
}

/** Normalize date to YYYY-MM-DD string. Avoid toISOString() for DATEs - it uses UTC and can shift calendar date. */
function toDateStr(val) {
  if (val == null) return null;
  if (typeof val === 'string' && /^\d{4}-\d{2}-\d{2}/.test(val)) return val.slice(0, 10);
  const d = val instanceof Date ? val : new Date(val);
  if (isNaN(d.getTime())) return null;
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** Manila offset: UTC+8 in ms. */
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

/** Get calendar date in Asia/Manila for a timestamp. Returns YYYY-MM-DD. Explicit UTC+8 math to avoid locale quirks. */
function getManilaDateStr(val) {
  if (val == null) return null;
  const d = val instanceof Date ? val : new Date(val);
  if (isNaN(d.getTime())) return null;
  const manilaMs = d.getTime() + MANILA_OFFSET_MS;
  const m = new Date(manilaMs);
  const y = m.getUTCFullYear();
  const mo = String(m.getUTCMonth() + 1).padStart(2, '0');
  const day = String(m.getUTCDate()).padStart(2, '0');
  return `${y}-${mo}-${day}`;
}

/**
 * Interpret ordered same-day biometric punches into DTR fields.
 * Mapping depends on shift type (from assignment):
 * - pm_only: 1st = break_in (PM In), 2nd = time_out
 * - am_only: 1st = time_in, 2nd = break_out
 * - full_day / null: 1=time_in, 2=break_out, 3=break_in, 4+=time_out
 *
 * @param {Array<Date|string>} punches - ascending order, same calendar day (Manila)
 * @param {string|null} shiftType - 'pm_only' | 'am_only' | 'full_day' | null
 * @param {{ breakEndMinutes?: number|null }|null} shiftInfo - assignment shift info for thresholding
 * @returns {{ timeIn, breakOut, breakIn, timeOut, status, totalHours, punchCount, shiftType }}
 */
function interpretPunchesForDay(punches, shiftType, shiftInfo = null) {
  return interpretPunchesForShift(
    punches,
    { ...(shiftInfo || {}), punchMode: shiftType || shiftInfo?.punchMode || 'auto' },
    HRMS_TIMEZONE
  );
}

/**
 * total_hours: full-day uses (time_out - time_in) minus lunch when both break points exist.
 * For am_only: use (break_out - time_in). For pm_only: use (time_out - break_in).
 * Missing required end punch returns 0. Rounded to 2 decimals, minimum 0.
 */
function computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType) {
  return computeShiftTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType);
}

/**
 * Process biometric_attendance_logs into dtr_daily_summary for the given scope.
 * Groups by user_id + attendance_date (Asia/Manila), sorts punches, maps to time_in / break_out / break_in / time_out.
 * Does NOT overwrite rows where source IN ('manual', 'adjusted').
 *
 * @param {string[]} userIds - UUIDs of users to process
 * @param {string} dateFrom - YYYY-MM-DD inclusive
 * @param {string} dateTo - YYYY-MM-DD inclusive
 * @returns {{ inserted: number, updated: number }}
 */
async function processBiometricLogsToSummary(userIds, dateFrom, dateTo) {
  if (!userIds || userIds.length === 0 || !dateFrom || !dateTo) {
    console.log('[biometricProcessing] Skipped: no userIds or date range');
    return { inserted: 0, updated: 0 };
  }

  const userIdArr = Array.isArray(userIds) ? userIds : [...userIds];
  const tz = HRMS_TIMEZONE;

  console.log('[biometricProcessing] Processing', {
    userIdCount: userIdArr.length,
    dateFrom,
    dateTo,
    timezone: tz,
  });

  let grouped;
  try {
    grouped = await pool.query(
      `WITH labeled AS (
         SELECT user_id,
                logged_at,
                ((logged_at AT TIME ZONE $4)::date)::text AS punch_date
         FROM biometric_attendance_logs
         WHERE user_id = ANY($1::uuid[])
           AND (logged_at AT TIME ZONE $4)::date >= $2::date
           AND (logged_at AT TIME ZONE $4)::date <= $3::date
       )
       SELECT user_id,
              punch_date AS attendance_date,
              array_agg(logged_at ORDER BY logged_at ASC) AS punches
       FROM labeled
       GROUP BY user_id, punch_date`,
      [userIdArr, dateFrom, dateTo, tz]
    );
  } catch (err) {
    console.error('[biometricProcessing] Grouped query failed:', err);
    throw err;
  }

  const rowCount = grouped.rows.length;
  console.log('[biometricProcessing] Grouped rows:', rowCount);

  let inserted = 0;
  let updated = 0;
  let removed = 0;
  let skipped = 0;
  const affected = [];

  for (const row of grouped.rows) {
    const { user_id, attendance_date, punches } = row;
    const attendanceDateStr = typeof attendance_date === 'string' ? attendance_date.slice(0, 10) : toDateStr(attendance_date);
    if (!attendanceDateStr || !/^\d{4}-\d{2}-\d{2}$/.test(attendanceDateStr)) {
      console.warn('[biometricProcessing] Skipping row with invalid date:', { user_id, attendance_date });
      skipped++;
      continue;
    }

    const rawPunches = Array.isArray(punches) ? punches : [];
    const punchList = rawPunches.filter((p) => getManilaDateStr(p) === attendanceDateStr);
    if (punchList.length === 0) {
      console.warn('[biometricProcessing] No punches match attendance_date after filter:', {
        user_id,
        attendance_date: attendanceDateStr,
        rawCount: rawPunches.length,
      });
      skipped++;
      continue;
    }
    if (punchList.length !== rawPunches.length) {
      console.warn('[biometricProcessing] Filtered out cross-date punches:', {
        user_id,
        attendance_date: attendanceDateStr,
        before: rawPunches.length,
        after: punchList.length,
      });
    }

    const gate = await evaluateBiometricDayGate(user_id, attendanceDateStr);
    if (!gate.allowed) {
      console.warn('[biometricProcessing] SKIP: biometric not allowed for day', {
        user_id,
        attendance_date: attendanceDateStr,
        reason: gate.reason,
      });
      try {
        const delRes = await pool.query(
          `DELETE FROM dtr_daily_summary
           WHERE employee_id = $1::uuid AND attendance_date = $2::date AND source = 'system'
           RETURNING id`,
          [user_id, attendanceDateStr]
        );
        if (delRes.rowCount > 0) {
          removed += delRes.rowCount;
          affected.push({
            action: 'biometric_removed',
            userId: String(user_id),
            date: attendanceDateStr,
          });
          console.log('[biometricProcessing] Removed system DTR row (policy gate)', {
            user_id,
            attendance_date: attendanceDateStr,
            reason: gate.reason,
            removed: delRes.rowCount,
          });
        }
      } catch (err) {
        console.error('[biometricProcessing] DELETE system DTR after policy skip failed:', err);
      }
      skipped++;
      continue;
    }
    const shiftInfo = gate.shiftInfo;
    const shiftType = getShiftType(shiftInfo);

    if (isFirstPunchAfterShiftEnd(punchList, shiftInfo, HRMS_TIMEZONE)) {
      console.warn('[biometricProcessing] SKIP: first punch after shift end', {
        user_id,
        attendance_date: attendanceDateStr,
        punch: punchList[0] instanceof Date ? punchList[0].toISOString() : String(punchList[0]),
        shift_end_minutes: shiftInfo.endMinutes,
      });
      try {
        const delRes = await pool.query(
          `DELETE FROM dtr_daily_summary
           WHERE employee_id = $1::uuid AND attendance_date = $2::date AND source = 'system'
           RETURNING id`,
          [user_id, attendanceDateStr]
        );
        if (delRes.rowCount > 0) {
          removed += delRes.rowCount;
          affected.push({
            action: 'biometric_removed',
            userId: String(user_id),
            date: attendanceDateStr,
          });
        }
      } catch (err) {
        console.error('[biometricProcessing] DELETE system DTR after shift-end skip failed:', err);
      }
      skipped++;
      continue;
    }

    console.log('[biometricProcessing] Processing day:', {
      user_id,
      attendance_date: attendanceDateStr,
      punch_count: punchList.length,
      shiftType: shiftType || 'full_day',
      punches: punchList.map((p) => (p instanceof Date ? p.toISOString() : String(p))),
    });

    const interpreted = interpretPunchesForShift(
      punchList,
      shiftInfo,
      HRMS_TIMEZONE
    );
    if (!interpreted) {
      skipped++;
      continue;
    }

    const {
      timeIn,
      breakOut,
      breakIn,
      timeOut,
      status,
      totalHours,
      punchCount,
    } = interpreted;

    const firstRecord = timeIn || breakIn;
    const firstRecordManilaDate = getManilaDateStr(firstRecord);
    if (!firstRecord || firstRecordManilaDate !== attendanceDateStr) {
      console.error('[biometricProcessing] REJECT: first record Manila date does not match attendance_date', {
        user_id,
        attendance_date: attendanceDateStr,
        first_record_manila_date: firstRecordManilaDate,
        first_record: firstRecord ? (firstRecord instanceof Date ? firstRecord.toISOString() : String(firstRecord)) : null,
      });
      skipped++;
      continue;
    }
    if (timeOut && getManilaDateStr(timeOut) !== attendanceDateStr) {
      console.error('[biometricProcessing] REJECT: time_out Manila date does not match attendance_date', {
        user_id,
        attendance_date: attendanceDateStr,
        time_out_manila_date: getManilaDateStr(timeOut),
      });
      skipped++;
      continue;
    }

    let holidayInfo = null;
    try {
      holidayInfo = await getHolidayForDate(attendanceDateStr);
    } catch (err) {
      console.warn('[biometricProcessing] Holiday lookup failed (computing late/undertime):', { attendance_date: attendanceDateStr });
    }
    const holidayId = holidayInfo?.id || null;
    const coverage = holidayInfo?.coverage || null;
    const effectiveStatus = holidayId ? 'holiday' : status;
    let lateMinutes = 0;
    let undertimeMinutes = 0;
    if (effectiveStatus !== 'on_leave') {
      const rawLate = await computeLateMinutes(
        user_id,
        attendanceDateStr,
        timeIn,
        breakIn,
        effectiveStatus,
        holidayId,
        coverage
      );
      const rawUnder = await computeUndertimeMinutes(
        user_id,
        attendanceDateStr,
        timeOut,
        breakOut,
        effectiveStatus,
        holidayId,
        coverage,
        timeIn,
        breakIn
      );
      const adjusted = await applyAttendancePolicyPenalties(
        user_id,
        attendanceDateStr,
        rawLate,
        rawUnder
      );
      lateMinutes = adjusted.lateMinutes;
      undertimeMinutes = adjusted.undertimeMinutes;
    }

    let existing;
    try {
      existing = await pool.query(
        `SELECT id, source, time_in, break_in, time_out
         FROM dtr_daily_summary
         WHERE employee_id = $1::uuid AND attendance_date = $2::date`,
        [user_id, attendanceDateStr]
      );
    } catch (err) {
      console.error('[biometricProcessing] Existing lookup failed:', { user_id, attendanceDateStr, err });
      throw err;
    }

    if (existing.rows.length === 0) {
      try {
        await pool.query(
          `INSERT INTO dtr_daily_summary
             (employee_id, attendance_date, time_in, break_out, break_in, time_out, status, source,
              late_minutes, undertime_minutes, overtime_minutes, total_hours)
           VALUES ($1::uuid, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz, $7, 'system', $8, $9, 0, $10)`,
          [
            user_id,
            attendanceDateStr,
            timeIn,
            breakOut,
            breakIn,
            timeOut,
            status,
            lateMinutes,
            undertimeMinutes,
            totalHours,
          ]
        );
        inserted++;
        affected.push({
          action: 'biometric_inserted',
          userId: String(user_id),
          date: attendanceDateStr,
        });
        console.log('[biometricProcessing] INSERT', {
          employee_id: user_id,
          attendance_date: attendanceDateStr,
          punches: punchCount,
        });
      } catch (err) {
        console.error('[biometricProcessing] INSERT failed:', { user_id, attendanceDateStr, err });
        throw err;
      }
    } else if (existing.rows[0].source === 'system') {
      const existingRow = existing.rows[0];
      const isCompletedSummary =
        existingRow.time_out != null &&
        (existingRow.time_in != null || existingRow.break_in != null);
      if (isCompletedSummary) {
        skipped++;
        console.log('[biometricProcessing] SKIP (completed system summary locked)', {
          employee_id: user_id,
          attendance_date: attendanceDateStr,
          punches: punchCount,
        });
        continue;
      }
      try {
        await pool.query(
          `UPDATE dtr_daily_summary SET
             time_in = $3::timestamptz,
             break_out = $4::timestamptz,
             break_in = $5::timestamptz,
             time_out = $6::timestamptz,
             status = $7,
             total_hours = $8,
             late_minutes = $9,
             undertime_minutes = $10,
             overtime_minutes = 0,
             updated_at = now()
           WHERE employee_id = $1::uuid AND attendance_date = $2::date`,
          [
            user_id,
            attendanceDateStr,
            timeIn,
            breakOut,
            breakIn,
            timeOut,
            status,
            totalHours,
            lateMinutes,
            undertimeMinutes,
          ]
        );
        updated++;
        affected.push({
          action: 'biometric_updated',
          userId: String(user_id),
          date: attendanceDateStr,
        });
        console.log('[biometricProcessing] UPDATE', {
          employee_id: user_id,
          attendance_date: attendanceDateStr,
          punches: punchCount,
        });
      } catch (err) {
        console.error('[biometricProcessing] UPDATE failed:', { user_id, attendanceDateStr, err });
        throw err;
      }
    } else {
      skipped++;
      console.log('[biometricProcessing] SKIP (manual/adjusted)', {
        employee_id: user_id,
        attendance_date: attendanceDateStr,
        source: existing.rows[0].source,
      });
    }
  }

  console.log('[biometricProcessing] Done:', { inserted, updated, removed, skipped });
  
  if (affected.length > 0) {
    const userIds = [...new Set(affected.map((item) => item.userId).filter(Boolean))];
    const dates = [...new Set(affected.map((item) => item.date).filter(Boolean))];
    broadcastBiometricUpdate('dtr_refresh', {
      action: 'biometric_processed',
      inserted,
      updated,
      removed,
      skipped,
      userIds,
      dates,
      dateFrom,
      dateTo,
      affected,
    });
  }

  return { inserted, updated };
}

module.exports = {
  processBiometricLogsToSummary,
  interpretPunchesForDay,
  computeTotalHours,
  evaluateBiometricDayGate,
  isPunchAfterShiftEnd,
  isFirstPunchAfterShiftEnd,
  minutesFromMidnightInTimeZone,
  getManilaDateStr,
};
