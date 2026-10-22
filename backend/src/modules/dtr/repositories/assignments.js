'use strict';
module.exports = function createDtrComponent({ pool, resolvedWorkingDay, timeToMinutes }) {
  /**
   * Get the employee assignment effective on a date, including closed history.
   * Returns { startMinutes, endMinutes, graceMinutes, breakEndMinutes } or null if no assignment/shift.
   * breakEndMinutes: configured PM shift start; legacy full-day null values use 1:00 PM.
   * endMinutes: shift end time in minutes from midnight (for validating clock-in outside shift).
   */
  async function getAssignmentShiftForDate(employeeId, dateStr) {
    const result = await pool.query(
      `SELECT saved.shift_snapshot, a.department_id, a.shift_id,
            (SELECT o.is_working_day FROM employee_schedule_overrides o
             WHERE o.employee_id = $1::uuid AND o.schedule_date = $2::date) AS scheduled_working_day,
            a.override_start_time::text AS override_start_time,
            a.override_end_time::text AS override_end_time,
            a.override_break_end::text AS override_break_end,
            a.effective_from, a.effective_to,
            s.start_time::text AS shift_start,
            s.end_time::text AS shift_end,
             s.break_end::text AS shift_break_end,
             s.punch_mode, s.break_start::text AS shift_break_start, s.capture_window_minutes,
             s.working_days,
             s.grace_period_minutes
     FROM (SELECT (SELECT d.shift_snapshot FROM dtr_daily_summary d
                   WHERE d.employee_id = $1::uuid AND d.attendance_date = $2::date)
                  AS shift_snapshot) saved
     LEFT JOIN LATERAL (
       SELECT a.* FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     ) a ON true
     LEFT JOIN shifts s ON a.shift_id = s.id`,
      [employeeId, dateStr]
    );
    const row = result.rows[0];
    if (!row) return null;
    if (row.shift_snapshot) return row.shift_snapshot;
    const startTimeStr = row.override_start_time || row.shift_start;
    if (!startTimeStr) return null;
    const startMinutes = timeToMinutes(startTimeStr);
    if (startMinutes == null) return null;
    const endTimeStr = row.override_end_time || row.shift_end;
    const endMinutes = endTimeStr ? timeToMinutes(endTimeStr) : null;
    const graceMinutes =
      row.grace_period_minutes != null ? parseInt(row.grace_period_minutes, 10) : 0;
    const breakEndStr = row.override_break_end || row.shift_break_end;
    const breakEndMinutes = breakEndStr ? timeToMinutes(breakEndStr) : null;
    return {
      departmentId: row.department_id || null,
      shiftId: row.shift_id || null,
      startMinutes,
      endMinutes,
      graceMinutes,
      breakEndMinutes,
      punchMode: row.punch_mode || 'auto',
      isWorkingDay:
        typeof row.scheduled_working_day === 'boolean'
          ? row.scheduled_working_day
          : resolvedWorkingDay({ employeeId, dateStr, workingDays: row.working_days }),
      breakStartMinutes: timeToMinutes(row.shift_break_start),
      captureWindowMinutes: Number(row.capture_window_minutes ?? 120),
      workingDays: Array.isArray(row.working_days)
        ? row.working_days.map((value) => parseInt(value, 10)).filter(Number.isFinite)
        : [],
    };
  }

  /**
   * Get assignments+shift info for employees that overlap [startStr, endStr].
   * Returns Map employeeId -> date-effective assignment and shift details sorted by effective_from desc.
   */
  async function getAssignmentsForEmployeesInRange(employeeIds, startStr, endStr) {
    const map = new Map();
    if (!employeeIds || employeeIds.length === 0) return map;
    if (!startStr || !endStr) return map;
    const res = await pool.query(
      `SELECT a.id,
            a.employee_id,
            a.department_id,
            d.name AS department_name,
            p.name AS position_name,
            a.shift_id,
            s.name AS shift_name,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to,
            COALESCE(a.override_start_time, s.start_time)::text AS start_time,
            COALESCE(a.override_end_time, s.end_time)::text AS end_time,
            COALESCE(a.override_break_end, s.break_end)::text AS break_end,
            s.punch_mode, s.break_start::text AS shift_break_start, s.capture_window_minutes,
            s.grace_period_minutes,
            s.working_days
     FROM assignments a
     LEFT JOIN shifts s ON s.id = a.shift_id
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN positions p ON p.id = a.position_id
     WHERE a.employee_id = ANY($1::uuid[])
       AND a.effective_from <= $3::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.employee_id, a.effective_from DESC, a.created_at DESC, a.id DESC`,
      [employeeIds, startStr, endStr]
    );
    for (const r of res.rows) {
      const empId = r.employee_id;
      const startTimeStr = r.start_time;
      const shift = {
        id: r.id,
        departmentId: r.department_id || null,
        departmentName: r.department_name || null,
        positionName: r.position_name || null,
        shiftId: r.shift_id || null,
        shiftName: r.shift_name || null,
        effective_from: String(r.effective_from).slice(0, 10),
        effective_to: r.effective_to ? String(r.effective_to).slice(0, 10) : null,
        startTime: r.start_time || null,
        endTime: r.end_time || null,
        breakEnd: r.break_end || null,
        startMinutes: startTimeStr ? timeToMinutes(startTimeStr) : null,
        endMinutes: r.end_time ? timeToMinutes(r.end_time) : null,
        breakEndMinutes: r.break_end ? timeToMinutes(r.break_end) : null,
        punchMode: r.punch_mode || 'auto',
        breakStartMinutes: timeToMinutes(r.shift_break_start),
        captureWindowMinutes: Number(r.capture_window_minutes ?? 120),
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
  return { getAssignmentShiftForDate, getAssignmentsForEmployeesInRange };
};
