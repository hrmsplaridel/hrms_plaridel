const { parseAssistantDateRange } = require('../../utils/dateRangeParser');

function toNumber(value) {
  if (value == null) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function toIso(value) {
  if (!value) return null;
  const dt = value instanceof Date ? value : new Date(value);
  return Number.isNaN(dt.getTime()) ? null : dt.toISOString();
}

function compactText(value, max = 360) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}...`;
}

async function loadEmployeeProfile(pool, userId) {
  const result = await pool.query(
    `SELECT id, full_name, role
     FROM users
     WHERE id = $1::uuid
     LIMIT 1`,
    [userId]
  );
  const row = result.rows[0];
  return row
    ? {
        id: row.id,
        full_name: row.full_name,
        role: row.role,
      }
    : null;
}

async function loadDtrRecords(pool, userId, dateRange) {
  const result = await pool.query(
    `SELECT d.id,
            d.attendance_date::text AS attendance_date,
            d.time_in,
            d.break_out,
            d.break_in,
            d.time_out,
            d.total_hours,
            d.late_minutes,
            d.undertime_minutes,
            d.overtime_minutes,
            d.status,
            d.pm_status,
            d.remarks,
            d.source,
            h.name AS holiday_name,
            h.holiday_type,
            lt.name AS leave_type
     FROM dtr_daily_summary d
     LEFT JOIN holidays h ON h.id = d.holiday_id
     LEFT JOIN leave_requests lr ON lr.id = d.leave_request_id
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE d.employee_id = $1::uuid
       AND d.attendance_date BETWEEN $2::date AND $3::date
     ORDER BY d.attendance_date DESC
     LIMIT 14`,
    [userId, dateRange.startDate, dateRange.endDate]
  );

  return result.rows.map((row) => ({
    id: row.id,
    attendance_date: row.attendance_date,
    time_in: toIso(row.time_in),
    break_out: toIso(row.break_out),
    break_in: toIso(row.break_in),
    time_out: toIso(row.time_out),
    total_hours: toNumber(row.total_hours),
    late_minutes: row.late_minutes ?? 0,
    undertime_minutes: row.undertime_minutes ?? 0,
    overtime_minutes: row.overtime_minutes ?? 0,
    status: row.status,
    pm_status: row.pm_status,
    remarks: compactText(row.remarks),
    source: row.source,
    holiday_name: row.holiday_name,
    holiday_type: row.holiday_type,
    leave_type: row.leave_type,
  }));
}

async function loadLeaveBalances(pool, userId) {
  const result = await pool.query(
    `SELECT leave_type,
            earned_days,
            used_days,
            pending_days,
            adjusted_days,
            as_of_date::text AS as_of_date,
            last_accrual_date::text AS last_accrual_date
     FROM leave_balances
     WHERE user_id = $1::uuid
     ORDER BY leave_type ASC`,
    [userId]
  );

  return result.rows.map((row) => {
    const earned = toNumber(row.earned_days) || 0;
    const used = toNumber(row.used_days) || 0;
    const pending = toNumber(row.pending_days) || 0;
    const adjusted = toNumber(row.adjusted_days) || 0;
    return {
      leave_type: row.leave_type,
      earned_days: earned,
      used_days: used,
      pending_days: pending,
      adjusted_days: adjusted,
      remaining_days: earned - used + adjusted,
      available_days: earned - used + adjusted - pending,
      as_of_date: row.as_of_date,
      last_accrual_date: row.last_accrual_date,
    };
  });
}

async function loadRecentLeaveRequests(pool, userId) {
  const result = await pool.query(
    `SELECT lr.id,
            lr.start_date::text AS start_date,
            lr.end_date::text AS end_date,
            COALESCE(lr.number_of_days, lr.total_days) AS days,
            lr.status,
            lr.reason,
            lr.reviewer_remarks,
            lr.reviewed_at,
            lr.approved_at,
            lr.created_at,
            lr.updated_at,
            lt.name AS leave_type
     FROM leave_requests lr
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE lr.user_id = $1::uuid OR lr.employee_id = $1::uuid
     ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
     LIMIT 8`,
    [userId]
  );

  return result.rows.map((row) => ({
    id: row.id,
    leave_type: row.leave_type,
    start_date: row.start_date,
    end_date: row.end_date,
    days: toNumber(row.days),
    status: row.status,
    reason: compactText(row.reason),
    reviewer_remarks: compactText(row.reviewer_remarks),
    reviewed_at: toIso(row.reviewed_at),
    approved_at: toIso(row.approved_at),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  }));
}

async function loadRecentLocatorSlips(pool, userId) {
  const result = await pool.query(
    `SELECT ls.id,
            ls.slip_date::text AS slip_date,
            ls.request_type,
            ls.office,
            ls.reason,
            ls.am_in,
            ls.am_out,
            ls.pm_in,
            ls.pm_out,
            ls.status,
            ls.dept_head_remarks,
            ls.hr_remarks,
            ls.dept_head_reviewed_at,
            ls.hr_reviewed_at,
            ls.created_at,
            ls.updated_at,
            lrt.label AS request_type_label,
            lrt.dtr_slot_label AS dtr_slot_label
     FROM locator_slips ls
     LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
     WHERE ls.employee_id = $1::uuid
     ORDER BY ls.updated_at DESC, ls.created_at DESC
     LIMIT 8`,
    [userId]
  );

  return result.rows.map((row) => ({
    id: row.id,
    slip_date: row.slip_date,
    request_type: row.request_type,
    request_type_label: row.request_type_label,
    dtr_slot_label: row.dtr_slot_label,
    office: compactText(row.office),
    reason: compactText(row.reason),
    coverage: {
      am_in: row.am_in,
      am_out: row.am_out,
      pm_in: row.pm_in,
      pm_out: row.pm_out,
    },
    status: row.status,
    dept_head_remarks: compactText(row.dept_head_remarks),
    hr_remarks: compactText(row.hr_remarks),
    dept_head_reviewed_at: toIso(row.dept_head_reviewed_at),
    hr_reviewed_at: toIso(row.hr_reviewed_at),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  }));
}

async function loadEmployeeAssistantContext(pool, { userId, message }) {
  const dateRange = parseAssistantDateRange(message);
  const [employee, dtrRecords, leaveBalances, leaveRequests, locatorSlips] =
    await Promise.all([
      loadEmployeeProfile(pool, userId),
      loadDtrRecords(pool, userId, dateRange),
      loadLeaveBalances(pool, userId),
      loadRecentLeaveRequests(pool, userId),
      loadRecentLocatorSlips(pool, userId),
    ]);

  return {
    scope: 'employee_self',
    date_range: dateRange,
    employee,
    dtr_records: dtrRecords,
    leave_balances: leaveBalances,
    recent_leave_requests: leaveRequests,
    recent_locator_slips: locatorSlips,
  };
}

module.exports = { loadEmployeeAssistantContext };
