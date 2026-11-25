'use strict';
const { projectAttendanceCoverage } = require('../../../services/attendanceCoverageProjection');
module.exports = function createDtrControllers({
  _holidaysHasCoverageColumn,
  annotateLocatorReportRows,
  computePmLateStatus,
  computeTotalHoursFromRecord,
  getAssignmentShiftForDate,
  getApprovedLocatorByDateInRange,
  getAttendancePolicyForEmployeeDate,
  loadHolidayOverlayMap,
  pool,
  resolveAttendanceHolidayOverlay,
  toIsoDateStr,
  todayInHrmsTimezone,
}) {
  const { findDayRecord } = require('../repositories/todayRecord')({
    _holidaysHasCoverageColumn,
    pool,
  });
  return {
    getTodayRecord: async (req, res) => {
      try {
        const userId = req.user?.id;
        if (!userId) return res.status(401).json({ error: 'Not authenticated' });
        const today = todayInHrmsTimezone();
        const holidays = await loadHolidayOverlayMap(pool, today, today);
        const activeHoliday = holidays.get(today) || null;
        const { row: savedRow, hasCoverage } = await findDayRecord(userId, today);
        const locatorByKey = await getApprovedLocatorByDateInRange([userId], today, today);
        let r = savedRow;
        if (!r && locatorByKey.has(`${userId}|${today}`)) {
          r = { employee_id: userId, attendance_date_iso: today, status: 'present' };
        }
        if (r && !hasCoverage) r.holiday_coverage = 'whole_day';
        if (!r && !activeHoliday) return res.json(null);
        if (!r) {
          return res.json({
            id: null,
            user_id: userId,
            record_date: today,
            time_in: null,
            break_out: null,
            break_in: null,
            time_out: null,
            total_hours: null,
            status: 'holiday',
            pm_status: null,
            remarks: null,
            source: 'adjusted',
            holiday_id: activeHoliday.id,
            holiday_name: activeHoliday.name,
            holiday_type: activeHoliday.holiday_type,
            coverage: activeHoliday.coverage || 'whole_day',
            leave_request_id: null,
            leave_coverage_id: null,
            is_leave_covered: false,
            leave_type_name: null,
            created_at: null,
            updated_at: null,
            employee_name: null,
          });
        }
        const todayRecordDateStr =
          (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || today;
        const shiftInfo = r.shift_snapshot || await getAssignmentShiftForDate(userId, todayRecordDateStr);
        const holidayState = resolveAttendanceHolidayOverlay(r, activeHoliday);
        const effectiveStatus = activeHoliday
          ? 'holiday'
          : r.is_leave_covered === true
            ? 'on_leave'
            : holidayState.status;
        let pmStatus = r.pm_status;
        if (pmStatus == null && r.break_in != null && activeHoliday == null) {
          const dateStr =
            (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
            toIsoDateStr(r.attendance_date);
          pmStatus = dateStr
            ? await computePmLateStatus(r.employee_id, dateStr, r.break_in)
            : 'present';
        }
        const payload = {
          id: r.id,
          user_id: r.employee_id,
          record_date: todayRecordDateStr,
          time_in: r.time_in,
          break_out: r.break_out,
          break_in: r.break_in,
          time_out: r.time_out,
          total_hours: r.total_hours != null && shiftInfo
            ? computeTotalHoursFromRecord({ ...r, attendance_date_iso: todayRecordDateStr }, shiftInfo)
            : r.total_hours != null ? parseFloat(r.total_hours) : null,
          status: effectiveStatus,
          pm_status: pmStatus,
          remarks: r.remarks,
          source: activeHoliday ? 'adjusted' : r.source || null,
          holiday_id: holidayState.holidayId,
          holiday_name: holidayState.holidayName,
          holiday_type: holidayState.holidayType,
          coverage: holidayState.coverage,
          leave_request_id: r.leave_request_id || null,
          leave_coverage_id: r.leave_coverage_id || null,
          is_leave_covered: r.is_leave_covered === true,
          leave_type_name: r.leave_type_name || null,
          created_at: r.created_at,
          updated_at: r.updated_at,
          employee_name: r.employee_name,
        };
        const projected = await projectAttendanceCoverage({ record: payload, date: todayRecordDateStr,
          shiftInfo, holidayInfo: activeHoliday,
          leave: r.is_leave_covered ? { number_of_days: r.number_of_days, total_days: r.total_days,
            start_date: r.leave_start_date, end_date: r.leave_end_date } : null,
          policy: activeHoliday?.coverage && activeHoliday.coverage !== 'whole_day'
            ? await getAttendancePolicyForEmployeeDate(userId, todayRecordDateStr) : null,
        });
        await annotateLocatorReportRows({ rows: [projected],
          savedShiftsByDate: new Map([[`${userId}|${todayRecordDateStr}`, shiftInfo]]),
          assignmentsByEmployee: new Map(), holidayByDate: holidays, locatorByKey,
        });
        res.json(projected);
      } catch (err) {
        console.error('[dtr-daily-summary/today GET]', err);
        res.status(500).json({ error: 'Failed to fetch today record' });
      }
    },
  };
};
