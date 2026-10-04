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

module.exports = {
  DEFAULT_WORKING_DAYS,
  addIsoDays,
  dateOnly,
  defaultWorkingDay,
  isIsoDate,
  isoWeekday,
  loadScheduleOverrides,
  normalizedWorkingDays,
  resolvedWorkingDay,
  scheduleKey,
  weekDates,
};
