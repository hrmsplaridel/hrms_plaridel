const { parseAssistantDateRange } = require('../../utils/dateRangeParser');
const { buildGuidelinesForTypes } = require('./leaveFilingGuidelines');

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

function parseJsonArray(value) {
  if (Array.isArray(value)) return value;
  if (!value) return [];
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

async function loadEmployeeProfile(pool, userId) {
  const result = await pool.query(
    `SELECT id, full_name, role, sex, civil_status, date_of_birth::text AS date_of_birth
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
        sex: row.sex,
        civil_status: row.civil_status,
        date_of_birth: row.date_of_birth,
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
     LIMIT 70`,
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

async function loadDtrCalendarDays(pool, userId, dateRange) {
  const result = await pool.query(
    `SELECT day.day::date::text AS attendance_date,
            assignment.id AS assignment_id,
            shift.id AS shift_id,
            shift.name AS shift_name,
            COALESCE(assignment.override_start_time, shift.start_time)::text AS start_time,
            COALESCE(assignment.override_end_time, shift.end_time)::text AS end_time,
            COALESCE(assignment.override_break_end, shift.break_end)::text AS break_end,
            shift.punch_mode,
            shift.grace_period_minutes,
            shift.working_days,
            holiday.id AS holiday_id,
            holiday.name AS holiday_name,
            holiday.holiday_type,
            holiday.coverage AS holiday_coverage
     FROM generate_series($2::date, $3::date, interval '1 day') AS day(day)
     LEFT JOIN LATERAL (
       SELECT a.*
       FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND (a.is_active IS NULL OR a.is_active = true)
         AND a.effective_from <= day.day::date
         AND (a.effective_to IS NULL OR a.effective_to >= day.day::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     ) assignment ON true
     LEFT JOIN shifts shift ON shift.id = assignment.shift_id
     LEFT JOIN LATERAL (
       SELECT h.*
       FROM holidays h
       WHERE (h.is_active IS NULL OR h.is_active = true)
         AND day.day::date BETWEEN h.date_from AND h.date_to
       ORDER BY
         CASE h.coverage WHEN 'whole_day' THEN 0 ELSE 1 END,
         h.date_from DESC,
         h.created_at DESC
       LIMIT 1
     ) holiday ON true
     ORDER BY day.day ASC`,
    [userId, dateRange.startDate, dateRange.endDate]
  );

  return result.rows.map((row) => ({
    attendance_date: row.attendance_date,
    assignment_id: row.assignment_id,
    shift_id: row.shift_id,
    shift_name: row.shift_name,
    start_time: row.start_time,
    end_time: row.end_time,
    break_end: row.break_end,
    punch_mode: row.punch_mode,
    grace_period_minutes: row.grace_period_minutes ?? 0,
    working_days: Array.isArray(row.working_days) ? row.working_days.map(Number) : [],
    holiday_id: row.holiday_id,
    holiday_name: row.holiday_name,
    holiday_type: row.holiday_type,
    holiday_coverage: row.holiday_coverage,
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

async function loadRecentLeaveRequests(pool, userId, dateRange) {
  const result = await pool.query(
    `SELECT lr.id,
            lr.start_date::text AS start_date,
            lr.end_date::text AS end_date,
            COALESCE(lr.number_of_days, lr.total_days) AS days,
            lr.status,
            lr.reason,
            lr.attachment_name,
            lr.attachment_path,
            lr.details,
            lr.reviewer_remarks,
            lr.reviewed_at,
            lr.approved_at,
            reviewer.full_name AS reviewer_name,
            approver.full_name AS approver_name,
            lr.created_at,
            lr.updated_at,
            lt.name AS leave_type_key,
            COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type,
            latest_history.action AS latest_history_action,
            latest_history.from_status AS latest_history_from_status,
            latest_history.to_status AS latest_history_to_status,
            latest_history.remarks AS latest_history_remarks,
            latest_history.acted_at AS latest_history_acted_at,
            latest_history.actor_name AS latest_history_actor_name,
            history_summary.history AS history
     FROM leave_requests lr
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     LEFT JOIN users reviewer ON reviewer.id = lr.reviewer_id
     LEFT JOIN users approver ON approver.id = lr.approved_by
     LEFT JOIN LATERAL (
       SELECT h.action,
              h.from_status,
              h.to_status,
              h.remarks,
              h.acted_at,
              actor.full_name AS actor_name
       FROM leave_request_history h
       LEFT JOIN users actor ON actor.id = h.acted_by
       WHERE h.leave_request_id = lr.id
       ORDER BY h.acted_at DESC
       LIMIT 1
     ) latest_history ON true
     LEFT JOIN LATERAL (
       SELECT json_agg(
                json_build_object(
                  'action', h.action,
                  'from_status', h.from_status,
                  'to_status', h.to_status,
                  'remarks', h.remarks,
                  'acted_at', h.acted_at,
                  'actor_name', actor.full_name
                )
                ORDER BY h.acted_at DESC
              ) AS history
       FROM leave_request_history h
       LEFT JOIN users actor ON actor.id = h.acted_by
       WHERE h.leave_request_id = lr.id
     ) history_summary ON true
     WHERE lr.user_id = $1::uuid OR lr.employee_id = $1::uuid
     ORDER BY
       CASE
         WHEN lr.start_date <= $3::date AND lr.end_date >= $2::date THEN 0
         ELSE 1
       END,
       lr.updated_at DESC NULLS LAST,
       lr.created_at DESC
     LIMIT 30`,
    [userId, dateRange.startDate, dateRange.endDate]
  );

  return result.rows.map((row) => ({
    id: row.id,
    leave_type: row.leave_type,
    leave_type_key: row.leave_type_key,
    start_date: row.start_date,
    end_date: row.end_date,
    days: toNumber(row.days),
    status: row.status,
    reason: compactText(row.reason),
    has_attachment: !!row.attachment_path,
    attachment_name: compactText(row.attachment_name, 120),
    details: row.details && typeof row.details === 'object' ? row.details : {},
    reviewer_remarks: compactText(row.reviewer_remarks),
    reviewer_name: row.reviewer_name,
    approver_name: row.approver_name,
    reviewed_at: toIso(row.reviewed_at),
    approved_at: toIso(row.approved_at),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    latest_history: row.latest_history_action
      ? {
          action: row.latest_history_action,
          from_status: row.latest_history_from_status,
          to_status: row.latest_history_to_status,
          remarks: compactText(row.latest_history_remarks),
          acted_at: toIso(row.latest_history_acted_at),
          actor_name: row.latest_history_actor_name,
        }
      : null,
    history: parseJsonArray(row.history).map((item) => ({
      action: item.action,
      from_status: item.from_status,
      to_status: item.to_status,
      remarks: compactText(item.remarks),
      acted_at: toIso(item.acted_at),
      actor_name: item.actor_name,
    })),
  }));
}

async function loadLeaveTypes(pool) {
  const result = await pool.query(
    `SELECT id,
            name,
            display_name,
            description,
            employee_can_file,
            admin_only,
            allows_past_dates,
            requires_attachment,
            requires_attachment_when_over_days,
            max_days,
            minimum_advance_days,
            sex_eligibility,
            affects_dtr_normally,
            balance_ledger_type,
            is_active
     FROM leave_types
     WHERE is_active IS NULL OR is_active = true
     ORDER BY display_name NULLS LAST, name ASC
     LIMIT 30`
  );

  return result.rows.map((row) => ({
    id: row.id,
    name: row.name,
    display_name: row.display_name,
    description: compactText(row.description),
    employee_can_file: row.employee_can_file !== false,
    admin_only: row.admin_only === true,
    allows_past_dates: row.allows_past_dates !== false,
    requires_attachment: row.requires_attachment === true,
    requires_attachment_when_over_days: toNumber(row.requires_attachment_when_over_days),
    max_days: toNumber(row.max_days),
    minimum_advance_days: row.minimum_advance_days ?? null,
    sex_eligibility: row.sex_eligibility,
    affects_dtr_normally: row.affects_dtr_normally !== false,
    balance_ledger_type: row.balance_ledger_type,
    is_active: row.is_active !== false,
  }));
}

async function loadRecentLocatorSlips(pool, userId, dateRange) {
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
     ORDER BY
       CASE
         WHEN ls.slip_date BETWEEN $2::date AND $3::date THEN 0
         ELSE 1
       END,
       ls.updated_at DESC,
       ls.created_at DESC
     LIMIT 30`,
    [userId, dateRange.startDate, dateRange.endDate]
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

async function loadEmployeeAssistantContext(pool, { userId, message, dateRange: dateRangeOverride }) {
  const dateRange = dateRangeOverride || parseAssistantDateRange(message);
  const [
    employee,
    dtrRecords,
    dtrCalendarDays,
    leaveBalances,
    leaveRequests,
    leaveTypes,
    locatorSlips,
  ] =
    await Promise.all([
      loadEmployeeProfile(pool, userId),
      loadDtrRecords(pool, userId, dateRange),
      loadDtrCalendarDays(pool, userId, dateRange),
      loadLeaveBalances(pool, userId),
      loadRecentLeaveRequests(pool, userId, dateRange),
      loadLeaveTypes(pool),
      loadRecentLocatorSlips(pool, userId, dateRange),
    ]);

  return {
    scope: 'employee_self',
    date_range: dateRange,
    employee,
    dtr_records: dtrRecords,
    dtr_calendar_days: dtrCalendarDays,
    leave_balances: leaveBalances,
    recent_leave_requests: leaveRequests,
    leave_types: leaveTypes,
    leave_guidelines: buildGuidelinesForTypes(leaveTypes),
    recent_locator_slips: locatorSlips,
  };
}

module.exports = { loadEmployeeAssistantContext };
