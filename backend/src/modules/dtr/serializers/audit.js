'use strict';
module.exports = function createDtrComponent({ toIsoDateStr }) {
  function dtrAuditSnapshot(row) {
    if (!row) return null;
    const numberOrNull = (value) => {
      if (value == null || value === '') return null;
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : null;
    };
    return {
      id: row.id || null,
      employee_id: row.employee_id || null,
      attendance_date:
        (row.attendance_date_iso && String(row.attendance_date_iso).slice(0, 10)) ||
        toIsoDateStr(row.attendance_date),
      assignment_id: row.assignment_id || null,
      shift_id: row.shift_id || null,
      attendance_policy_id: row.attendance_policy_id || null,
      holiday_id: row.holiday_id || null,
      leave_request_id: row.leave_request_id || null,
      time_in: row.time_in || null,
      break_out: row.break_out || null,
      break_in: row.break_in || null,
      time_out: row.time_out || null,
      total_hours: numberOrNull(row.total_hours),
      late_minutes: numberOrNull(row.late_minutes),
      undertime_minutes: numberOrNull(row.undertime_minutes),
      overtime_minutes: numberOrNull(row.overtime_minutes),
      status: row.status || null,
      pm_status: row.pm_status || null,
      source: row.source || null,
      remarks: row.remarks || null,
      updated_at: row.updated_at || null,
    };
  }
  return { dtrAuditSnapshot };
};
