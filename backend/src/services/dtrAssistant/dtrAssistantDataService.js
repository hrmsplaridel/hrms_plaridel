const {
  MAX_ASSISTANT_DATE_RANGE_DAYS,
  assertAssistantDateRange,
  parseAssistantDateRange,
} = require('../../utils/dateRangeParser');
const {
  buildDtrPolicyKnowledge,
  buildLocatorPolicyKnowledge,
} = require('./attendanceLocatorPolicies');
const {
  buildAllLeaveGuidelines,
  buildGuidelinesForTypes,
} = require('./leaveFilingGuidelines');
const {
  normalizeEmployeeDetailSchema,
  sanitizeEmployeeLeaveDetails,
} = require('../leaveRequestDetailsPolicy');

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

function assistantQueryTimeoutMs(env = process.env) {
  const parsed = Number.parseInt(
    String(env.DTR_ASSISTANT_QUERY_TIMEOUT_MS || '10000'),
    10
  );
  if (!Number.isFinite(parsed)) return 10000;
  return Math.max(1000, Math.min(parsed, 60000));
}

function throwIfAssistantQueryAborted(signal) {
  if (!signal?.aborted) return;
  const error = new Error('Assistant request was cancelled.');
  error.statusCode = 499;
  error.code = 'ASSISTANT_REQUEST_ABORTED';
  throw error;
}

function runAssistantQuery(pool, text, values = []) {
  return pool.query({
    text,
    values,
    query_timeout: assistantQueryTimeoutMs(),
  });
}

const ASSISTANT_CONTEXT_SOURCES = [
  'employee',
  'dtrRecords',
  'dtrCalendarDays',
  'leaveBalances',
  'leaveRequests',
  'leaveAnnualUsage',
  'leaveTypes',
  'locatorSlips',
  'locatorTypes',
];

const DTR_RECORD_INTENTS = new Set([
  'today_dtr',
  'missing_logs',
  'dtr_daily_record',
  'dtr_range_summary',
  'dtr_missing_logs',
  'dtr_missing_log_reason',
  'dtr_late_summary',
  'dtr_late_reason',
  'dtr_undertime_summary',
  'dtr_overtime_summary',
  'dtr_absent_summary',
  'dtr_status_explanation',
  'dtr_correction_guidance',
  'dtr_export_guidance',
  'dtr_hours_summary',
]);

const LEAVE_REQUEST_INTENTS = new Set([
  'latest_leave_request',
  'pending_leave_requests',
  'approved_leave_requests',
  'rejected_leave_requests',
  'leave_history',
  'leave_overlap_check',
  'leave_request_summary',
  'leave_request_lookup',
  'leave_rejection_reason',
  'leave_approval_tracker',
  'leave_approval_history',
]);

const LEAVE_BALANCE_INTENTS = new Set([
  'leave_balance',
  'leave_pending_days_explanation',
  'leave_balance_after_filing',
  'leave_balance_projection',
]);

const LEAVE_FILING_CHECK_INTENTS = new Set([
  'leave_availability_check',
  'leave_guided_filing',
]);

const LOCATOR_HISTORY_INTENTS = new Set([
  'latest_locator_request',
  'locator_status',
  'locator_summary',
  'locator_rejection_reason',
  'locator_approval_tracker',
]);

function allAssistantContextSources() {
  return Object.fromEntries(
    ASSISTANT_CONTEXT_SOURCES.map((source) => [source, true])
  );
}

function assistantContextLoadPlan(intents) {
  const normalized = [...new Set(
    (Array.isArray(intents) ? intents : [intents])
      .map((intent) => String(intent || '').trim())
      .filter(Boolean)
  )];
  if (
    normalized.length === 0 ||
    normalized.some((intent) => intent === 'unknown' || intent === 'direct_ai')
  ) {
    return allAssistantContextSources();
  }

  const plan = Object.fromEntries(
    ASSISTANT_CONTEXT_SOURCES.map((source) => [source, false])
  );
  plan.employee = true;

  for (const intent of normalized) {
    if (DTR_RECORD_INTENTS.has(intent)) {
      plan.dtrRecords = true;
      plan.dtrCalendarDays = true;
      continue;
    }
    if (intent === 'dtr_holiday_check' || intent === 'dtr_schedule_context') {
      plan.dtrCalendarDays = true;
      continue;
    }
    if (intent === 'dtr_leave_coverage_check') {
      plan.leaveRequests = true;
      plan.leaveTypes = true;
      continue;
    }
    if (intent === 'dtr_locator_coverage_check') {
      plan.dtrCalendarDays = true;
      plan.locatorSlips = true;
      plan.locatorTypes = true;
      continue;
    }
    if (intent === 'dtr_policy_guidance') continue;

    if (intent.startsWith('leave_') || LEAVE_REQUEST_INTENTS.has(intent)) {
      plan.leaveTypes = true;
      if (LEAVE_REQUEST_INTENTS.has(intent)) plan.leaveRequests = true;
      if (LEAVE_BALANCE_INTENTS.has(intent)) plan.leaveBalances = true;
      if (intent === 'leave_pending_days_explanation') {
        plan.leaveRequests = true;
      }
      if (LEAVE_FILING_CHECK_INTENTS.has(intent)) {
        plan.leaveBalances = true;
        plan.leaveRequests = true;
        plan.leaveAnnualUsage = true;
      }
      continue;
    }

    if (intent.startsWith('locator_') || LOCATOR_HISTORY_INTENTS.has(intent)) {
      plan.locatorTypes = true;
      if (LOCATOR_HISTORY_INTENTS.has(intent)) plan.locatorSlips = true;
      if (intent === 'locator_availability_check') {
        plan.dtrCalendarDays = true;
        plan.locatorSlips = true;
      }
      continue;
    }

    return allAssistantContextSources();
  }

  return plan;
}

const catalogCacheByPool = new WeakMap();

function assistantCatalogCacheMs(env = process.env) {
  const parsed = Number.parseInt(
    String(env.DTR_ASSISTANT_CATALOG_CACHE_MS || '60000'),
    10
  );
  if (!Number.isFinite(parsed)) return 60000;
  return Math.max(0, Math.min(parsed, 5 * 60 * 1000));
}

async function loadCachedAssistantCatalog(pool, key, loader) {
  const ttlMs = assistantCatalogCacheMs();
  if (ttlMs <= 0 || !pool || typeof pool !== 'object') return loader();
  const now = Date.now();
  const poolCache = catalogCacheByPool.get(pool) || new Map();
  const cached = poolCache.get(key);
  if (cached && cached.expiresAt > now) {
    return cached.promise || cached.value;
  }
  const promise = Promise.resolve().then(loader);
  poolCache.set(key, { promise, expiresAt: now + ttlMs });
  catalogCacheByPool.set(pool, poolCache);
  try {
    const value = await promise;
    poolCache.set(key, { value, expiresAt: Date.now() + ttlMs });
    return value;
  } catch (error) {
    if (poolCache.get(key)?.promise === promise) poolCache.delete(key);
    throw error;
  }
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
  const result = await runAssistantQuery(
    pool,
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
  const result = await runAssistantQuery(
    pool,
    `WITH active_leave_coverage AS (
       SELECT c.*
       FROM dtr_leave_coverage c
       JOIN leave_requests request ON request.id = c.leave_request_id
       WHERE request.status = 'approved'
     )
     SELECT COALESCE(d.id, coverage.id) AS id,
            COALESCE(d.attendance_date, coverage.attendance_date)::text AS attendance_date,
            d.time_in,
            d.break_out,
            d.break_in,
            d.time_out,
            d.total_hours,
            CASE WHEN coverage.id IS NOT NULL THEN 0 ELSE d.late_minutes END AS late_minutes,
            CASE WHEN coverage.id IS NOT NULL THEN 0 ELSE d.undertime_minutes END AS undertime_minutes,
            CASE WHEN coverage.id IS NOT NULL THEN 0 ELSE d.overtime_minutes END AS overtime_minutes,
            CASE WHEN coverage.id IS NOT NULL THEN 'on_leave' ELSE d.status END AS status,
            d.pm_status,
            d.remarks,
            CASE WHEN coverage.id IS NOT NULL THEN 'adjusted' ELSE d.source END AS source,
            h.name AS holiday_name,
            h.holiday_type,
            lt.name AS leave_type
     FROM dtr_daily_summary d
     FULL OUTER JOIN active_leave_coverage coverage
       ON coverage.employee_id = d.employee_id
      AND coverage.attendance_date = d.attendance_date
     LEFT JOIN holidays h ON h.id = d.holiday_id
     LEFT JOIN leave_requests lr
       ON lr.id = COALESCE(coverage.leave_request_id, d.leave_request_id)
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE COALESCE(d.employee_id, coverage.employee_id) = $1::uuid
       AND COALESCE(d.attendance_date, coverage.attendance_date)
         BETWEEN $2::date AND $3::date
     ORDER BY COALESCE(d.attendance_date, coverage.attendance_date) DESC`,
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
  const result = await runAssistantQuery(
    pool,
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
     FROM generate_series(
       $2::date,
       LEAST(
         $3::date,
         $2::date + (($4::int - 1) * interval '1 day')
       ),
       interval '1 day'
     ) AS day(day)
     LEFT JOIN LATERAL (
       SELECT a.*
       FROM assignments a
       WHERE a.employee_id = $1::uuid
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
    [
      userId,
      dateRange.startDate,
      dateRange.endDate,
      MAX_ASSISTANT_DATE_RANGE_DAYS,
    ]
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
  const result = await runAssistantQuery(
    pool,
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
  const result = await runAssistantQuery(
    pool,
    `SELECT lr.id,
            lr.start_date::text AS start_date,
            lr.end_date::text AS end_date,
            COALESCE(lr.number_of_days, lr.total_days) AS days,
            lr.status,
            lr.reason,
            lr.attachment_name,
            lr.attachment_path,
            lr.details,
            lr.employee_detail_schema_snapshot,
            lr.reviewer_remarks,
            lr.recommendation_remarks,
            lr.disapproval_reason,
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
    details: sanitizeEmployeeLeaveDetails(
      row.details,
      row.employee_detail_schema_snapshot
    ),
    employee_detail_schema_snapshot: normalizeEmployeeDetailSchema(
      row.employee_detail_schema_snapshot
    ),
    reviewer_remarks: compactText(row.reviewer_remarks),
    recommendation_remarks: compactText(row.recommendation_remarks),
    disapproval_reason: compactText(row.disapproval_reason),
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

async function loadAnnualLeaveUsage(pool, userId, dateRange) {
  const year = parseInt(String(dateRange?.startDate || '').slice(0, 4), 10);
  if (!Number.isInteger(year)) return [];
  const trackedTypes = ['specialPrivilegeLeave', 'soloParentLeave', 'tenDayVawcLeave'];
  const result = await runAssistantQuery(
    pool,
    `SELECT lt.name AS leave_type_key,
            COALESCE(SUM(COALESCE(lr.number_of_days, lr.total_days, 0)), 0)::float8 AS days,
            COUNT(*)::int AS request_count
     FROM leave_requests lr
     INNER JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE (lr.user_id = $1::uuid OR lr.employee_id = $1::uuid)
       AND lt.name = ANY($2::text[])
       AND lr.status = ANY($3::text[])
       AND lr.start_date <= $5::date
       AND lr.end_date >= $4::date
     GROUP BY lt.name
     ORDER BY lt.name ASC`,
    [
      userId,
      trackedTypes,
      ['pending', 'pending_department_head', 'pending_hr', 'approved'],
      `${year}-01-01`,
      `${year}-12-31`,
    ]
  );

  const usageByType = new Map(
    result.rows.map((row) => [
      row.leave_type_key,
      {
        year,
        leave_type_key: row.leave_type_key,
        days: toNumber(row.days) || 0,
        request_count: row.request_count || 0,
      },
    ])
  );

  return trackedTypes.map(
    (leaveTypeKey) =>
      usageByType.get(leaveTypeKey) || {
        year,
        leave_type_key: leaveTypeKey,
        days: 0,
        request_count: 0,
      }
  );
}

async function queryLeaveTypes(pool) {
  const result = await runAssistantQuery(
    pool,
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
            entitlement_basis,
            employee_detail_schema,
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
    entitlement_basis: row.entitlement_basis,
    employee_detail_schema: normalizeEmployeeDetailSchema(
      row.employee_detail_schema
    ),
    is_active: row.is_active !== false,
  }));
}

function loadLeaveTypes(pool) {
  return loadCachedAssistantCatalog(pool, 'leaveTypes', () =>
    queryLeaveTypes(pool)
  );
}

async function loadRecentLocatorSlips(pool, userId, dateRange) {
  const result = await runAssistantQuery(
    pool,
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
            ls.revoked_at,
            ls.revocation_reason,
            ls.month_end_reconciliation_required,
            ls.month_end_reconciled_at,
            ls.attachment_name,
            ls.attachment_path,
            ls.created_at,
            ls.updated_at,
            dept_head.full_name AS dept_head_reviewer_name,
            hr.full_name AS hr_reviewer_name,
            revoker.full_name AS revoked_by_name,
            COALESCE(ls.request_type_label_snapshot, lrt.label) AS request_type_label,
            COALESCE(ls.request_type_short_label_snapshot, lrt.short_label) AS request_type_short_label,
            COALESCE(ls.request_type_location_label_snapshot, lrt.location_label) AS request_type_location_label,
            COALESCE(ls.request_type_location_hint_snapshot, lrt.location_hint) AS request_type_location_hint,
            COALESCE(ls.request_type_dtr_slot_label_snapshot, lrt.dtr_slot_label) AS dtr_slot_label,
            COALESCE(ls.request_type_dtr_print_label_snapshot, lrt.dtr_print_label) AS dtr_print_label,
            COALESCE(ls.request_type_requires_attachment_snapshot, lrt.requires_attachment, false) AS request_type_requires_attachment,
            COALESCE(ls.request_type_coverage_mode_snapshot, lrt.coverage_mode) AS request_type_coverage_mode
     FROM locator_slips ls
     LEFT JOIN users dept_head ON dept_head.id = ls.dept_head_reviewer_id
     LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
     LEFT JOIN users revoker ON revoker.id = ls.revoked_by
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
    request_type_short_label: row.request_type_short_label,
    request_type_location_label: row.request_type_location_label,
    request_type_location_hint: row.request_type_location_hint,
    dtr_slot_label: row.dtr_slot_label,
    dtr_print_label: row.dtr_print_label,
    request_type_requires_attachment: row.request_type_requires_attachment === true,
    request_type_coverage_mode: row.request_type_coverage_mode,
    office: compactText(row.office),
    reason: compactText(row.reason),
    has_attachment: !!row.attachment_path,
    attachment_name: compactText(row.attachment_name, 120),
    coverage: {
      am_in: row.am_in,
      am_out: row.am_out,
      pm_in: row.pm_in,
      pm_out: row.pm_out,
    },
    status: row.status,
    dept_head_remarks: compactText(row.dept_head_remarks),
    hr_remarks: compactText(row.hr_remarks),
    dept_head_reviewer_name: row.dept_head_reviewer_name,
    hr_reviewer_name: row.hr_reviewer_name,
    revoked_by_name: row.revoked_by_name,
    dept_head_reviewed_at: toIso(row.dept_head_reviewed_at),
    hr_reviewed_at: toIso(row.hr_reviewed_at),
    revoked_at: toIso(row.revoked_at),
    revocation_reason: compactText(row.revocation_reason),
    month_end_reconciliation_required:
      row.month_end_reconciliation_required === true,
    month_end_reconciled_at: toIso(row.month_end_reconciled_at),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  }));
}

async function queryLocatorTypes(pool) {
  const result = await runAssistantQuery(
    pool,
    `SELECT code,
            label,
            short_label,
            location_label,
            location_hint,
            dtr_slot_label,
            dtr_print_label,
            requires_attachment,
            coverage_mode,
            is_active,
            sort_order
     FROM locator_request_types
     WHERE is_active IS NULL OR is_active = true
     ORDER BY sort_order ASC, label ASC
     LIMIT 40`
  );

  return result.rows.map((row) => ({
    code: row.code,
    label: row.label,
    short_label: row.short_label,
    location_label: row.location_label,
    location_hint: row.location_hint,
    dtr_slot_label: row.dtr_slot_label,
    dtr_print_label: row.dtr_print_label,
    requires_attachment: row.requires_attachment === true,
    coverage_mode: row.coverage_mode,
    is_active: row.is_active !== false,
    sort_order: row.sort_order,
  }));
}

function loadLocatorTypes(pool) {
  return loadCachedAssistantCatalog(pool, 'locatorTypes', () =>
    queryLocatorTypes(pool)
  );
}

async function loadEmployeeAssistantContext(
  pool,
  { userId, message, dateRange: dateRangeOverride, intents, signal }
) {
  throwIfAssistantQueryAborted(signal);
  const dateRange = assertAssistantDateRange(
    dateRangeOverride || parseAssistantDateRange(message)
  );
  const loadPlan = assistantContextLoadPlan(intents);
  const [
    employee,
    dtrRecords,
    dtrCalendarDays,
    leaveBalances,
    leaveRequests,
    leaveAnnualUsage,
    leaveTypes,
    locatorSlips,
    locatorTypes,
  ] =
    await Promise.all([
      loadPlan.employee ? loadEmployeeProfile(pool, userId) : null,
      loadPlan.dtrRecords ? loadDtrRecords(pool, userId, dateRange) : [],
      loadPlan.dtrCalendarDays
        ? loadDtrCalendarDays(pool, userId, dateRange)
        : [],
      loadPlan.leaveBalances ? loadLeaveBalances(pool, userId) : [],
      loadPlan.leaveRequests
        ? loadRecentLeaveRequests(pool, userId, dateRange)
        : [],
      loadPlan.leaveAnnualUsage
        ? loadAnnualLeaveUsage(pool, userId, dateRange)
        : [],
      loadPlan.leaveTypes ? loadLeaveTypes(pool) : [],
      loadPlan.locatorSlips
        ? loadRecentLocatorSlips(pool, userId, dateRange)
        : [],
      loadPlan.locatorTypes ? loadLocatorTypes(pool) : [],
    ]);
  throwIfAssistantQueryAborted(signal);

  return {
    scope: 'employee_self',
    date_range: dateRange,
    context_sources: {
      intents: Array.isArray(intents) ? intents : intents ? [intents] : [],
      loaded: ASSISTANT_CONTEXT_SOURCES.filter((source) => loadPlan[source]),
    },
    data_completeness: {
      dtr_records: {
        complete: loadPlan.dtrRecords,
        capped: false,
        returned_count: dtrRecords.length,
      },
      dtr_calendar_days: {
        complete: loadPlan.dtrCalendarDays,
        capped: false,
        returned_count: dtrCalendarDays.length,
      },
      dtr_export: {
        complete: loadPlan.dtrRecords && loadPlan.dtrCalendarDays,
      },
    },
    employee,
    dtr_records: dtrRecords,
    dtr_calendar_days: dtrCalendarDays,
    leave_balances: leaveBalances,
    recent_leave_requests: leaveRequests,
    leave_annual_usage: leaveAnnualUsage,
    leave_types: leaveTypes,
    leave_guidelines: buildGuidelinesForTypes(leaveTypes),
    leave_guideline_catalog: buildAllLeaveGuidelines(),
    recent_locator_slips: locatorSlips,
    locator_types: locatorTypes,
    dtr_policies: buildDtrPolicyKnowledge(),
    locator_policies: buildLocatorPolicyKnowledge(),
  };
}

module.exports = {
  loadEmployeeAssistantContext,
  __test: {
    assistantQueryTimeoutMs,
    assistantCatalogCacheMs,
    assistantContextLoadPlan,
  },
};
