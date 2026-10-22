/**
 * Phase 4 — Mayor endorsement monitoring stats (Asia/Manila).
 * Week boundary: Monday 00:00 Asia/Manila (PostgreSQL date_trunc('week')).
 */

'use strict';

const { MANILA_TZ, manilaDateSql } = require('../utils/mayorEndorsementIsolation');

function officialScopeSql(alias = 'mer', includeTest = false) {
  if (includeTest) return 'TRUE';
  return `COALESCE(${alias}.is_test, false) = false`;
}

function manilaTodayExpr() {
  return `(CURRENT_TIMESTAMP AT TIME ZONE '${MANILA_TZ}')::date`;
}

function manilaWeekStartExpr() {
  return `date_trunc('week', (CURRENT_TIMESTAMP AT TIME ZONE '${MANILA_TZ}'))::date`;
}

function manilaMonthStartExpr() {
  return `date_trunc('month', (CURRENT_TIMESTAMP AT TIME ZONE '${MANILA_TZ}'))::date`;
}

/** Official endorsement calendar date: endorsed_at, else office_form / approved for legacy. */
function officialEndorsementDateSql(alias = 'mer') {
  return manilaDateSql(
    `COALESCE(${alias}.endorsed_at, ${alias}.office_form_approved_at, ${alias}.approved_at)`,
  );
}

function parseReportPeriod(query = {}) {
  const period = String(query.period || 'monthly').trim().toLowerCase();
  const includeTest = query.include_test === '1' || query.include_test === 'true';
  let fromDate = null;
  let toDateExclusive = null;

  const today = new Date();
  // Build Manila calendar bounds in JS for custom; SQL uses expressions for presets.
  if (period === 'custom') {
    const fromRaw = String(query.from_date || query.from || '').trim();
    const toRaw = String(query.to_date || query.to || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(fromRaw) || !/^\d{4}-\d{2}-\d{2}$/.test(toRaw)) {
      return {
        error: 'Custom reports require from_date and to_date as YYYY-MM-DD',
      };
    }
    fromDate = fromRaw;
    // inclusive end → exclusive next day
    const end = new Date(`${toRaw}T00:00:00Z`);
    end.setUTCDate(end.getUTCDate() + 1);
    toDateExclusive = end.toISOString().slice(0, 10);
    return { period: 'custom', includeTest, fromDate, toDateExclusive, toDateInclusive: toRaw };
  }

  if (!['daily', 'weekly', 'monthly'].includes(period)) {
    return { error: 'period must be daily, weekly, monthly, or custom' };
  }
  return { period, includeTest, fromDate: null, toDateExclusive: null, today };
}

async function ensureIsTestColumn(pool) {
  await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS is_test BOOLEAN NOT NULL DEFAULT false
  `);
  await pool.query(`
    UPDATE public.mayor_endorsement_requests
       SET is_test = true
     WHERE id IN (
       'bf301de0-0461-45a6-93ff-f350791856c4'::uuid,
       'c77aa381-4c9c-494d-8e10-f8e282d4fac4'::uuid,
       '1dcdeb69-f310-4f01-bfed-c06c2f304855'::uuid
     )
       AND COALESCE(is_test, false) = false
  `);
}

async function fetchDashboardMetrics(pool, { includeTest = false } = {}) {
  await ensureIsTestColumn(pool);
  const scope = officialScopeSql('mer', includeTest);
  const endorseDate = officialEndorsementDateSql('mer');
  const submitDate = manilaDateSql('mer.submitted_at');
  const apptDate = manilaDateSql('mer.appointment_at');
  const rejectDate = manilaDateSql('mer.rejected_at');
  const today = manilaTodayExpr();
  const weekStart = manilaWeekStartExpr();
  const monthStart = manilaMonthStartExpr();
  const meetingInWindow = `mer.appointment_at IS NOT NULL
              AND COALESCE(mer.appointment_status, 'none') IN ('scheduled', 'completed')`;

  const [summaryRes, meetingRes, trendRes, officeRes, recentEndorsedRes, pendingActionsRes, upcomingRes] =
    await Promise.all([
      pool.query(`
        SELECT
          COUNT(*)::int AS total_requests,
          COUNT(*) FILTER (WHERE mer.status = 'pending')::int AS pending_count,
          COUNT(*) FILTER (WHERE mer.status = 'mayor_approved')::int AS mayor_approved_count,
          COUNT(*) FILTER (WHERE mer.status = 'endorsed')::int AS endorsed_count,
          COUNT(*) FILTER (WHERE mer.status = 'rejected')::int AS rejected_count,
          COUNT(*) FILTER (
            WHERE mer.status = 'endorsed' AND ${endorseDate} = ${today}
          )::int AS endorsed_today,
          COUNT(*) FILTER (
            WHERE mer.status = 'endorsed' AND ${endorseDate} >= ${weekStart}
          )::int AS endorsed_this_week,
          COUNT(*) FILTER (
            WHERE mer.status = 'endorsed' AND ${endorseDate} >= ${monthStart}
          )::int AS endorsed_this_month,
          COUNT(*) FILTER (WHERE ${submitDate} = ${today})::int AS requests_today,
          COUNT(*) FILTER (WHERE ${submitDate} >= ${weekStart})::int AS requests_this_week,
          COUNT(*) FILTER (WHERE ${submitDate} >= ${monthStart})::int AS requests_this_month,
          COUNT(*) FILTER (
            WHERE mer.status = 'rejected' AND ${rejectDate} = ${today}
          )::int AS rejected_today,
          COUNT(*) FILTER (
            WHERE mer.status = 'rejected' AND ${rejectDate} >= ${weekStart}
          )::int AS rejected_this_week,
          COUNT(*) FILTER (
            WHERE mer.status = 'rejected' AND ${rejectDate} >= ${monthStart}
          )::int AS rejected_this_month,
          COUNT(*) FILTER (
            WHERE ${meetingInWindow} AND ${apptDate} = ${today}
          )::int AS meetings_on_today,
          COUNT(*) FILTER (
            WHERE ${meetingInWindow}
              AND ${apptDate} >= ${weekStart}
              AND ${apptDate} < (${weekStart} + 7)
          )::int AS meetings_this_week,
          COUNT(*) FILTER (
            WHERE ${meetingInWindow}
              AND ${apptDate} >= ${monthStart}
              AND ${apptDate} < (${monthStart} + INTERVAL '1 month')
          )::int AS meetings_this_month,
          COUNT(*) FILTER (
            WHERE mer.meeting_request_status = 'submitted'
          )::int AS pending_meeting_approvals,
          COUNT(*) FILTER (
            WHERE mer.status = 'pending'
              AND COALESCE(mer.appointment_status, 'none') = 'completed'
          )::int AS pending_final_decisions,
          COUNT(*) FILTER (
            WHERE mer.status = 'pending'
              AND mer.meeting_request_status = 'approved'
              AND COALESCE(mer.appointment_status, 'none') = 'scheduled'
          )::int AS pending_attendance,
          COUNT(*) FILTER (
            WHERE mer.meeting_request_status = 'reschedule_requested'
          )::int AS reschedule_requested_count,
          COUNT(*) FILTER (
            WHERE mer.meeting_request_status = 'approved'
          )::int AS approved_meetings_count,
          COUNT(*) FILTER (
            WHERE COALESCE(mer.appointment_status, 'none') = 'completed'
          )::int AS completed_meetings_count,
          COUNT(*) FILTER (
            WHERE COALESCE(mer.appointment_status, 'none') = 'scheduled'
              AND ${apptDate} = ${today}
          )::int AS meetings_today,
          COUNT(*) FILTER (
            WHERE COALESCE(mer.appointment_status, 'none') = 'scheduled'
              AND mer.appointment_at IS NOT NULL
              AND ${apptDate} > ${today}
          )::int AS upcoming_meetings,
          COUNT(*) FILTER (
            WHERE COALESCE(mer.appointment_status, 'none') = 'scheduled'
              AND COALESCE(mer.meeting_request_status, 'none') = 'none'
          )::int AS legacy_scheduled_without_meeting_approval
        FROM mayor_endorsement_requests mer
        WHERE ${scope}
      `),
      pool.query(`
        SELECT
          mer.id,
          mer.reference_number,
          mer.status,
          mer.meeting_request_status,
          mer.meeting_proposed_at,
          mer.meeting_purpose,
          mer.appointment_at,
          mer.appointment_status,
          COALESCE(mer.applicant_full_name,
            NULLIF(TRIM(CONCAT_WS(' ',
              mer.intake_form->>'first_name',
              mer.intake_form->>'middle_name_or_initial',
              mer.intake_form->>'last_name'
            )), '')
          ) AS applicant_name,
          COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name
        FROM mayor_endorsement_requests mer
        LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
        LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
        WHERE ${scope}
          AND (
            mer.meeting_request_status = 'submitted'
            OR (
              COALESCE(mer.appointment_status, 'none') = 'scheduled'
              AND mer.appointment_at IS NOT NULL
              AND ${apptDate} >= ${today}
            )
          )
        ORDER BY COALESCE(mer.meeting_proposed_at, mer.appointment_at) ASC NULLS LAST
        LIMIT 15
      `),
      pool.query(`
        SELECT
          to_char(month_start, 'YYYY-MM') AS month,
          COUNT(*)::int AS endorsed_count
        FROM (
          SELECT date_trunc('month', ${endorseDate})::date AS month_start
          FROM mayor_endorsement_requests mer
          WHERE ${scope}
            AND mer.status = 'endorsed'
            AND COALESCE(mer.endorsed_at, mer.office_form_approved_at, mer.approved_at) IS NOT NULL
            AND ${endorseDate} >= (${monthStart} - INTERVAL '11 months')
        ) t
        GROUP BY month_start
        ORDER BY month_start ASC
      `),
      pool.query(`
        SELECT
          COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name, 'Unassigned') AS office_name,
          COUNT(*)::int AS total
        FROM mayor_endorsement_requests mer
        LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
        LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
        WHERE ${scope}
          AND mer.status = 'endorsed'
        GROUP BY 1
        ORDER BY total DESC, office_name ASC
        LIMIT 20
      `),
      pool.query(`
        SELECT
          mer.id,
          mer.reference_number,
          mer.status,
          mer.endorsed_at,
          mer.approved_at,
          mer.office_form_approved_at,
          mer.submitted_at,
          COALESCE(mer.applicant_full_name,
            NULLIF(TRIM(CONCAT_WS(' ',
              mer.intake_form->>'first_name',
              mer.intake_form->>'middle_name_or_initial',
              mer.intake_form->>'last_name'
            )), '')
          ) AS applicant_name,
          COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name
        FROM mayor_endorsement_requests mer
        LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
        LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
        WHERE ${scope}
          AND mer.status = 'endorsed'
        ORDER BY COALESCE(mer.endorsed_at, mer.office_form_approved_at, mer.approved_at) DESC NULLS LAST
        LIMIT 10
      `),
      pool.query(`
        SELECT
          mer.id,
          mer.reference_number,
          mer.status,
          mer.meeting_request_status,
          mer.appointment_status,
          mer.priority,
          mer.submitted_at,
          mer.meeting_proposed_at,
          mer.appointment_at,
          COALESCE(mer.applicant_full_name,
            NULLIF(TRIM(CONCAT_WS(' ',
              mer.intake_form->>'first_name',
              mer.intake_form->>'middle_name_or_initial',
              mer.intake_form->>'last_name'
            )), '')
          ) AS applicant_name,
          COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name
        FROM mayor_endorsement_requests mer
        LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
        LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
        WHERE ${scope}
          AND (
            mer.meeting_request_status = 'submitted'
            OR (
              mer.status = 'pending'
              AND COALESCE(mer.appointment_status, 'none') = 'completed'
            )
            OR mer.status = 'mayor_approved'
          )
        ORDER BY mer.submitted_at DESC
        LIMIT 15
      `),
      pool.query(`
        SELECT
          mer.id,
          mer.reference_number,
          mer.appointment_at,
          mer.appointment_status,
          mer.meeting_request_status,
          COALESCE(mer.applicant_full_name,
            NULLIF(TRIM(CONCAT_WS(' ',
              mer.intake_form->>'first_name',
              mer.intake_form->>'middle_name_or_initial',
              mer.intake_form->>'last_name'
            )), '')
          ) AS applicant_name,
          COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name
        FROM mayor_endorsement_requests mer
        LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
        LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
        WHERE ${scope}
          AND COALESCE(mer.appointment_status, 'none') = 'scheduled'
          AND mer.appointment_at IS NOT NULL
          AND ${apptDate} >= ${today}
        ORDER BY mer.appointment_at ASC
        LIMIT 10
      `),
    ]);

  const s = summaryRes.rows[0] || {};
  return {
    timezone: MANILA_TZ,
    week_boundary: 'monday',
    include_test: includeTest,
    summary: {
      total_requests: s.total_requests || 0,
      pending_count: s.pending_count || 0,
      mayor_approved_count: s.mayor_approved_count || 0,
      endorsed_count: s.endorsed_count || 0,
      rejected_count: s.rejected_count || 0,
      endorsed_today: s.endorsed_today || 0,
      endorsed_this_week: s.endorsed_this_week || 0,
      endorsed_this_month: s.endorsed_this_month || 0,
      requests_today: s.requests_today || 0,
      requests_this_week: s.requests_this_week || 0,
      requests_this_month: s.requests_this_month || 0,
      rejected_today: s.rejected_today || 0,
      rejected_this_week: s.rejected_this_week || 0,
      rejected_this_month: s.rejected_this_month || 0,
      meetings_on_today: s.meetings_on_today || 0,
      meetings_this_week: s.meetings_this_week || 0,
      meetings_this_month: s.meetings_this_month || 0,
      pending_meeting_approvals: s.pending_meeting_approvals || 0,
      pending_final_decisions: s.pending_final_decisions || 0,
      pending_attendance: s.pending_attendance || 0,
      reschedule_requested_count: s.reschedule_requested_count || 0,
      approved_meetings_count: s.approved_meetings_count || 0,
      completed_meetings_count: s.completed_meetings_count || 0,
      meetings_today: s.meetings_today || 0,
      upcoming_meetings: s.upcoming_meetings || 0,
      legacy_scheduled_without_meeting_approval:
        s.legacy_scheduled_without_meeting_approval || 0,
    },
    monthly_trends: trendRes.rows,
    office_statistics: officeRes.rows,
    recent_endorsements: recentEndorsedRes.rows,
    pending_mayor_actions: pendingActionsRes.rows,
    meeting_queue: meetingRes.rows,
    upcoming_meetings: upcomingRes.rows,
    // Backward-compatible aliases for older Flutter clients
    recent_requests: pendingActionsRes.rows.slice(0, 10),
  };
}

async function fetchEndorsementReport(pool, options) {
  await ensureIsTestColumn(pool);
  const parsed = parseReportPeriod(options);
  if (parsed.error) return { error: parsed.error, status: 400 };

  const { period, includeTest, fromDate, toDateExclusive, toDateInclusive } = parsed;
  const scope = officialScopeSql('mer', includeTest);
  const endorseDate = officialEndorsementDateSql('mer');
  const submitDate = manilaDateSql('mer.submitted_at');
  const today = manilaTodayExpr();
  const weekStart = manilaWeekStartExpr();
  const monthStart = manilaMonthStartExpr();

  let periodSql;
  let labelFrom;
  let labelTo;
  const params = [];

  if (period === 'daily') {
    periodSql = `${endorseDate} = ${today} OR (${submitDate} = ${today} AND mer.status IN ('pending','mayor_approved','rejected'))`;
    // For report rows: include all statuses whose relevant date falls in period.
    // Spec: totals for requests/endorsed/rejected/pending in period.
    periodSql = `(
      (${submitDate} = ${today})
      OR (mer.status = 'endorsed' AND ${endorseDate} = ${today})
      OR (mer.status = 'rejected' AND ${manilaDateSql('mer.rejected_at')} = ${today})
    )`;
    labelFrom = 'today';
    labelTo = 'today';
  } else if (period === 'weekly') {
    periodSql = `(
      (${submitDate} >= ${weekStart})
      OR (mer.status = 'endorsed' AND ${endorseDate} >= ${weekStart})
      OR (mer.status = 'rejected' AND ${manilaDateSql('mer.rejected_at')} >= ${weekStart})
    )`;
    labelFrom = 'week_start';
    labelTo = 'today';
  } else if (period === 'monthly') {
    periodSql = `(
      (${submitDate} >= ${monthStart})
      OR (mer.status = 'endorsed' AND ${endorseDate} >= ${monthStart})
      OR (mer.status = 'rejected' AND ${manilaDateSql('mer.rejected_at')} >= ${monthStart})
    )`;
    labelFrom = 'month_start';
    labelTo = 'today';
  } else {
    params.push(fromDate, toDateExclusive);
    periodSql = `(
      (${submitDate} >= $1::date AND ${submitDate} < $2::date)
      OR (mer.status = 'endorsed' AND ${endorseDate} >= $1::date AND ${endorseDate} < $2::date)
      OR (mer.status = 'rejected' AND ${manilaDateSql('mer.rejected_at')} >= $1::date AND ${manilaDateSql('mer.rejected_at')} < $2::date)
    )`;
    labelFrom = fromDate;
    labelTo = toDateInclusive;
  }

  const boundsRes = await pool.query(`
    SELECT
      to_char(${today}, 'YYYY-MM-DD') AS today,
      to_char(${weekStart}, 'YYYY-MM-DD') AS week_start,
      to_char(${monthStart}, 'YYYY-MM-DD') AS month_start
  `);
  const bounds = boundsRes.rows[0] || {};

  const rowsRes = await pool.query(
    `
    SELECT
      mer.id,
      mer.reference_number,
      mer.status,
      mer.submitted_at,
      mer.endorsed_at,
      mer.approved_at,
      mer.office_form_approved_at,
      mer.rejected_at,
      mer.is_test,
      COALESCE(mer.applicant_full_name,
        NULLIF(TRIM(CONCAT_WS(' ',
          mer.intake_form->>'first_name',
          mer.intake_form->>'middle_name_or_initial',
          mer.intake_form->>'last_name'
        )), '')
      ) AS applicant_name,
      COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name, 'Unassigned') AS destination_office
    FROM mayor_endorsement_requests mer
    LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
    LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
    WHERE ${scope}
      AND (${periodSql})
    ORDER BY COALESCE(mer.endorsed_at, mer.rejected_at, mer.submitted_at) DESC
    `,
    params,
  );

  const rows = rowsRes.rows;
  // Unique counts by status (one record once)
  const totals = {
    total_requests: rows.length,
    total_endorsed: rows.filter((r) => r.status === 'endorsed').length,
    total_rejected: rows.filter((r) => r.status === 'rejected').length,
    total_pending: rows.filter(
      (r) => r.status === 'pending' || r.status === 'mayor_approved',
    ).length,
  };

  const periodLabel = {
    daily: {
      from: bounds.today,
      to: bounds.today,
      title: 'Daily Endorsement Report',
    },
    weekly: {
      from: bounds.week_start,
      to: bounds.today,
      title: 'Weekly Endorsement Report',
    },
    monthly: {
      from: bounds.month_start,
      to: bounds.today,
      title: 'Monthly Endorsement Report',
    },
    custom: {
      from: labelFrom,
      to: labelTo,
      title: 'Custom Range Endorsement Report',
    },
  }[period];

  return {
    timezone: MANILA_TZ,
    week_boundary: 'monday',
    include_test: includeTest,
    period,
    report_title: periodLabel.title,
    reporting_period: {
      from: periodLabel.from,
      to: periodLabel.to,
    },
    totals,
    rows: rows.map((r) => ({
      id: r.id,
      reference_number: r.reference_number,
      applicant_name: r.applicant_name,
      destination_office: r.destination_office,
      status: r.status,
      submitted_at: r.submitted_at,
      endorsed_at: r.endorsed_at || r.office_form_approved_at || r.approved_at || null,
      rejected_at: r.rejected_at,
      is_test: Boolean(r.is_test),
    })),
  };
}

module.exports = {
  MANILA_TZ,
  officialScopeSql,
  officialEndorsementDateSql,
  ensureIsTestColumn,
  fetchDashboardMetrics,
  fetchEndorsementReport,
  parseReportPeriod,
};
