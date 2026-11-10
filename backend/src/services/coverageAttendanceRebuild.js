'use strict';
const { isValidIsoDate } = require('./dtrPunchDateValidation');

// Called after coverage removal commits. The normal biometric processor still
// enforces current approvals, manual-record protection and attendance reset blocks.
async function rebuildCoverageAttendance({ employeeId = null, dateFrom, dateTo, recurring = false }, deps = {}) {
  if (!isValidIsoDate(dateFrom) || !isValidIsoDate(dateTo) || dateFrom > dateTo) {
    throw new Error('Invalid attendance rebuild date range');
  }
  const pool = deps.pool || require('../config/db').pool;
  const rebuild = deps.process || require('./biometricProcessing').processBiometricLogsToSummary;
  const zone = process.env.HRMS_TIMEZONE || 'Asia/Manila';
  const result = await pool.query(
    `SELECT DISTINCT user_id, (logged_at AT TIME ZONE $4)::date::text AS punch_date
     FROM biometric_attendance_logs
     WHERE ($1::uuid IS NULL OR user_id = $1::uuid)
       AND ${recurring ? `(
         (to_char($2::date, 'MM-DD') <= to_char($3::date, 'MM-DD')
          AND to_char(logged_at AT TIME ZONE $4, 'MM-DD') BETWEEN to_char($2::date, 'MM-DD') AND to_char($3::date, 'MM-DD'))
         OR (to_char($2::date, 'MM-DD') > to_char($3::date, 'MM-DD')
          AND (to_char(logged_at AT TIME ZONE $4, 'MM-DD') >= to_char($2::date, 'MM-DD')
            OR to_char(logged_at AT TIME ZONE $4, 'MM-DD') <= to_char($3::date, 'MM-DD')))
       )` : `(logged_at AT TIME ZONE $4)::date BETWEEN $2::date - 1 AND $3::date + 1`}
     ORDER BY user_id, punch_date`, [employeeId, dateFrom, dateTo, zone]);
  let rebuilt = 0;
  if (recurring) {
    for (const row of result.rows) {
      await rebuild([row.user_id], row.punch_date, row.punch_date);
      rebuilt++;
    }
  } else {
    const ids = [...new Set(result.rows.map((row) => row.user_id).filter(Boolean))];
    if (ids.length) { await rebuild(ids, dateFrom, dateTo); rebuilt = ids.length; }
  }
  return { rebuilt };
}

module.exports = { rebuildCoverageAttendance };
