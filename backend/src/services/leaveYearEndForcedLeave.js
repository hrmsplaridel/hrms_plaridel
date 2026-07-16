/**
 * Year-end Mandatory/Forced Leave compliance and bulk deduction service.
 *
 * CSC rule: All employees must take at least 5 working days of forced/vacation
 * leave annually. If unused by year-end, HR deducts the shortfall from VL credits.
 *
 * Approved mandatory/forced leave and qualifying vacation leave both count
 * toward the five-day requirement (CSC Form No. 6 / Section 25).
 */

const { insertLeaveBalanceLedger } = require('./leaveBalanceLedger');

const REQUIRED_FORCED_DAYS = 5;
const CRON_ADVISORY_LOCK_KEY = 918273646; // distinct from monthly accrual (918273645)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function manilaYearNow() {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
  });
  return parseInt(fmt.format(new Date()), 10);
}

// ---------------------------------------------------------------------------
// Compliance query
// ---------------------------------------------------------------------------

/**
 * Returns year-end forced leave compliance for every active employee.
 * @param {import('pg').Pool} pool
 * @param {{ year: number }} options
 */
async function getYearEndForcedLeaveCompliance(pool, { year }) {
  const yearStr = String(year);
  const yearClosed = year < manilaYearNow();

  const { rows } = await pool.query(
    `
    SELECT
      u.id                                                   AS user_id,
      u.employee_number,
      u.full_name,
      cur.current_department_name,

      /* Approved mandatoryForcedLeave days in the target year */
      COALESCE(fl.forced_days, 0)::numeric                   AS forced_leave_days_used,

      /* Current VL available balance */
      GREATEST(
        COALESCE(vl.earned_days, 0)
          - COALESCE(vl.used_days, 0)
          + COALESCE(vl.adjusted_days, 0),
        0
      )::numeric                                             AS vl_accumulated,

      GREATEST(
        COALESCE(vl.earned_days, 0)
          - COALESCE(vl.used_days, 0)
          + COALESCE(vl.adjusted_days, 0)
          - COALESCE(vl.pending_days, 0),
        0
      )::numeric                                             AS vl_available,

      /* Already-deducted entry for this year */
      ded.id                                                 AS deduction_ledger_id,
      ABS(ded.days_changed)::numeric                         AS deducted_days,
      ded.created_at                                         AS deducted_at,
      ded.remarks                                            AS deduction_remarks

    FROM users u

    /* Current department (latest active assignment) */
    LEFT JOIN LATERAL (
      SELECT d.name AS current_department_name
      FROM   assignments a
      LEFT JOIN departments d ON d.id = a.department_id
      WHERE  a.employee_id = u.id
        AND  (a.is_active IS NULL OR a.is_active = true)
        AND  a.effective_from <= CURRENT_DATE
        AND  (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
      ORDER BY a.effective_from DESC
      LIMIT 1
    ) cur ON true

    /* Qualifying approved mandatory/forced leave and vacation leave */
    LEFT JOIN (
      SELECT
        COALESCE(lr.user_id, lr.employee_id) AS uid,
        COALESCE(SUM(COALESCE(lr.number_of_days, lr.total_days, 0)), 0) AS forced_days
      FROM   leave_requests lr
      JOIN   leave_types lt ON lt.id = lr.leave_type_id
      WHERE  lt.name IN ('mandatoryForcedLeave', 'vacationLeave')
        AND  lr.status = 'approved'
        AND  EXTRACT(YEAR FROM lr.start_date) = $1::int
      GROUP BY COALESCE(lr.user_id, lr.employee_id)
    ) fl ON fl.uid = u.id

    /* Current VL balance row */
    LEFT JOIN leave_balances vl
      ON vl.user_id = u.id AND vl.leave_type = 'vacationLeave'

    /* Existing year-end deduction ledger entry for this year */
    LEFT JOIN LATERAL (
      SELECT lbl.id, lbl.days_changed, lbl.created_at, lbl.remarks
      FROM   leave_balance_ledger lbl
      WHERE  lbl.user_id = u.id
        AND  lbl.leave_type = 'vacationLeave'
        AND  lbl.action = 'forced_leave_deduction'
        AND  (
          lbl.metadata_json->>'year' = $1::text
          OR lbl.metadata_json->>'deduction_year' = $1::text
        )
      ORDER BY lbl.created_at DESC
      LIMIT 1
    ) ded ON true

    WHERE (u.is_active IS NULL OR u.is_active = true)
    ORDER BY u.full_name ASC
    `,
    [yearStr],
  );

  const employees = rows.map((r) => {
    const forcedUsed = parseFloat(r.forced_leave_days_used || 0);
    const vlAccumulated = parseFloat(r.vl_accumulated || 0);
    const vlAvailable = parseFloat(r.vl_available || 0);
    const alreadyDeducted = !!r.deduction_ledger_id;
    const shortfall = alreadyDeducted
      ? 0
      : parseFloat(Math.max(0, REQUIRED_FORCED_DAYS - forcedUsed).toFixed(4));
    // Employees below ten accumulated VL credits are optional under Section
    // 25 and must not be included in automatic bulk deductions. Monetization
    // exceptions require HR review because that history is not yet stored.
    const eligible = vlAccumulated >= 10;
    const actualDeduction = alreadyDeducted || !eligible || !yearClosed
      ? 0
      : parseFloat(Math.min(shortfall, vlAvailable).toFixed(4));
    const unresolvedShortfall = parseFloat(
      Math.max(0, shortfall - actualDeduction).toFixed(4),
    );

    let status;
    if (alreadyDeducted) status = 'deducted';
    else if (forcedUsed >= REQUIRED_FORCED_DAYS) status = 'compliant';
    else if (!eligible) status = 'optional_below_threshold';
    else if (!yearClosed) status = 'monitoring';
    else if (actualDeduction <= 0) status = 'insufficient_balance';
    else if (actualDeduction < shortfall) status = 'partial';
    else status = 'pending';

    return {
      user_id: r.user_id,
      employee_number: r.employee_number || null,
      full_name: r.full_name,
      current_department_name: r.current_department_name || null,
      forced_leave_days_used: forcedUsed,
      required_days: REQUIRED_FORCED_DAYS,
      suggested_deduction: shortfall,
      actual_deduction: actualDeduction,
      unresolved_shortfall: unresolvedShortfall,
      vl_available: vlAvailable,
      vl_accumulated: vlAccumulated,
      eligible,
      eligibility_status: eligible ? 'required' : 'optional_below_threshold',
      eligibility_reason: eligible
        ? 'At least 10 VL credits at assessment'
        : 'Below 10 VL credits; forced leave is optional and requires HR review',
      already_deducted: alreadyDeducted,
      deducted_days: alreadyDeducted ? parseFloat(r.deducted_days || 0) : null,
      deducted_at: r.deducted_at || null,
      deduction_remarks: r.deduction_remarks || null,
      can_apply: yearClosed && !alreadyDeducted && eligible && actualDeduction > 0,
      status,
    };
  });

  const summary = {
    total: employees.length,
    compliant: employees.filter((e) => e.status === 'compliant').length,
    pending_deduction: employees.filter((e) => e.status === 'pending').length,
    monitoring: employees.filter((e) => e.status === 'monitoring').length,
    partial: employees.filter((e) => e.status === 'partial').length,
    optional_review: employees.filter((e) => e.status === 'optional_below_threshold').length,
    insufficient_balance: employees.filter((e) => e.status === 'insufficient_balance').length,
    already_deducted: employees.filter((e) => e.status === 'deducted').length,
  };

  return {
    year,
    year_closed: yearClosed,
    required_days: REQUIRED_FORCED_DAYS,
    employees,
    summary,
  };
}

// ---------------------------------------------------------------------------
// Bulk apply (or dry-run)
// ---------------------------------------------------------------------------

/**
 * Apply year-end forced leave deductions for all eligible employees (or a
 * subset). Idempotent: already-deducted employees are skipped gracefully.
 *
 * @param {import('pg').Pool} pool
 * @param {{
 *   year: number,
 *   actorUserId?: string,
 *   dryRun?: boolean,
 *   employeeIds?: string[],
 *   remarks?: string,
 * }} options
 */
async function applyYearEndForcedLeaveDeductions(pool, {
  year,
  actorUserId = null,
  dryRun = false,
  employeeIds = null,
  remarks = null,
}) {
  const compliance = await getYearEndForcedLeaveCompliance(pool, { year });

  const filterIds = employeeIds && employeeIds.length > 0
    ? new Set(employeeIds)
    : null;

  const targets = compliance.employees.filter(
    (e) => e.can_apply && (!filterIds || filterIds.has(e.user_id)),
  );

  const skippedDeducted = compliance.employees
    .filter((e) => e.status === 'deducted' && (!filterIds || filterIds.has(e.user_id)))
    .map((e) => ({
      user_id: e.user_id,
      employee_number: e.employee_number,
      full_name: e.full_name,
      current_department_name: e.current_department_name,
      forced_leave_days_used: e.forced_leave_days_used,
      days_to_deduct: 0,
      vl_available: e.vl_available,
      vl_sufficient: null,
      apply_status: 'already_deducted',
      error: null,
      applied_at: e.deducted_at,
    }));

  const skippedCompliant = compliance.employees
    .filter((e) => e.status === 'compliant' && (!filterIds || filterIds.has(e.user_id)))
    .map((e) => ({
      user_id: e.user_id,
      employee_number: e.employee_number,
      full_name: e.full_name,
      current_department_name: e.current_department_name,
      forced_leave_days_used: e.forced_leave_days_used,
      days_to_deduct: 0,
      vl_available: e.vl_available,
      vl_sufficient: null,
      apply_status: 'compliant',
      error: null,
      applied_at: null,
    }));

  // --- Dry-run: return preview without writing anything ---
  if (dryRun) {
    const preview = targets.map((emp) => ({
      user_id: emp.user_id,
      employee_number: emp.employee_number,
      full_name: emp.full_name,
      current_department_name: emp.current_department_name,
      forced_leave_days_used: emp.forced_leave_days_used,
      days_to_deduct: emp.actual_deduction,
      vl_available: emp.vl_available,
      vl_sufficient: emp.actual_deduction >= emp.suggested_deduction,
      apply_status: emp.actual_deduction < emp.suggested_deduction
        ? 'would_partially_apply'
        : 'would_apply',
      error: null,
      applied_at: null,
    }));

    return {
      dry_run: true,
      year,
      summary: {
        total_eligible: preview.length,
        would_apply: preview.length,
        already_deducted: skippedDeducted.length,
        compliant: skippedCompliant.length,
        insufficient_balance: preview.filter((r) => !r.vl_sufficient).length,
      },
      results: [...preview, ...skippedDeducted, ...skippedCompliant],
    };
  }

  // --- Live apply ---
  const yearStr = String(year);
  const appliedResults = [];

  for (const emp of targets) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Race-condition duplicate guard
      const dupQ = await client.query(
        `SELECT id FROM leave_balance_ledger
         WHERE  user_id = $1::uuid
           AND  leave_type = 'vacationLeave'
           AND  action = 'forced_leave_deduction'
           AND  (
             metadata_json->>'year' = $2
             OR metadata_json->>'deduction_year' = $2
           )
         LIMIT 1`,
        [emp.user_id, yearStr],
      );
      if (dupQ.rows.length > 0) {
        await client.query('ROLLBACK');
        appliedResults.push({
          user_id: emp.user_id, employee_number: emp.employee_number,
          full_name: emp.full_name, current_department_name: emp.current_department_name,
          forced_leave_days_used: emp.forced_leave_days_used,
          days_to_deduct: 0, vl_available: emp.vl_available, vl_sufficient: null,
          apply_status: 'already_deducted', error: null, applied_at: null,
        });
        continue;
      }

      // Lock the VL balance row and read current values
      const balQ = await client.query(
        `SELECT earned_days, used_days, pending_days, adjusted_days
         FROM   leave_balances
         WHERE  user_id = $1::uuid AND leave_type = 'vacationLeave'
         LIMIT  1 FOR UPDATE`,
        [emp.user_id],
      );
      const bal = balQ.rows[0] || null;
      const vlRemaining = bal
        ? parseFloat(bal.earned_days || 0)
          - parseFloat(bal.used_days || 0)
          + parseFloat(bal.adjusted_days || 0)
          - parseFloat(bal.pending_days || 0)
        : 0;
      const beforeUsed = bal ? parseFloat(bal.used_days || 0) : 0;

      // Cap deduction at available remaining balance (no negatives)
      const daysToDeduct = parseFloat(
        Math.min(emp.suggested_deduction, Math.max(0, vlRemaining)).toFixed(4),
      );

      if (daysToDeduct <= 0) {
        await client.query('ROLLBACK');
        appliedResults.push({
          user_id: emp.user_id, employee_number: emp.employee_number,
          full_name: emp.full_name, current_department_name: emp.current_department_name,
          forced_leave_days_used: emp.forced_leave_days_used,
          days_to_deduct: emp.suggested_deduction, vl_available: emp.vl_available,
          vl_sufficient: false,
          apply_status: 'insufficient_balance',
          error: 'No VL balance available for deduction',
          applied_at: null,
        });
        continue;
      }

      // Increment used_days
      await client.query(
        `INSERT INTO leave_balances
           (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days,
            as_of_date, last_accrual_date, created_at, updated_at)
         VALUES ($1::uuid, 'vacationLeave', 0, $2::numeric, 0, 0,
                 now()::date, now()::date, now(), now())
         ON CONFLICT (user_id, leave_type)
         DO UPDATE SET used_days  = COALESCE(leave_balances.used_days, 0) + EXCLUDED.used_days,
                       updated_at = now()`,
        [emp.user_id, daysToDeduct],
      );

      const afterUsed = beforeUsed + daysToDeduct;

      // Write ledger entry
      await insertLeaveBalanceLedger(client, {
        userId: emp.user_id,
        leaveType: 'vacationLeave',
        action: 'forced_leave_deduction',
        affectedBucket: 'used',
        daysChanged: afterUsed - beforeUsed,
        oldValue: beforeUsed,
        newValue: afterUsed,
        actorUserId: actorUserId || null,
        actorKind: actorUserId ? 'admin' : 'system',
        remarks: remarks || null,
        metadataJson: {
          source: actorUserId ? 'year_end_bulk_deduction' : 'year_end_auto_deduction',
          year,
          deduction_year: year,
          requested_leave_type: 'mandatoryForcedLeave',
          deducted_days: daysToDeduct,
          forced_leave_days_used: emp.forced_leave_days_used,
          required_days: REQUIRED_FORCED_DAYS,
        },
      });

      await client.query('COMMIT');
      const fullySatisfied = daysToDeduct >= emp.suggested_deduction;
      appliedResults.push({
        user_id: emp.user_id, employee_number: emp.employee_number,
        full_name: emp.full_name, current_department_name: emp.current_department_name,
        forced_leave_days_used: emp.forced_leave_days_used,
        days_to_deduct: daysToDeduct, vl_available: emp.vl_available,
        vl_sufficient: fullySatisfied,
        apply_status: fullySatisfied ? 'applied' : 'partially_applied',
        error: null, applied_at: new Date().toISOString(),
      });
    } catch (err) {
      try { await client.query('ROLLBACK'); } catch (_) { /* ignore */ }
      appliedResults.push({
        user_id: emp.user_id, employee_number: emp.employee_number,
        full_name: emp.full_name, current_department_name: emp.current_department_name,
        forced_leave_days_used: emp.forced_leave_days_used,
        days_to_deduct: emp.suggested_deduction, vl_available: emp.vl_available,
        vl_sufficient: null,
        apply_status: 'error',
        error: err.message || 'Unknown error',
        applied_at: null,
      });
    } finally {
      client.release();
    }
  }

  return {
    dry_run: false,
    year,
    summary: {
      total_eligible: targets.length,
      applied: appliedResults.filter((r) => r.apply_status === 'applied').length,
      partially_applied: appliedResults.filter((r) => r.apply_status === 'partially_applied').length,
      already_deducted: appliedResults.filter((r) => r.apply_status === 'already_deducted').length + skippedDeducted.length,
      insufficient_balance: appliedResults.filter((r) => r.apply_status === 'insufficient_balance').length,
      errors: appliedResults.filter((r) => r.apply_status === 'error').length,
      compliant: skippedCompliant.length,
    },
    results: [...appliedResults, ...skippedDeducted, ...skippedCompliant],
  };
}

module.exports = {
  getYearEndForcedLeaveCompliance,
  applyYearEndForcedLeaveDeductions,
  manilaYearNow,
  REQUIRED_FORCED_DAYS,
  CRON_ADVISORY_LOCK_KEY,
};
