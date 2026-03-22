const { pool } = require('../config/db');

const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
const NOON_MINUTES = 12 * 60;
const ONE_PM_MINUTES = 13 * 60;

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
  const result = await pool.query(
    `SELECT a.override_start_time::text AS override_start_time,
            a.override_end_time::text AS override_end_time,
            a.override_break_end::text AS override_break_end,
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

async function getHolidayForDate(dateStr) {
  const exact = await pool.query(
    `SELECT id, COALESCE(coverage, 'whole_day') AS coverage
     FROM holidays WHERE holiday_date = $1::date AND (is_active IS NULL OR is_active = true) LIMIT 1`,
    [dateStr]
  );
  if (exact.rows[0]) return exact.rows[0];
  const recurring = await pool.query(
    `SELECT id, COALESCE(coverage, 'whole_day') AS coverage FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)
       AND EXTRACT(MONTH FROM holiday_date) = EXTRACT(MONTH FROM $1::date)
       AND EXTRACT(DAY FROM holiday_date) = EXTRACT(DAY FROM $1::date)
     LIMIT 1`,
    [dateStr]
  );
  return recurring.rows[0] || null;
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

function getShiftType(shiftInfo) {
  if (!shiftInfo) return null;
  const { startMinutes, endMinutes, breakEndMinutes } = shiftInfo;
  if (startMinutes == null) return null;
  if (startMinutes >= NOON_MINUTES) return 'pm_only';
  if (breakEndMinutes == null && endMinutes != null && endMinutes <= ONE_PM_MINUTES) return 'am_only';
  return 'full_day';
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
 * @returns {{ timeIn, breakOut, breakIn, timeOut, status, totalHours, punchCount }}
 */
function interpretPunchesForDay(punches, shiftType) {
  const n = punches.length;
  if (n === 0) return null;

  let timeIn = null;
  let breakOut = null;
  let breakIn = null;
  let timeOut = null;
  let status;

  if (shiftType === 'pm_only') {
    if (n >= 1) breakIn = punches[0];
    if (n >= 2) timeOut = punches[1];
    status = n >= 2 ? 'present' : 'incomplete';
  } else if (shiftType === 'am_only') {
    if (n >= 1) timeIn = punches[0];
    if (n >= 2) breakOut = punches[1];
    status = n >= 2 ? 'present' : 'incomplete';
  } else {
    if (n === 1) {
      timeIn = punches[0];
      status = 'incomplete';
    } else if (n === 2) {
      timeIn = punches[0];
      timeOut = punches[1];
      status = 'present';
    } else if (n === 3) {
      timeIn = punches[0];
      breakOut = punches[1];
      timeOut = punches[2];
      status = 'incomplete';
    } else {
      timeIn = punches[0];
      breakOut = punches[1];
      breakIn = punches[2];
      timeOut = punches[n - 1];
      status = 'present';
    }
  }

  const totalHours = computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType);

  return {
    timeIn,
    breakOut,
    breakIn,
    timeOut,
    status,
    totalHours,
    punchCount: n,
  };
}

/**
 * total_hours: (time_out - time_in) minus (break_in - break_out) when both breaks exist; else full span.
 * For pm_only: time_in may be null → use (time_out - break_in).
 * If time_out is null → 0. Rounded to 2 decimals, minimum 0.
 */
function computeTotalHours(timeIn, timeOut, breakOut, breakIn, shiftType) {
  if (!timeOut) return 0;
  let workMs;
  if (shiftType === 'pm_only' && !timeIn && breakIn) {
    workMs = new Date(timeOut) - new Date(breakIn);
  } else if (!timeIn) {
    return 0;
  } else {
    workMs = new Date(timeOut) - new Date(timeIn);
    if (breakOut && breakIn) {
      const breakMs = new Date(breakIn) - new Date(breakOut);
      if (breakMs > 0) workMs -= breakMs;
    }
  }
  const hours = workMs / (1000 * 60 * 60);
  return Math.max(0, Math.round(hours * 100) / 100);
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
  let skipped = 0;

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

    let shiftInfo = null;
    try {
      shiftInfo = await getAssignmentShiftForDate(user_id, attendanceDateStr);
    } catch (err) {
      console.warn('[biometricProcessing] Shift lookup failed (using full_day):', { user_id, attendance_date: attendanceDateStr });
    }
    const shiftType = getShiftType(shiftInfo);

    console.log('[biometricProcessing] Processing day:', {
      user_id,
      attendance_date: attendanceDateStr,
      punch_count: punchList.length,
      shiftType: shiftType || 'full_day',
      punches: punchList.map((p) => (p instanceof Date ? p.toISOString() : String(p))),
    });

    const interpreted = interpretPunchesForDay(punchList, shiftType);
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
      lateMinutes = await computeLateMinutes(user_id, attendanceDateStr, timeIn, breakIn, effectiveStatus, holidayId, coverage);
      undertimeMinutes = await computeUndertimeMinutes(user_id, attendanceDateStr, timeOut, breakOut, effectiveStatus, holidayId, coverage);
    }

    let existing;
    try {
      existing = await pool.query(
        `SELECT id, source FROM dtr_daily_summary
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

  console.log('[biometricProcessing] Done:', { inserted, updated, skipped });
  return { inserted, updated };
}

module.exports = {
  processBiometricLogsToSummary,
  interpretPunchesForDay,
  computeTotalHours,
};
