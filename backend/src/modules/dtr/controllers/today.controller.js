'use strict';
module.exports = function createDtrControllers({
  _holidaysHasCoverageColumn,
  computePmLateStatus,
  pool,
  resolveAttendanceHolidayOverlay,
  toIsoDateStr,
  todayInHrmsTimezone,
}) {
  return {
    getTodayRecord: async (req, res) => {
      try {
        const userId = req.user?.id;
        if (!userId) return res.status(401).json({ error: 'Not authenticated' });
        const today = todayInHrmsTimezone();
        const hasCoverage = await _holidaysHasCoverageColumn();
        const joinCols = hasCoverage
          ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
          : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
        const result = await pool.query(
          `WITH target AS (
         SELECT $1::uuid AS employee_id, $2::date AS attendance_date
       )
       SELECT d.id,
              target.employee_id,
              target.attendance_date,
              target.attendance_date::text AS attendance_date_iso,
              d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours,
              CASE WHEN dlc.id IS NOT NULL OR lr.status = 'approved' THEN 'on_leave' ELSE d.status END AS status,
              d.pm_status, d.remarks,
              CASE WHEN dlc.id IS NOT NULL OR lr.status = 'approved' THEN 'adjusted' ELSE d.source END AS source,
              d.holiday_id, d.created_at, d.updated_at,
              dlc.id AS leave_coverage_id,
              COALESCE(dlc.leave_request_id, CASE WHEN lr.status = 'approved' THEN d.leave_request_id END) AS leave_request_id,
              (dlc.id IS NOT NULL OR lr.status = 'approved') AS is_leave_covered,
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name,
              u.full_name AS employee_name,
              ${joinCols}
       FROM target
       LEFT JOIN dtr_daily_summary d
         ON d.employee_id = target.employee_id AND d.attendance_date = target.attendance_date
       LEFT JOIN dtr_leave_coverage dlc
         ON dlc.employee_id = target.employee_id
        AND dlc.attendance_date = target.attendance_date
        AND EXISTS (
          SELECT 1 FROM leave_requests approved_request
          WHERE approved_request.id = dlc.leave_request_id
            AND approved_request.status = 'approved'
        )
       LEFT JOIN leave_requests lr ON lr.id = COALESCE(dlc.leave_request_id, d.leave_request_id)
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = target.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id IS NOT NULL OR dlc.id IS NOT NULL`,
          [userId, today]
        );
        const r = result.rows[0];
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
        res.json({
          id: r.id,
          user_id: r.employee_id,
          record_date: todayRecordDateStr,
          time_in: r.time_in,
          break_out: r.break_out,
          break_in: r.break_in,
          time_out: r.time_out,
          total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
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
        });
      } catch (err) {
        console.error('[dtr-daily-summary/today GET]', err);
        res.status(500).json({ error: 'Failed to fetch today record' });
      }
    },
  };
};
