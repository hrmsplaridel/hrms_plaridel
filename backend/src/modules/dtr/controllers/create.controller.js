'use strict';
module.exports = function createDtrControllers({
  HRMS_TIMEZONE,
  applyAttendancePolicyPenalties,
  broadcastBiometricUpdate,
  computeLateMinutes,
  computePmLateStatus,
  computeStatusFromShift,
  computeTotalHours,
  computeUndertimeMinutes,
  getApprovedLeaveCoverageForDate,
  getAssignmentShiftForDate,
  getHolidayByDate,
  inclusiveIsoDateRangeDays,
  minutesFromMidnightInTimeZone,
  minutesToTimeStr,
  pool,
  todayInHrmsTimezone,
  validateDtrPunchDates,
}) {
  return {
    createRecord: async (req, res) => {
      try {
        const {
          employee_id,
          attendance_date,
          time_in,
          break_out,
          break_in,
          time_out,
          total_hours,
          reason,
        } = req.body;
        const userId = req.user?.id;
        const targetId = employee_id || userId;
        if (!targetId) return res.status(401).json({ error: 'Not authenticated' });

        const normalizePunch = (value) => {
          if (value == null) return null;
          const normalized = String(value).trim();
          return normalized || null;
        };
        const timeIn = normalizePunch(time_in);
        const breakOut = normalizePunch(break_out);
        const breakIn = normalizePunch(break_in);
        const timeOut = normalizePunch(time_out);
        if (![timeIn, breakOut, breakIn, timeOut].some(Boolean)) {
          return res.status(400).json({
            error: 'At least one attendance punch is required for a manual entry.',
          });
        }

        const date = String(attendance_date || '').trim();
        if (inclusiveIsoDateRangeDays(date, date) !== 1) {
          return res
            .status(400)
            .json({ error: 'attendance_date must be a valid YYYY-MM-DD date.' });
        }
        const todayDate = todayInHrmsTimezone();
        if (date > todayDate) {
          return res.status(400).json({
            error: `Future attendance is not allowed. The latest permitted date is ${todayDate}.`,
          });
        }
        const shiftInfo = await getAssignmentShiftForDate(targetId, date);
        const punchDateValidation = validateDtrPunchDates({
          attendanceDate: date,
          punches: { time_in: timeIn, break_out: breakOut, break_in: breakIn, time_out: timeOut },
          shiftInfo,
          todayDate,
          timeZone: HRMS_TIMEZONE,
        });
        if (!punchDateValidation.valid) {
          return res.status(400).json({ error: punchDateValidation.error });
        }
        const leaveCoverage = await getApprovedLeaveCoverageForDate(targetId, date);
        if (leaveCoverage) {
          return res.status(409).json({
            error:
              'An approved leave already covers this date. Revoke or return the leave approval before adding attendance.',
            leave_request_id: leaveCoverage.leave_request_id,
          });
        }
        const isAfternoonOnly = Boolean(breakIn) && !timeIn;
        const holiday = await getHolidayByDate(date);
        const coverage = holiday ? holiday.coverage || 'whole_day' : null;

        // Reject PM In (break_in) if after shift end time (skip for holidays)
        if (breakIn && !holiday) {
          if (shiftInfo && shiftInfo.endMinutes != null) {
            const breakInMins = minutesFromMidnightInTimeZone(breakIn);
            const isOvernightShift =
              shiftInfo.startMinutes != null && shiftInfo.endMinutes <= shiftInfo.startMinutes;
            if (!isOvernightShift && breakInMins != null && breakInMins > shiftInfo.endMinutes) {
              return res.status(400).json({
                error: `PM clock-in time is after shift end. Shift ends at ${minutesToTimeStr(shiftInfo.endMinutes)}. Clock-in not allowed.`,
              });
            }
          }
        }
        let status = holiday
          ? 'holiday'
          : isAfternoonOnly
            ? 'absent'
            : await computeStatusFromShift(targetId, date, timeIn);
        let pmStatus = null;
        if (breakIn && !holiday) {
          pmStatus = await computePmLateStatus(targetId, date, breakIn);
        }
        const holidayId = holiday ? holiday.id : null;
        const total =
          total_hours != null
            ? parseFloat(total_hours)
            : computeTotalHours(timeIn, breakOut, breakIn, timeOut, shiftInfo);
        let lateMinutes = 0;
        let undertimeMinutes = 0;
        if (
          (!holiday || coverage === 'am_only' || coverage === 'pm_only') &&
          status !== 'on_leave'
        ) {
          const rawLate = await computeLateMinutes(
            targetId,
            date,
            timeIn,
            breakIn,
            status,
            holidayId,
            coverage
          );
          const rawUnder = await computeUndertimeMinutes(
            targetId,
            date,
            timeOut,
            breakOut,
            status,
            holidayId,
            coverage,
            timeIn || null,
            breakIn
          );
          const adjusted = await applyAttendancePolicyPenalties(targetId, date, rawLate, rawUnder);
          lateMinutes = adjusted.lateMinutes;
          undertimeMinutes = adjusted.undertimeMinutes;
        }

        const sourceValue = status === 'holiday' || holidayId ? 'adjusted' : 'manual';

        const result = await pool.query(
          `INSERT INTO dtr_daily_summary (employee_id, attendance_date, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, holiday_id, shift_snapshot)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz, $7::numeric, $8, $9, $10, $11, $12, $13, $14::jsonb)
       RETURNING id, employee_id, attendance_date::text AS attendance_date_iso, time_in, break_out, break_in, time_out, total_hours, late_minutes, undertime_minutes, status, pm_status, source, created_at`,
          [
            targetId,
            date,
            timeIn,
            breakOut,
            breakIn,
            timeOut,
            total,
            lateMinutes,
            undertimeMinutes,
            status,
            pmStatus,
            sourceValue,
            holidayId,
            JSON.stringify(shiftInfo),
          ]
        );
        const r = result.rows[0];
        const recordDateStr =
          (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) || date;

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
        if (err.code === '23505')
          return res
            .status(409)
            .json({ error: 'Record already exists for this employee and date' });
        console.error('[dtr-daily-summary POST]', err);
        res.status(500).json({ error: 'Failed to create DTR record' });
      }
    },
  };
};
