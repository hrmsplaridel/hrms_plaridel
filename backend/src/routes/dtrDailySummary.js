const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

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
 * Returns 'am_only' | 'pm_only' | 'full_day' | null (no shift).
 * - pm_only: shift starts at or after noon (startMinutes >= 720)
 * - am_only: no break_end and shift ends by 1 PM
 * - full_day: otherwise (has both AM and PM periods)
 */
function getShiftType(shiftInfo) {
  if (!shiftInfo) return null;
  const { startMinutes, endMinutes, breakEndMinutes } = shiftInfo;
  if (startMinutes == null) return null;
  if (startMinutes >= NOON_MINUTES) return 'pm_only';
  if (breakEndMinutes == null && endMinutes != null && endMinutes <= ONE_PM_MINUTES) return 'am_only';
  return 'full_day';
}

/**
 * Get which logs are expected for the shift.
 * Returns { needsAm: boolean, needsPm: boolean }.
 * needsAm: expects time_in + break_out
 * needsPm: expects break_in + time_out
 */
function getShiftExpectedLogs(shiftInfo) {
  const type = getShiftType(shiftInfo);
  if (!type) return { needsAm: true, needsPm: true }; // fallback: require all
  if (type === 'pm_only') return { needsAm: false, needsPm: true };
  if (type === 'am_only') return { needsAm: true, needsPm: false };
  return { needsAm: true, needsPm: true };
}

/**
 * Get expected logs for a day considering holiday/suspension coverage.
 * holidayInfo: { holiday_type, coverage } or null.
 * - whole_day or regular/special/local: no logs required.
 * - am_only (work_suspension): only PM required.
 * - pm_only (work_suspension): only AM required.
 */
function getExpectedLogsForDay(shiftInfo, holidayInfo) {
  if (!holidayInfo || !holidayInfo.coverage) return getShiftExpectedLogs(shiftInfo);
  const cov = holidayInfo.coverage;
  if (cov === 'whole_day') return { needsAm: false, needsPm: false };
  if (cov === 'am_only') return { needsAm: false, needsPm: true };
  if (cov === 'pm_only') return { needsAm: true, needsPm: false };
  return getShiftExpectedLogs(shiftInfo);
}

/**
 * Get employee's assignment for a date (effective_from <= date <= effective_to, is_active).
 * Returns { startMinutes, endMinutes, graceMinutes, breakEndMinutes } or null if no assignment/shift.
 * breakEndMinutes: PM shift start (when late is checked for break_in). Null = no PM late check.
 * endMinutes: shift end time in minutes from midnight (for validating clock-in outside shift).
 */
async function getAssignmentShiftForDate(employeeId, dateStr) {
  const result = await pool.query(
    `SELECT a.override_start_time::text AS override_start_time,
            a.override_end_time::text AS override_end_time,
            a.override_break_end::text AS override_break_end,
            a.effective_from, a.effective_to,
            s.start_time::text AS shift_start,
            s.end_time::text AS shift_end,
            s.break_end::text AS shift_break_end,
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
  return { startMinutes, endMinutes, graceMinutes, breakEndMinutes };
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
async function computeUndertimeMinutes(employeeId, dateStr, timeOutIso, breakOutIso, status, holidayId, coverage) {
  if (status === 'on_leave') return 0;
  const isHolidayOrSuspension = status === 'holiday' || holidayId != null;
  if (isHolidayOrSuspension && (!coverage || coverage === 'whole_day')) return 0;
  const shiftInfo = await getAssignmentShiftForDate(employeeId, dateStr);
  if (!shiftInfo || shiftInfo.endMinutes == null) return 0;
  const type = getShiftType(shiftInfo);
  const evalAm = !isHolidayOrSuspension || coverage !== 'am_only';
  const evalPm = !isHolidayOrSuspension || coverage !== 'pm_only';
  let clockOutMins = null;
  if (evalAm && type === 'am_only' && breakOutIso) {
    clockOutMins = minutesFromMidnightInTimeZone(breakOutIso);
  } else if (evalPm && timeOutIso) {
    clockOutMins = minutesFromMidnightInTimeZone(timeOutIso);
  }
  if (clockOutMins == null) return 0;
  const endMinutes = shiftInfo.endMinutes;
  if (clockOutMins >= endMinutes) return 0;
  return endMinutes - clockOutMins;
}

/**
 * Compute attendance remark. Priority: 1) Holiday/Suspension 2) Leave 3) Absent 4) Incomplete 5) Late+Undertime 6) Late 7) Undertime 8) On Time.
 * holidayInfo: { name, holiday_type, coverage } or null.
 */
async function computeAttendanceRemark(record, shiftInfo, holidayId, leaveRequestId, holidayInfo) {
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
  const hasAnyLog = record.time_in || record.break_out || record.break_in || record.time_out;
  if (!hasAnyLog) return 'Absent';
  if (record.status === 'invalid') return 'Invalid Log';

  const expected = getExpectedLogsForDay(shiftInfo, holidayInfo);
  const hasAm = record.time_in != null && record.break_out != null;
  const hasPm = record.break_in != null && record.time_out != null;
  const missingRequired =
    (expected.needsAm && !hasAm) || (expected.needsPm && !hasPm);
  if (missingRequired) return 'Incomplete';

  const late = (record.late_minutes ?? 0) > 0;
  const under = (record.undertime_minutes ?? 0) > 0;
  if (late && under) return 'Late + Undertime';
  if (late) return 'Late';
  if (under) return 'Undertime';
  return 'On Time';
}

/** Get all active holiday dates in [startStr, endStr]. Returns array of { dateStr, id, name, holiday_type, coverage }. Tolerates missing coverage column. */
async function getHolidaysInRange(startStr, endStr) {
  if (!startStr || !endStr) return [];
  const hasCoverage = await _holidaysHasCoverageColumn();
  const exactCols = hasCoverage ? 'id, name, holiday_type, coverage, holiday_date::text AS date_str' : 'id, name, holiday_type, holiday_date::text AS date_str';
  const exact = await pool.query(
    `SELECT ${exactCols} FROM holidays
     WHERE (is_active IS NULL OR is_active = true)
       AND holiday_date >= $1::date AND holiday_date <= $2::date`,
    [startStr, endStr]
  );
  const results = exact.rows.map((r) => ({
    dateStr: r.date_str?.slice(0, 10) || String(r.date_str),
    id: r.id,
    name: r.name,
    holiday_type: r.holiday_type,
    coverage: r.coverage || 'whole_day',
  }));
  const recurCols = hasCoverage ? 'id, name, holiday_type, coverage, holiday_date' : 'id, name, holiday_type, holiday_date';
  const recurring = await pool.query(
    `SELECT ${recurCols},
            EXTRACT(YEAR FROM $1::date)::int AS start_year,
            EXTRACT(YEAR FROM $2::date)::int AS end_year
     FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)`,
    [startStr, endStr]
  );
  for (const r of recurring.rows) {
    const month = r.holiday_date ? new Date(r.holiday_date).getMonth() + 1 : 0;
    const day = r.holiday_date ? new Date(r.holiday_date).getDate() : 0;
    if (!month || !day) continue;
    const startYear = parseInt(r.start_year, 10) || new Date().getFullYear();
    const endYear = parseInt(r.end_year, 10) || new Date().getFullYear();
    for (let y = startYear; y <= endYear; y++) {
      const dateStr = `${y}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
      if (dateStr >= startStr && dateStr <= endStr) {
        if (!results.some((x) => x.dateStr === dateStr)) {
          results.push({
            dateStr,
            id: r.id,
            name: r.name,
            holiday_type: r.holiday_type,
            coverage: r.coverage || 'whole_day',
          });
        }
      }
    }
  }
  return results.sort((a, b) => a.dateStr.localeCompare(b.dateStr));
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
 * Get assignments+shift info for employees that overlap [startStr, endStr].
 * Returns Map employeeId -> array of { effective_from, effective_to, startMinutes, endMinutes, breakEndMinutes, graceMinutes, workingDays } sorted by effective_from desc.
 */
async function getAssignmentsForEmployeesInRange(employeeIds, startStr, endStr) {
  const map = new Map();
  if (!employeeIds || employeeIds.length === 0) return map;
  if (!startStr || !endStr) return map;
  const res = await pool.query(
    `SELECT a.employee_id,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to,
            COALESCE(a.override_start_time, s.start_time) AS start_time,
            COALESCE(a.override_end_time, s.end_time) AS end_time,
            COALESCE(a.override_break_end, s.break_end) AS break_end,
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

/** Get active holiday for a date, if any. Exact date match first, then recurring (same month/day). Returns { id, name, holiday_type, coverage } or null. Tolerates missing coverage column. */
async function getHolidayByDate(dateStr) {
  const hasCoverage = await _holidaysHasCoverageColumn();
  const cols = hasCoverage ? 'id, name, holiday_type, coverage' : 'id, name, holiday_type';
  const exact = await pool.query(
    `SELECT ${cols} FROM holidays WHERE holiday_date = $1::date AND (is_active IS NULL OR is_active = true) LIMIT 1`,
    [dateStr]
  );
  if (exact.rows[0]) {
    const r = exact.rows[0];
    return { ...r, coverage: r.coverage || 'whole_day' };
  }
  const recurring = await pool.query(
    `SELECT ${cols} FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)
       AND EXTRACT(MONTH FROM holiday_date) = EXTRACT(MONTH FROM $1::date)
       AND EXTRACT(DAY FROM holiday_date) = EXTRACT(DAY FROM $1::date)
     LIMIT 1`,
    [dateStr]
  );
  if (recurring.rows[0]) {
    const r = recurring.rows[0];
    return { ...r, coverage: r.coverage || 'whole_day' };
  }
  return null;
}

// GET /api/dtr-daily-summary - list for admin (filters: start_date, end_date, employee_id, department_id, limit)
router.get('/', protect, async (req, res) => {
  try {
    const { start_date, end_date, employee_id, department_id, limit = 500 } = req.query;
    const params = [];
    const conditions = [];
    let i = 1;
    if (start_date) {
      conditions.push(`d.attendance_date >= $${i++}`);
      params.push(start_date);
    }
    if (end_date) {
      conditions.push(`d.attendance_date <= $${i++}`);
      params.push(end_date);
    }
    if (employee_id) {
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
    const limitNum = Math.min(parseInt(limit, 10) || 500, 1000);
    params.push(limitNum);

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
              lt.description AS leave_type_name
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

    const rows = await Promise.all(rawRows.map(async (r) => {
      // Use the date-only text from SQL to avoid timezone shifting issues when JS receives Date objects.
      const dateStr = (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || toIsoDateStr(r.attendance_date);
      const shiftInfo = dateStr ? await getAssignmentShiftForDate(r.employee_id, dateStr) : null;
      const coverage = r.holiday_coverage || 'whole_day';
      const isPartialSuspension = r.status === 'holiday' && (coverage === 'am_only' || coverage === 'pm_only');
      let lateMinutes = r.late_minutes != null ? parseInt(r.late_minutes, 10) : 0;
      let undertimeMinutes = r.undertime_minutes != null ? parseInt(r.undertime_minutes, 10) : 0;
      if (dateStr && r.status !== 'on_leave' && (r.status !== 'holiday' || isPartialSuspension)) {
        if (lateMinutes === 0 && (r.time_in || r.break_in)) {
          lateMinutes = await computeLateMinutes(r.employee_id, dateStr, r.time_in, r.break_in, r.status, r.holiday_id, coverage);
        }
        if (undertimeMinutes === 0 && (r.time_out || r.break_out)) {
          undertimeMinutes = await computeUndertimeMinutes(r.employee_id, dateStr, r.time_out, r.break_out, r.status, r.holiday_id, coverage);
        }
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
      };
    }));

    // Inject synthetic holiday rows for dates with no record
    const startStr = start_date ? String(start_date).slice(0, 10) : null;
    const endStr = end_date ? String(end_date).slice(0, 10) : null;
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
      } else {
        const fromRows = [...new Set(rawRows.map((r) => r.employee_id).filter(Boolean))];
        if (fromRows.length > 0) {
          employeeIds = fromRows;
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
          const allEmps = await pool.query(
            'SELECT id, full_name FROM users WHERE is_active = true ORDER BY full_name'
          );
          employeeIds = allEmps.rows.map((r) => r.id).filter(Boolean);
          for (const r of allEmps.rows) {
            if (r.id && r.full_name) userIdToName[r.id] = r.full_name;
          }
        }
      }

      const holidaysInRange = await getHolidaysInRange(startStr, endStr);
      const holidayByDate = new Map();
      for (const h of holidaysInRange) holidayByDate.set(h.dateStr, h);

      // 1) Inject synthetic holiday rows for dates with no record (existing behavior)
      if (holidaysInRange.length > 0) {
        for (const h of holidaysInRange) {
          const cov = h.coverage || 'whole_day';
          let remark = h.name || 'Holiday';
          if (cov === 'am_only') remark = `${remark} (AM)`;
          else if (cov === 'pm_only') remark = `${remark} (PM)`;
          for (const empId of employeeIds) {
            const key = `${empId}|${h.dateStr}`;
            if (existingKeys.has(key)) continue;
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
            });
          }
        }
      }

      // 2) Inject synthetic "Absent" rows for working days with no record, only after shift end / for past dates
      const todayStr = new Date().toISOString().slice(0, 10);
      const now = new Date();
      const nowMinutes = now.getHours() * 60 + now.getMinutes();

      const leaveKeys = await getApprovedLeaveKeysInRange(employeeIds, startStr, endStr);
      const assignmentsByEmployee = await getAssignmentsForEmployeesInRange(employeeIds, startStr, endStr);

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

          // Absent = full scheduled shift not worked; undertime = scheduled minutes for the day.
          const absentUndertime =
            shiftInfo.endMinutes != null && shiftInfo.startMinutes != null
              ? Math.max(0, shiftInfo.endMinutes - shiftInfo.startMinutes)
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
          });
        }
      }

      rows.sort((a, b) => {
        const dA = a.record_date;
        const dB = b.record_date;
        if (dA !== dB) return String(dB).localeCompare(String(dA));
        return (b.time_in || '').localeCompare(a.time_in || '');
      });
    }

    res.json(rows);
  } catch (err) {
    console.error('[dtr-daily-summary GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR summary' });
  }
});

// GET /api/dtr-daily-summary/summary - counts for dashboard (present today, late today)
router.get('/summary', protect, async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const present = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL`,
      [today]
    );
    const late = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL AND status = 'late'`,
      [today]
    );
    res.json({
      present_today: parseInt(present.rows[0]?.c ?? 0, 10),
      late_today: parseInt(late.rows[0]?.c ?? 0, 10),
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
    const today = new Date().toISOString().slice(0, 10);
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
    const today = new Date().toISOString().slice(0, 10);
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

/** Compute total_hours from 4 punch points: (break_out - time_in) + (time_out - break_in). Fallback to (time_out - time_in) if only 2 punches. Afternoon-only: (time_out - break_in). */
function computeTotalHours(timeIn, breakOut, breakIn, timeOut) {
  const parse = (x) => (x ? new Date(x).getTime() : null);
  const ti = parse(timeIn);
  const bo = parse(breakOut);
  const bi = parse(breakIn);
  const to = parse(timeOut);
  if (ti && bo && bi && to) {
    return ((bo - ti) + (to - bi)) / (1000 * 60 * 60);
  }
  if (ti && to) return (to - ti) / (1000 * 60 * 60);
  if (!ti && bi && to) return (to - bi) / (1000 * 60 * 60); // afternoon-only (AM absent)
  return 0;
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
        const breakInDate = new Date(break_in);
        const breakInMins = breakInDate.getHours() * 60 + breakInDate.getMinutes();
        if (breakInMins > shiftInfo.endMinutes) {
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
      lateMinutes = await computeLateMinutes(targetId, date, timeIn, break_in || null, status, holidayId, coverage);
      undertimeMinutes = await computeUndertimeMinutes(targetId, date, time_out || null, break_out || null, status, holidayId, coverage);
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
        const breakInDate = new Date(break_in);
        const breakInMins = breakInDate.getHours() * 60 + breakInDate.getMinutes();
        if (breakInMins > shiftInfo.endMinutes) {
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
    const computedTotal = total_hours === undefined ? computeTotalHours(ti, bo, bi, to) : null;
    if (total_hours !== undefined) { updates.push(`total_hours = $${i++}::numeric`); values.push(parseFloat(total_hours)); }
    else if (computedTotal !== null && (time_in !== undefined || break_out !== undefined || break_in !== undefined || time_out !== undefined)) {
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

    const anyTimeChanged = time_in !== undefined || break_out !== undefined || break_in !== undefined || time_out !== undefined;
    const finalStatus = resolvedStatus !== undefined ? resolvedStatus : existing.status;
    const isHolidayOrLeave = existing.holiday_id != null || finalStatus === 'holiday' || finalStatus === 'on_leave';
    const isPartialSuspension = isHolidayOrLeave && (existingCoverage === 'am_only' || existingCoverage === 'pm_only');
    if (anyTimeChanged && (!isHolidayOrLeave || isPartialSuspension)) {
      const bo = break_out !== undefined ? break_out : existing.break_out;
      const lateMin = await computeLateMinutes(employeeId, dateStr, ti, bi, finalStatus, existing.holiday_id, existingCoverage);
      const underMin = await computeUndertimeMinutes(employeeId, dateStr, to, bo, finalStatus, existing.holiday_id, existingCoverage);
      updates.push(`late_minutes = $${i++}`);
      values.push(lateMin);
      updates.push(`undertime_minutes = $${i++}`);
      values.push(underMin);
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
  try {
    const result = await pool.query('DELETE FROM dtr_daily_summary WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Record not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[dtr-daily-summary DELETE]', err);
    res.status(500).json({ error: 'Failed to delete DTR record' });
  }
});

// POST /api/dtr-daily-summary/sync-holidays - admin only; set holiday_id and status='holiday' for existing rows whose attendance_date is a holiday (exact or recurring)
router.post('/sync-holidays', protect, requireAdmin, async (req, res) => {
  try {
    const { start_date, end_date } = req.body;
    const start = start_date || new Date().toISOString().slice(0, 10);
    const end = end_date || start;
    const exact = await pool.query(
      `UPDATE dtr_daily_summary d
       SET holiday_id = h.id, status = 'holiday', source = 'adjusted', updated_at = now()
       FROM holidays h
       WHERE d.attendance_date = h.holiday_date
         AND (h.is_active IS NULL OR h.is_active = true)
         AND d.attendance_date >= $1::date AND d.attendance_date <= $2::date
       RETURNING d.id`,
      [start, end]
    );
    const recurring = await pool.query(
      `UPDATE dtr_daily_summary d
       SET holiday_id = h.id, status = 'holiday', source = 'adjusted', updated_at = now()
       FROM holidays h
       WHERE h.recurring = true AND (h.is_active IS NULL OR h.is_active = true)
         AND EXTRACT(MONTH FROM d.attendance_date) = EXTRACT(MONTH FROM h.holiday_date)
         AND EXTRACT(DAY FROM d.attendance_date) = EXTRACT(DAY FROM h.holiday_date)
         AND d.attendance_date >= $1::date AND d.attendance_date <= $2::date
         AND d.holiday_id IS NULL
       RETURNING d.id`,
      [start, end]
    );
    res.json({ updated: exact.rowCount + recurring.rowCount });
  } catch (err) {
    console.error('[dtr-daily-summary sync-holidays POST]', err);
    res.status(500).json({ error: 'Failed to sync holidays to DTR summary' });
  }
});

module.exports = router;
