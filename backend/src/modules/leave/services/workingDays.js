'use strict';
module.exports = function createLeaveComponent({
  expandNonRecurringToWindow,
  expandRecurringToWindow,
  isWeekday,
  isoWeekdayFromDateString,
  maxIsoDate,
  minIsoDate,
  normalizeWorkingDays,
  toIsoDateStr,
}) {
  async function holidayDateSetForRange(startStr, endStr, dbClient = null) {
    const holidayDates = new Set();
    if (!dbClient) return holidayDates;
    try {
      const nonRec = await dbClient.query(
        `SELECT date_from, date_to FROM holidays
       WHERE is_active = true
        AND recurring = false
         AND holiday_type IN ('regular', 'special', 'local')
         AND date_from <= $2::date AND date_to >= $1::date`,
        [startStr, endStr],
      );
      for (const row of nonRec.rows) {
        const df = String(row.date_from).split('T')[0].slice(0, 10);
        const dt = String(row.date_to).split('T')[0].slice(0, 10);
        for (const ds of expandNonRecurringToWindow(df, dt, startStr, endStr)) {
          holidayDates.add(ds);
        }
      }
      const rec = await dbClient.query(
        `SELECT date_from, date_to FROM holidays
       WHERE is_active = true
         AND recurring = true
         AND holiday_type IN ('regular', 'special', 'local')`,
      );
      for (const row of rec.rows) {
        const df = String(row.date_from).split('T')[0].slice(0, 10);
        const dt = String(row.date_to).split('T')[0].slice(0, 10);
        for (const ds of expandRecurringToWindow(df, dt, startStr, endStr)) {
          holidayDates.add(ds);
        }
      }
    } catch (_) {
      // Keep callers resilient; they can still count scheduled days without holidays.
    }
    return holidayDates;
  }

  /**
   * #12 Holiday-aware working day count (Mon–Fri, excluding public holidays).
   *
   * @param {string} startStr  YYYY-MM-DD
   * @param {string} endStr    YYYY-MM-DD
   * @param {import('pg').PoolClient|null} [dbClient]  optional DB client for holiday lookup.
   *        If null, falls back to simple Mon–Fri count (safe for contexts where a
   *        DB client is not available, e.g. validation before the transaction begins).
   * @returns {Promise<number|null>} count or null on invalid input
   */
  async function computeNumberOfDays(startStr, endStr, dbClient = null) {
    if (!startStr || !endStr) return null;
    const start = new Date(`${startStr}T12:00:00`);
    const end = new Date(`${endStr}T12:00:00`);
    if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
    if (end < start) return null;

    const holidayDates = await holidayDateSetForRange(startStr, endStr, dbClient);

    let count = 0;
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      if (!isWeekday(d)) continue;
      const ds = toIsoDateStr(d); // use the same shift-proof helper
      if (!holidayDates.has(ds)) count += 1;
    }
    return count;
  }

  async function computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr) {
    if (!client || !userId || !startStr || !endStr) {
      return {
        days: await computeNumberOfDays(startStr, endStr, client),
        countedDates: [],
        scheduleSource: 'fallback',
      };
    }
    const start = new Date(`${startStr}T12:00:00`);
    const end = new Date(`${endStr}T12:00:00`);
    if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) {
      return { days: null, countedDates: [], scheduleSource: 'invalid' };
    }

    const holidayDates = await holidayDateSetForRange(startStr, endStr, client);
    const q = await client.query(
      `SELECT
        to_char(gs::date, 'YYYY-MM-DD') AS attendance_date,
        COALESCE(s.working_days, ARRAY[1,2,3,4,5]::int[]) AS working_days,
        eso.is_working_day AS override_is_working_day,
        eff.assignment_id IS NOT NULL AS has_assignment,
        s.id IS NOT NULL AS has_shift
     FROM generate_series($2::date, $3::date, '1 day'::interval) AS gs
     LEFT JOIN LATERAL (
       SELECT a.id AS assignment_id, a.shift_id
       FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND a.effective_from <= gs::date
         AND (a.effective_to IS NULL OR a.effective_to >= gs::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     ) eff ON TRUE
     LEFT JOIN shifts s ON s.id = eff.shift_id
     LEFT JOIN employee_schedule_overrides eso
       ON eso.employee_id = $1::uuid
      AND eso.schedule_date = gs::date
     ORDER BY gs::date`,
      [userId, startStr, endStr],
    );

    const countedDates = [];
    let sawShift = false;
    let sawAssignmentWithoutShift = false;
    let sawNoAssignment = false;
    for (const row of q.rows) {
      const ds = row.attendance_date;
      const isoWeekday = isoWeekdayFromDateString(ds);
      if (isoWeekday == null) continue;
      if (row.has_shift) sawShift = true;
      else if (row.has_assignment) sawAssignmentWithoutShift = true;
      else sawNoAssignment = true;
      if (holidayDates.has(ds)) continue;
      const workingDays = normalizeWorkingDays(row.working_days);
      const isWorkingDay =
        typeof row.override_is_working_day === 'boolean'
          ? row.override_is_working_day
          : workingDays.includes(isoWeekday);
      if (isWorkingDay) countedDates.push(ds);
    }

    const scheduleSource = sawShift
      ? 'shift'
      : sawAssignmentWithoutShift
        ? 'assignment_fallback'
        : sawNoAssignment
          ? 'fallback'
          : 'none';
    return {
      days: countedDates.length,
      countedDates,
      scheduleSource,
      holidayDates: Array.from(holidayDates).sort(),
    };
  }

  /** Synchronous fallback (Mon–Fri only), used where async is not possible. */
  function computeNumberOfDaysSync(startStr, endStr) {
    if (!startStr || !endStr) return null;
    const start = new Date(`${startStr}T12:00:00`);
    const end = new Date(`${endStr}T12:00:00`);
    if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
    if (end < start) return null;
    let count = 0;
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      if (isWeekday(d)) count += 1;
    }
    return count;
  }

  async function workingDaysWithinYear(client, userId, startStr, endStr, year) {
    if (!startStr || !endStr) return 0;
    const from = maxIsoDate(startStr, `${year}-01-01`);
    const to = minIsoDate(endStr, `${year}-12-31`);
    if (!from || !to || to < from) return 0;
    const result = await computeEmployeeLeaveWorkingDays(client, userId, from, to);
    return result.days ?? 0;
  }
  return {
    holidayDateSetForRange,
    computeNumberOfDays,
    computeEmployeeLeaveWorkingDays,
    computeNumberOfDaysSync,
    workingDaysWithinYear,
  };
};
