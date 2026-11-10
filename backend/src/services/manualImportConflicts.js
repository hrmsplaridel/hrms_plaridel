'use strict';

const { loadHolidayOverlayMap } = require('./holidayOverlay');
const { localTimestampParts } = require('./dtrPunchDateValidation');
const { locatorCoverageSegments, mergeLocatorCoverages } = require('./locatorCoverage');

// Request-scoped cache only: confirmation must load current approvals again.
function createManualImportConflictChecker(client) {
  const days = new Map();
  const holidays = new Map();
  const timeZone = process.env.HRMS_TIMEZONE || 'Asia/Manila';
  async function loadDay(employeeId, date) {
    const key = `${employeeId}|${date}`;
    if (!days.has(key)) days.set(key, (async () => {
      if (!holidays.has(date)) holidays.set(date, loadHolidayOverlayMap(client, date, date));
      const holidayMap = await holidays.get(date);
      // A transaction uses one PostgreSQL connection: issue its reads sequentially.
      const leaves = await client.query(
        `SELECT lr.start_date::text AS sd, lr.end_date::text AS ed,
                lr.number_of_days, lr.total_days
         FROM leave_requests lr
         LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
         WHERE lr.employee_id = $1::uuid AND lr.status = 'approved'
           AND COALESCE(lt.affects_dtr_normally, true) = true
           AND (
             EXISTS (SELECT 1 FROM dtr_leave_coverage c
                     WHERE c.leave_request_id = lr.id AND c.attendance_date = $2::date)
             OR (NOT EXISTS (SELECT 1 FROM dtr_leave_coverage c WHERE c.leave_request_id = lr.id)
                 AND lr.start_date <= $2::date AND lr.end_date >= $2::date)
           )`, [employeeId, date]);
      const locators = await client.query(
        `SELECT am_in, am_out, pm_in, pm_out FROM locator_slips
         WHERE employee_id = $1::uuid AND slip_date = $2::date AND status = 'approved'`,
        [employeeId, date]);
      return [holidayMap, leaves, locators];
    })());
    return days.get(key);
  }

  return async ({ employeeId, date, loggedAt }) => {
    const [holidayMap, leaveResult, locatorResult] = await loadDay(employeeId, date);
    const holiday = holidayMap.get(date);
    const local = localTimestampParts(loggedAt, timeZone);
    if (!local) throw new Error('Could not determine the imported punch time.');
    // AM/PM holiday coverage describes civil-day sessions. Noon out belongs to AM;
    // later lunch-return punches belong to PM. A next-day overnight punch must not
    // be treated as a same-calendar-day half-day holiday punch.
    const coveredByHoliday = holiday && (holiday.coverage === 'whole_day' ||
      (local.date === date && ((holiday.coverage === 'am_only' && local.minutes <= 720) ||
        (holiday.coverage === 'pm_only' && local.minutes > 720))));
    if (coveredByHoliday) return { exclusion: { code: 'holiday',
      message: `Excluded: ${holiday.name || 'holiday'} covers this attendance session.` }, warnings: [] };

    const warnings = [];
    for (const leave of leaveResult.rows) {
      const amount = Number(leave.number_of_days ?? leave.total_days ?? 1);
      if (leave.sd === leave.ed && Number.isFinite(amount) && amount > 0 && amount < 1) {
        warnings.push({ code: 'partial_leave_review', message:
          'Approved partial-day leave exists without a recorded AM/PM session. Verify this punch against the signed leave before importing.' });
      } else {
        return { exclusion: { code: 'approved_leave',
          message: 'Excluded: approved full-day leave covers this attendance date.' }, warnings: [] };
      }
    }
    const segments = locatorCoverageSegments(mergeLocatorCoverages(locatorResult.rows));
    if (segments.length) warnings.push({ code: 'locator_review', message:
      `Approved locator coverage: ${segments.join(', ')}. Verify that this is an actual punch, not copied locator coverage.` });
    return { exclusion: null, warnings };
  };
}

module.exports = { createManualImportConflictChecker };
