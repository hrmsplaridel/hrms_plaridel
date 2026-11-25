const DEFAULT_WORKING_DAYS = Object.freeze([1, 2, 3, 4, 5]);

function dateOnly(value) {
  return value == null ? null : String(value).slice(0, 10);
}

function isIsoDate(value) {
  const raw = String(value || '').trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return false;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return date.getUTCFullYear() === Number(match[1]) &&
    date.getUTCMonth() === Number(match[2]) - 1 &&
    date.getUTCDate() === Number(match[3]);
}

function isoWeekday(dateStr) {
  if (!isIsoDate(dateStr)) return null;
  const day = new Date(`${dateStr}T00:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

function addIsoDays(dateStr, amount) {
  const date = new Date(`${dateStr}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}

function weekDates(weekStart) {
  if (!isIsoDate(weekStart) || isoWeekday(weekStart) !== 1) return null;
  return Array.from({ length: 7 }, (_, index) => addIsoDays(weekStart, index));
}

function normalizedWorkingDays(value) {
  if (!Array.isArray(value)) return [...DEFAULT_WORKING_DAYS];
  const values = [...new Set(value.map(Number).filter((day) => Number.isInteger(day) && day >= 1 && day <= 7))];
  return values.length > 0 ? values.sort((a, b) => a - b) : [...DEFAULT_WORKING_DAYS];
}

function scheduleKey(employeeId, dateStr) {
  return `${employeeId}|${dateStr}`;
}

function defaultWorkingDay(workingDays, dateStr) {
  const weekday = isoWeekday(dateStr);
  return weekday != null && normalizedWorkingDays(workingDays).includes(weekday);
}

function resolvedWorkingDay({ employeeId, dateStr, workingDays, overrides }) {
  const override = overrides?.get(scheduleKey(employeeId, dateStr));
  return typeof override === 'boolean'
    ? override
    : defaultWorkingDay(workingDays, dateStr);
}

async function loadScheduleOverrides(db, employeeIds, startDate, endDate) {
  const result = new Map();
  if (!db || !Array.isArray(employeeIds) || employeeIds.length === 0) return result;
  const query = await db.query(
    `SELECT employee_id, schedule_date::text AS schedule_date, is_working_day
     FROM employee_schedule_overrides
     WHERE employee_id = ANY($1::uuid[])
       AND schedule_date BETWEEN $2::date AND $3::date`,
    [employeeIds, startDate, endDate]
  );
  for (const row of query.rows) {
    result.set(
      scheduleKey(String(row.employee_id), dateOnly(row.schedule_date)),
      row.is_working_day === true
    );
  }
  return result;
}

// Duty roster: a per-date shift stored on employee_schedule_overrides.shift_id.
// Queries select these columns from the roster shift aliased as `rs`.
const ROSTER_SHIFT_COLUMNS = `rs.id AS roster_shift_id,
            rs.name AS roster_shift_name,
            rs.start_time::text AS roster_start_time,
            rs.end_time::text AS roster_end_time,
            rs.break_start::text AS roster_break_start,
            rs.break_end::text AS roster_break_end,
            rs.punch_mode AS roster_punch_mode,
            rs.grace_period_minutes AS roster_grace_period_minutes,
            rs.capture_window_minutes AS roster_capture_window_minutes,
            rs.flexi_latest_start::text AS roster_flexi_latest_start`;

function clockMinutes(value) {
  const match = /^(\d{1,2}):(\d{2})/.exec(String(value || ''));
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

function rosterShiftFromRow(row) {
  if (!row?.roster_shift_id) return null;
  return {
    shiftId: String(row.roster_shift_id),
    shiftName: row.roster_shift_name || null,
    startTime: row.roster_start_time || null,
    endTime: row.roster_end_time || null,
    breakEnd: row.roster_break_end || null,
    startMinutes: clockMinutes(row.roster_start_time),
    endMinutes: clockMinutes(row.roster_end_time),
    breakStartMinutes: clockMinutes(row.roster_break_start),
    breakEndMinutes: clockMinutes(row.roster_break_end),
    punchMode: row.roster_punch_mode || 'auto',
    graceMinutes: Number(row.roster_grace_period_minutes || 0),
    captureWindowMinutes: Number(row.roster_capture_window_minutes ?? 120),
    flexiLatestStartMinutes: clockMinutes(row.roster_flexi_latest_start),
  };
}

/**
 * A rostered day uses the roster shift's schedule in place of the assignment's
 * shift (and its time overrides), keeping the assignment context (department,
 * working-day pattern, effective dates).
 */
function applyRosterShift(shiftInfo, roster) {
  if (!roster) return shiftInfo;
  return {
    ...(shiftInfo || {}),
    ...roster,
    rosterShiftId: roster.shiftId,
    isWorkingDay: true,
  };
}

async function loadRosterShifts(db, employeeIds, startDate, endDate) {
  const result = new Map();
  if (!db || !Array.isArray(employeeIds) || employeeIds.length === 0) return result;
  const query = await db.query(
    `SELECT eso.employee_id, eso.schedule_date::text AS schedule_date,
            ${ROSTER_SHIFT_COLUMNS}
     FROM employee_schedule_overrides eso
     JOIN shifts rs ON rs.id = eso.shift_id
     WHERE eso.employee_id = ANY($1::uuid[])
       AND eso.shift_id IS NOT NULL
       AND eso.schedule_date BETWEEN $2::date AND $3::date`,
    [employeeIds, startDate, endDate]
  );
  for (const row of query.rows) {
    result.set(
      scheduleKey(String(row.employee_id), dateOnly(row.schedule_date)),
      rosterShiftFromRow(row)
    );
  }
  return result;
}

module.exports = {
  DEFAULT_WORKING_DAYS,
  ROSTER_SHIFT_COLUMNS,
  addIsoDays,
  applyRosterShift,
  dateOnly,
  defaultWorkingDay,
  isIsoDate,
  isoWeekday,
  loadRosterShifts,
  loadScheduleOverrides,
  normalizedWorkingDays,
  resolvedWorkingDay,
  rosterShiftFromRow,
  scheduleKey,
  weekDates,
};
