/**
 * Monthly earned-days accrual for Vacation and Sick leave.
 *
 * Enhancements over v1:
 *  1. Employment status filtering  — resigned / retired / terminated employees are excluded.
 *  2. Hire date backfill           — when last_accrual_date IS NULL and maxCatchUpMonths > 1,
 *                                    months are counted from date_hired (not always just 1).
 *  3. Catch-up hire-month proration— hire month is prorated even in a multi-month backfill.
 *  4. Annual balance cap           — accrual_annual_cap on leave_types limits the remaining
 *                                    balance (earned - used + adjusted). Accrual stops when cap
 *                                    is reached; resumes after leave is used.
 *  5. Separation date proration    — employees with users.separation_date in the target month
 *                                    receive a prorated final month instead of the full rate.
 *  6. DB-driven accrual rates      — leave_types.accrues_monthly / accrual_monthly_rate
 *                                    drive which types accrue and at what rate. Falls back to
 *                                    hardcoded 1.25 if migration has not yet been run.
 *  7. Missing date_hired warning   — details entry carries missing_hire_date: true so HR can
 *                                    review; credits still proceed at the full rate.
 *  8. last_accrual_date edit guard — enforced in the PUT /balances/:userId route (see
 *                                    leaveRoutes.js); not this file.
 *  9. Eligibility gate             — only leave_credit_eligible users with an active assignment
 *                                    overlapping the target month receive monthly credits.
 *
 * @module services/leaveMonthlyAccrual
 */

const {
  insertLeaveBalanceLedger,
  initLeaveBalanceLedger,
} = require('./leaveBalanceLedger');

// ─── Constants ───────────────────────────────────────────────────────────────

/** Fallback used when leave_types accrual columns are not yet migrated. */
const HARDCODED_ACCRUAL_CONFIGS = [
  { name: 'vacationLeave', monthly_rate: 1.25, accrual_annual_cap: null },
  { name: 'sickLeave',     monthly_rate: 1.25, accrual_annual_cap: null },
];

/** @deprecated Use DB-driven config. Kept for backwards-compat module exports. */
const ACCRUAL_LEAVE_TYPES = ['vacationLeave', 'sickLeave'];

/** Default monthly rate; used as SQL fallback when accrual_monthly_rate IS NULL. */
const DAYS_PER_MONTH = 1.25;

// ─── Date utilities ──────────────────────────────────────────────────────────

function startOfMonth(d) {
  const x = new Date(d.getTime());
  x.setDate(1);
  x.setHours(0, 0, 0, 0);
  return x;
}

function addMonths(d, n) {
  const x = new Date(d.getTime());
  x.setMonth(x.getMonth() + n);
  return x;
}

/** Compare calendar months (year + month only). */
function monthKey(t) {
  return t.getFullYear() * 12 + t.getMonth();
}

function toDateStr(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isValidDate(d) {
  return d instanceof Date && !Number.isNaN(d.getTime());
}

/** Round to 2 decimal places (policy for earned days). */
function round2(n) {
  return Math.round(Number(n) * 100) / 100;
}

/** Calendar days in month (handles Feb 28/29). */
function daysInCalendarMonth(year, monthIndex) {
  return new Date(year, monthIndex + 1, 0).getDate();
}

/**
 * Parse DB `date` / ISO string to local calendar date (avoid UTC off-by-one).
 * @param {Date|string|null|undefined} input
 * @returns {Date|null}
 */
function parseDateOnly(input) {
  if (input == null) return null;
  if (input instanceof Date) {
    if (Number.isNaN(input.getTime())) return null;
    return new Date(input.getFullYear(), input.getMonth(), input.getDate());
  }
  const s = String(input).trim().slice(0, 10);
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  if (!m) return null;
  const y = parseInt(m[1], 10);
  const mo = parseInt(m[2], 10) - 1;
  const d = parseInt(m[3], 10);
  const dt = new Date(y, mo, d);
  if (dt.getFullYear() !== y || dt.getMonth() !== mo || dt.getDate() !== d) return null;
  return dt;
}

function parseTargetMonth(input) {
  if (input == null) return startOfMonth(new Date());
  if (typeof input === 'string') {
    const m = /^(\d{4})-(\d{2})$/.exec(input.trim());
    if (!m) {
      throw new Error('targetMonth must be YYYY-MM');
    }
    const year = parseInt(m[1], 10);
    const month = parseInt(m[2], 10);
    if (month < 1 || month > 12) {
      throw new Error('targetMonth month must be between 01 and 12');
    }
    return new Date(year, month - 1, 1);
  }
  const parsed = startOfMonth(new Date(input));
  if (!isValidDate(parsed)) {
    throw new Error('targetMonth must be a valid date or YYYY-MM');
  }
  return parsed;
}

function endOfMonth(d) {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0);
}

async function ensureLeaveCreditEligibilityColumn(db) {
  await db.query(
    `ALTER TABLE users
       ADD COLUMN IF NOT EXISTS leave_credit_eligible BOOLEAN NOT NULL DEFAULT true`
  );
  await db.query(
    `CREATE INDEX IF NOT EXISTS idx_users_leave_credit_eligible
       ON users (leave_credit_eligible)
       WHERE leave_credit_eligible = true`
  );
}

function activeAssignmentExistsSql(userAlias, targetStartParam, targetEndParam) {
  return `EXISTS (
    SELECT 1
    FROM assignments a
    WHERE a.employee_id = ${userAlias}.id
      AND (a.is_active IS NULL OR a.is_active = true)
      AND (a.effective_from IS NULL OR a.effective_from <= ${targetEndParam}::date)
      AND (a.effective_to IS NULL OR a.effective_to >= ${targetStartParam}::date)
  )`;
}

function monthStartInTimeZone(input = new Date(), timeZone = 'Asia/Manila') {
  const d = input instanceof Date ? input : new Date(input);
  if (!isValidDate(d)) {
    throw new Error('now must be a valid date');
  }
  let fmt;
  try {
    fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
    });
  } catch (_) {
    throw new Error('timeZone must be a valid IANA time zone');
  }
  const parts = fmt.formatToParts(d);
  const year = parts.find((p) => p.type === 'year')?.value;
  const month = parts.find((p) => p.type === 'month')?.value;
  if (!year || !month) {
    throw new Error('Could not resolve current accrual month');
  }
  return parseTargetMonth(`${year}-${month}`);
}

// ─── DB-driven leave type config ─────────────────────────────────────────────

/**
 * Read accrual leave type configuration from leave_types (DB-driven, Enhancement 6).
 * Falls back to HARDCODED_ACCRUAL_CONFIGS when accrues_monthly column is not yet present
 * (i.e., the 20260626_accrual_enhancements.sql migration has not been run).
 *
 * @param {import('pg').Pool} pgPool
 * @returns {Promise<Array<{name: string, monthly_rate: number, accrual_annual_cap: number|null}>>}
 */
async function readAccrualLeaveTypeConfigs(pgPool) {
  try {
    const { rows } = await pgPool.query(
      `SELECT name,
              COALESCE(accrual_monthly_rate, $1::numeric) AS monthly_rate,
              accrual_annual_cap
       FROM leave_types
       WHERE accrues_monthly = true
         AND is_active = true
       ORDER BY name`,
      [DAYS_PER_MONTH]
    );
    if (rows.length > 0) {
      return rows.map((r) => ({
        name: r.name,
        monthly_rate: parseFloat(r.monthly_rate),
        accrual_annual_cap: r.accrual_annual_cap != null ? parseFloat(r.accrual_annual_cap) : null,
      }));
    }
  } catch (_) {
    // accrues_monthly column not yet added — fall back to hardcoded
  }
  return HARDCODED_ACCRUAL_CONFIGS.map((c) => ({ ...c }));
}

// ─── Month counting ──────────────────────────────────────────────────────────

/**
 * How many consecutive months from the first due month through targetMonthStart (inclusive)
 * to credit, capped at maxCatchUpMonths. Returns 0 if already up to date.
 *
 * Enhancement 2 — Hire date backfill:
 *   When lastAccrualDate is null and dateHired is provided, the sequence starts from the
 *   hire month instead of just crediting the one target month. This allows a single admin
 *   run with a high maxCatchUpMonths to fully backfill from hire date.
 *   Without a hire date, falls back to crediting exactly 1 month (original behavior).
 *
 * @param {Date|null} lastAccrualDate
 * @param {Date} targetMonthStart
 * @param {number} maxCatchUpMonths
 * @param {Date|string|null} [dateHired]
 * @returns {number}
 */
function countMonthsToCredit(lastAccrualDate, targetMonthStart, maxCatchUpMonths, dateHired) {
  const cap = Math.max(0, Math.min(120, parseInt(maxCatchUpMonths, 10) || 1));
  if (cap === 0) return 0;

  const target = startOfMonth(targetMonthStart);

  if (!lastAccrualDate) {
    if (dateHired) {
      const hire = parseDateOnly(dateHired);
      if (hire) {
        const hireMonthStart = startOfMonth(hire);
        if (monthKey(hireMonthStart) > monthKey(target)) {
          return 0; // hired after target month — nothing to credit yet
        }
        let count = 0;
        let cursor = hireMonthStart;
        while (monthKey(cursor) <= monthKey(target) && count < cap) {
          count += 1;
          cursor = addMonths(cursor, 1);
        }
        return count;
      }
    }
    // No hire date: credit exactly 1 month (backward-compatible)
    return Math.min(1, cap);
  }

  const lastStart = startOfMonth(lastAccrualDate);
  if (monthKey(lastStart) >= monthKey(target)) {
    return 0;
  }

  let count = 0;
  let cursor = addMonths(lastStart, 1);
  while (monthKey(cursor) <= monthKey(target) && count < cap) {
    count += 1;
    cursor = addMonths(cursor, 1);
  }
  return count;
}

/** Last calendar month start in the credited sequence (first month + (n-1) months). */
function lastCreditedMonthStart(firstMonthStart, monthsCredited) {
  if (monthsCredited <= 0) return null;
  return addMonths(startOfMonth(firstMonthStart), monthsCredited - 1);
}

// ─── Proration helpers ───────────────────────────────────────────────────────

/**
 * Amount for the first month of a new accrual sequence, applying hire-date proration.
 * Used for:
 *   (a) A single-month first accrual, and
 *   (b) The first month of a multi-month backfill (Enhancement 3).
 *
 * @returns {{ addDays, skipped, prorated, reason?, days_worked?, days_in_month? }}
 */
function firstMonthAccrualAmount(targetMonthStart, dateHiredRaw, daysPerMonth) {
  const target = startOfMonth(targetMonthStart);
  const y = target.getFullYear();
  const m = target.getMonth();
  const dim = daysInCalendarMonth(y, m);

  const hire = parseDateOnly(dateHiredRaw);
  if (!hire) {
    return {
      addDays: round2(daysPerMonth),
      skipped: false,
      prorated: false,
      reason: 'no_hire_date_full_rate',
    };
  }

  const hireMonthStart = startOfMonth(hire);

  if (monthKey(hireMonthStart) > monthKey(target)) {
    return { addDays: 0, skipped: true, reason: 'hired_after_target_month', prorated: false };
  }

  if (monthKey(hireMonthStart) < monthKey(target)) {
    return { addDays: round2(daysPerMonth), skipped: false, prorated: false };
  }

  // Same calendar month as target
  if (hire.getDate() === 1) {
    return { addDays: round2(daysPerMonth), skipped: false, prorated: false };
  }

  // Hired mid-month (day 2..last): prorate
  const daysWorked = dim - hire.getDate() + 1;
  if (daysWorked < 1) {
    return { addDays: 0, skipped: true, reason: 'invalid_hire_day', prorated: false };
  }
  const addDays = Math.max(0, round2((daysWorked / dim) * daysPerMonth));
  return {
    addDays,
    skipped: false,
    prorated: true,
    days_worked: daysWorked,
    days_in_month: dim,
  };
}

/**
 * Enhancement 5 — Prorate the final month of employment based on separation date.
 * Returns the amount to credit for the last month (days 1 through separation day, inclusive).
 *
 * @param {Date|string} separationDate
 * @param {Date} lastMonthStart   - The first day of the final credited month.
 * @param {number} daysPerMonth
 * @returns {{ addDays, prorated, days_worked?, days_in_month? }}
 */
function separationMonthAccrualAmount(separationDate, lastMonthStart, daysPerMonth) {
  const sep = parseDateOnly(separationDate);
  if (!sep) {
    return { addDays: round2(daysPerMonth), prorated: false };
  }
  const target = startOfMonth(lastMonthStart);
  const y = target.getFullYear();
  const m = target.getMonth();
  const dim = daysInCalendarMonth(y, m);

  // Days worked = 1st through last day worked (separation day), inclusive
  const daysWorked = Math.max(0, Math.min(sep.getDate(), dim));
  if (daysWorked === 0) {
    return { addDays: 0, prorated: true, days_worked: 0, days_in_month: dim };
  }
  if (daysWorked >= dim) {
    // Worked the full month — no proration needed
    return { addDays: round2(daysPerMonth), prorated: false };
  }
  const addDays = round2((daysWorked / dim) * daysPerMonth);
  return { addDays, prorated: true, days_worked: daysWorked, days_in_month: dim };
}

// ─── Main accrual function ───────────────────────────────────────────────────

/**
 * @param {import('pg').Pool} pgPool
 * @param {object} [options]
 * @param {Date|string} [options.targetMonth]       - Defaults to current Asia/Manila month.
 * @param {number}      [options.maxCatchUpMonths=1] - Max months to credit per row per run.
 * @param {boolean}     [options.dryRun=false]
 * @param {boolean}     [options.allowFutureTargetMonth=false]
 * @param {Date|string} [options.now]               - Testing hook for current month guard.
 * @param {string}      [options.timeZone='Asia/Manila']
 * @returns {Promise<{
 *   targetYearMonth: string, rate: number, leaveTypes: string[], dryRun: boolean,
 *   rowsUpdated: number, rowsSkipped: number, details: Array<object>
 * }>}
 */
async function runLeaveMonthlyAccrual(pgPool, options = {}) {
  const dryRun = options.dryRun === true;
  const maxCatchUpMonths = options.maxCatchUpMonths != null ? options.maxCatchUpMonths : 1;
  const allowFutureTargetMonth = options.allowFutureTargetMonth === true;
  const accrualTimeZone = options.timeZone || 'Asia/Manila';
  const nowMonth = monthStartInTimeZone(
    options.now != null ? options.now : new Date(),
    accrualTimeZone
  );
  const targetMonth = options.targetMonth == null
    ? nowMonth
    : parseTargetMonth(options.targetMonth);

  if (!allowFutureTargetMonth && monthKey(targetMonth) > monthKey(nowMonth)) {
    throw new Error('targetMonth cannot be in the future');
  }

  const targetYearMonth = `${targetMonth.getFullYear()}-${String(targetMonth.getMonth() + 1).padStart(2, '0')}`;
  const targetMonthStartStr = toDateStr(targetMonth);
  const targetMonthEndStr = toDateStr(endOfMonth(targetMonth));

  // Enhancement 6: Read DB-driven leave type configs (falls back to hardcoded pre-migration)
  const leaveTypeConfigs = await readAccrualLeaveTypeConfigs(pgPool);
  const leaveTypeConfigMap = new Map(leaveTypeConfigs.map((c) => [c.name, c]));
  const accrualLeaveTypes = leaveTypeConfigs.map((c) => c.name);

  initLeaveBalanceLedger(pgPool);
  await ensureLeaveCreditEligibilityColumn(pgPool);

  const client = await pgPool.connect();
  const details = [];
  let rowsUpdated = 0;
  let rowsSkipped = 0;

  try {
    if (!dryRun) {
      await client.query('BEGIN');
    }

    // ── Find employees missing balance rows ───────────────────────────────────
    // Enhancement 1: exclude employees whose employment_status is resigned/retired/terminated
    const missingBalanceResult = await client.query(
      `SELECT u.id AS user_id, u.full_name, u.date_hired,
              u.employment_type, u.employment_status, u.separation_date,
              u.leave_credit_eligible, t.leave_type
       FROM users u
       CROSS JOIN unnest($1::text[]) AS t(leave_type)
       LEFT JOIN leave_balances lb
         ON lb.user_id = u.id
        AND lb.leave_type = t.leave_type
       WHERE (u.is_active IS NULL OR u.is_active = true)
         AND u.leave_credit_eligible = true
         AND (u.employment_status IS NULL
              OR u.employment_status NOT IN ('resigned', 'retired', 'terminated'))
         AND ${activeAssignmentExistsSql('u', '$2', '$3')}
         AND lb.id IS NULL`,
      [accrualLeaveTypes, targetMonthStartStr, targetMonthEndStr]
    );
    const missingBalanceKeys = new Set(
      missingBalanceResult.rows.map((row) => `${row.user_id}|${row.leave_type}`)
    );

    if (!dryRun && missingBalanceResult.rows.length > 0) {
      await client.query(
        `INSERT INTO leave_balances (
           user_id, leave_type, earned_days, used_days, pending_days,
           adjusted_days, as_of_date, created_at, updated_at
         )
         SELECT u.id, t.leave_type, 0, 0, 0, 0, CURRENT_DATE, now(), now()
         FROM users u
         CROSS JOIN unnest($1::text[]) AS t(leave_type)
         LEFT JOIN leave_balances lb
           ON lb.user_id = u.id
          AND lb.leave_type = t.leave_type
         WHERE (u.is_active IS NULL OR u.is_active = true)
           AND u.leave_credit_eligible = true
           AND (u.employment_status IS NULL
                OR u.employment_status NOT IN ('resigned', 'retired', 'terminated'))
           AND ${activeAssignmentExistsSql('u', '$2', '$3')}
           AND lb.id IS NULL
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [accrualLeaveTypes, targetMonthStartStr, targetMonthEndStr]
      );
    }

    // ── Fetch balance rows for active, non-separated employees ───────────────
    // Enhancement 1: employment_status filter
    // Enhancement 4: fetch used_days, adjusted_days for annual cap check
    // Enhancement 5: fetch separation_date for final-month proration
    // The separation_date column is added by migration 20260626_accrual_enhancements.sql.
    // If the column is missing (pre-migration), we retry without it for graceful degradation.
    let rows;
    try {
      ({ rows } = await client.query(
        `SELECT lb.id, lb.user_id, lb.leave_type,
                lb.earned_days, lb.used_days, lb.adjusted_days,
                lb.last_accrual_date,
                u.full_name, u.date_hired, u.employment_type,
                u.employment_status, u.separation_date,
                u.leave_credit_eligible
         FROM leave_balances lb
         INNER JOIN users u ON u.id = lb.user_id
         WHERE lb.leave_type = ANY($1::text[])
           AND (u.is_active IS NULL OR u.is_active = true)
           AND u.leave_credit_eligible = true
           AND (u.employment_status IS NULL
                OR u.employment_status NOT IN ('resigned', 'retired', 'terminated'))
           AND ${activeAssignmentExistsSql('u', '$2', '$3')}`,
        [accrualLeaveTypes, targetMonthStartStr, targetMonthEndStr]
      ));
    } catch (colErr) {
      if (colErr.code === '42703') {
        // separation_date column not yet added — degrade gracefully
        ({ rows } = await client.query(
          `SELECT lb.id, lb.user_id, lb.leave_type,
                  lb.earned_days, lb.used_days, lb.adjusted_days,
                  lb.last_accrual_date,
                  u.full_name, u.date_hired, u.employment_type, u.employment_status,
                  u.leave_credit_eligible
           FROM leave_balances lb
           INNER JOIN users u ON u.id = lb.user_id
           WHERE lb.leave_type = ANY($1::text[])
             AND (u.is_active IS NULL OR u.is_active = true)
             AND u.leave_credit_eligible = true
             AND (u.employment_status IS NULL
                  OR u.employment_status NOT IN ('resigned', 'retired', 'terminated'))
             AND ${activeAssignmentExistsSql('u', '$2', '$3')}`,
          [accrualLeaveTypes, targetMonthStartStr, targetMonthEndStr]
        ));
      } else {
        throw colErr;
      }
    }

    // Merge in dry-run synthetic rows for employees with no balance yet
    if (dryRun && missingBalanceResult.rows.length > 0) {
      rows.push(
        ...missingBalanceResult.rows.map((row) => ({
          id: null,
          user_id: row.user_id,
          leave_type: row.leave_type,
          earned_days: 0,
          used_days: 0,
          adjusted_days: 0,
          last_accrual_date: null,
          full_name: row.full_name,
          date_hired: row.date_hired,
          employment_type: row.employment_type,
          employment_status: row.employment_status,
          leave_credit_eligible: row.leave_credit_eligible !== false,
          separation_date: row.separation_date ?? null,
        }))
      );
    }

    // ── Per-row accrual loop ──────────────────────────────────────────────────
    for (const row of rows) {
      // Enhancement 6: use DB-driven rate; fall back to 1.25
      const config = leaveTypeConfigMap.get(row.leave_type)
        || { monthly_rate: DAYS_PER_MONTH, accrual_annual_cap: null };
      const rate = config.monthly_rate;

      const createdBalanceRow = missingBalanceKeys.has(`${row.user_id}|${row.leave_type}`);
      const lastAccrual = row.last_accrual_date ? new Date(row.last_accrual_date) : null;

      // Enhancement 2: pass dateHired for hire date backfill
      const months = countMonthsToCredit(lastAccrual, targetMonth, maxCatchUpMonths, row.date_hired);

      if (months <= 0) {
        rowsSkipped += 1;
        let reason = 'no_months_due';
        if (lastAccrual && monthKey(startOfMonth(lastAccrual)) >= monthKey(targetMonth)) {
          reason = 'already_credited_through_target_month';
        } else if (maxCatchUpMonths <= 0) {
          reason = 'max_catch_up_months_is_zero';
        } else if (!lastAccrual) {
          reason = 'hired_after_target_month';
        }
        details.push({
          user_id: row.user_id,
          employee_name: row.full_name,
          leave_type: row.leave_type,
          action: 'skipped',
          reason,
          created_balance_row: createdBalanceRow,
        });
        continue;
      }

      // First month in the credited sequence
      let firstMonthStart;
      if (!lastAccrual) {
        // Enhancement 2: backfill starts from hire month if available
        const hire = parseDateOnly(row.date_hired);
        firstMonthStart = hire ? startOfMonth(hire) : targetMonth;
      } else {
        firstMonthStart = addMonths(startOfMonth(lastAccrual), 1);
      }

      const lastMonthStart = lastCreditedMonthStart(firstMonthStart, months);
      const lastAccrualStr = toDateStr(lastMonthStart);

      // Enhancement 7 (missing hire date): flag it but still credit
      const missingHireDate = !row.date_hired;

      let addDays;
      let firstMonthInfo = null;

      if (!lastAccrual) {
        // First ever accrual — apply hire-date proration to the hire/first month
        firstMonthInfo = firstMonthAccrualAmount(firstMonthStart, row.date_hired, rate);
        if (firstMonthInfo.skipped) {
          rowsSkipped += 1;
          details.push({
            user_id: row.user_id,
            employee_name: row.full_name,
            leave_type: row.leave_type,
            action: 'skipped',
            reason: firstMonthInfo.reason || 'first_month_skip',
            created_balance_row: createdBalanceRow,
          });
          continue;
        }

        if (months === 1) {
          // Single month: standard proration (unchanged from v1)
          addDays = firstMonthInfo.addDays;
        } else {
          // Enhancement 3: multi-month backfill — hire month prorated, rest full
          addDays = round2(firstMonthInfo.addDays + (months - 1) * rate);
        }
      } else {
        // Subsequent run (catch-up): full rate for each month
        addDays = round2(months * rate);
      }

      // Enhancement 5: Separation date proration — prorate the last credited month
      let separationProrateInfo = null;
      const sepDate = parseDateOnly(row.separation_date);
      if (sepDate && monthKey(startOfMonth(sepDate)) === monthKey(lastMonthStart)) {
        separationProrateInfo = separationMonthAccrualAmount(sepDate, lastMonthStart, rate);
        // Replace the last full month's credit with the prorated amount
        addDays = Math.max(0, round2(addDays - rate + separationProrateInfo.addDays));
      }

      // Enhancement 4: Annual balance cap — cap earned_days to prevent exceeding max balance
      let capApplied = false;
      if (config.accrual_annual_cap != null) {
        const currentEarned = parseFloat(row.earned_days || 0);
        const currentUsed = parseFloat(row.used_days || 0);
        const currentAdjusted = parseFloat(row.adjusted_days || 0);
        const currentBalance = round2(currentEarned - currentUsed + currentAdjusted);
        const capacityLeft = Math.max(0, round2(config.accrual_annual_cap - currentBalance));
        if (addDays > capacityLeft) {
          addDays = capacityLeft;
          capApplied = true;
        }
      }

      // Skip if nothing to credit after all adjustments
      if (addDays <= 0) {
        rowsSkipped += 1;
        details.push({
          user_id: row.user_id,
          employee_name: row.full_name,
          leave_type: row.leave_type,
          action: 'skipped',
          reason: capApplied ? 'annual_cap_reached' : 'zero_days_to_add',
          months_credited: months,
          last_accrual_date: lastAccrualStr,
          accrual_rate: rate,
          cap_applied: capApplied,
          created_balance_row: createdBalanceRow,
        });
        continue;
      }

      // ── Build shared detail fields ────────────────────────────────────────
      const detailBase = {
        user_id: row.user_id,
        employee_name: row.full_name,
        leave_type: row.leave_type,
        months_credited: months,
        days_added: addDays,
        last_accrual_date: lastAccrualStr,
        created_balance_row: createdBalanceRow,
        accrual_rate: rate,
        hire_prorated: !!(firstMonthInfo && firstMonthInfo.prorated),
        separation_prorated: !!(separationProrateInfo && separationProrateInfo.prorated),
        cap_applied: capApplied,
        missing_hire_date: missingHireDate,
        ...(firstMonthInfo && firstMonthInfo.days_worked != null
          ? { hire_days_worked: firstMonthInfo.days_worked, hire_days_in_month: firstMonthInfo.days_in_month }
          : {}),
        ...(separationProrateInfo && separationProrateInfo.prorated
          ? { separation_days_worked: separationProrateInfo.days_worked, separation_days_in_month: separationProrateInfo.days_in_month }
          : {}),
      };

      if (dryRun) {
        rowsUpdated += 1;
        details.push({ ...detailBase, action: 'would_apply' });
        continue;
      }

      // ── Apply to DB ───────────────────────────────────────────────────────
      const beforeEarned = parseFloat(row.earned_days ?? 0);

      await client.query(
        `UPDATE leave_balances
         SET earned_days = COALESCE(earned_days, 0) + $1::numeric,
             last_accrual_date = $2::date,
             as_of_date = CURRENT_DATE,
             updated_at = now()
         WHERE id = $3::uuid`,
        [addDays, lastAccrualStr, row.id]
      );

      const afterEarned = beforeEarned + addDays;
      const meta = {
        target_year_month: targetYearMonth,
        months_credited: months,
        last_accrual_date: lastAccrualStr,
        accrual_rate: rate,
      };
      if (firstMonthInfo && firstMonthInfo.prorated) {
        meta.hire_date_proration = true;
        meta.hire_days_worked = firstMonthInfo.days_worked;
        meta.hire_days_in_month = firstMonthInfo.days_in_month;
      }
      if (separationProrateInfo && separationProrateInfo.prorated) {
        meta.separation_proration = true;
        meta.separation_days_worked = separationProrateInfo.days_worked;
        meta.separation_days_in_month = separationProrateInfo.days_in_month;
      }
      if (capApplied) meta.annual_cap_applied = true;
      if (missingHireDate) meta.missing_hire_date_warning = true;

      await insertLeaveBalanceLedger(client, {
        userId: row.user_id,
        leaveType: row.leave_type,
        action: 'monthly_accrual',
        affectedBucket: 'earned',
        daysChanged: addDays,
        oldValue: beforeEarned,
        newValue: afterEarned,
        relatedLeaveRequestId: null,
        actorUserId: null,
        actorKind: 'system',
        remarks: `Accrual for ${targetYearMonth}`,
        metadataJson: meta,
      });

      rowsUpdated += 1;
      details.push({ ...detailBase, action: 'applied' });
    }

    if (!dryRun) {
      await client.query('COMMIT');
    }

    return {
      targetYearMonth,
      rate: DAYS_PER_MONTH,
      leaveTypes: accrualLeaveTypes,
      maxCatchUpMonths,
      dryRun,
      rowsUpdated,
      rowsSkipped,
      missingBalanceRowsCreated: dryRun ? 0 : missingBalanceResult.rows.length,
      missingBalanceRowsDetected: missingBalanceResult.rows.length,
      details,
    };
  } catch (e) {
    if (!dryRun) {
      try {
        await client.query('ROLLBACK');
      } catch (_) { /* ignore */ }
    }
    throw e;
  } finally {
    client.release();
  }
}

module.exports = {
  runLeaveMonthlyAccrual,
  ACCRUAL_LEAVE_TYPES,
  DAYS_PER_MONTH,
  /** @internal exported for tests */
  countMonthsToCredit,
  startOfMonth,
  firstMonthAccrualAmount,
  separationMonthAccrualAmount,
  readAccrualLeaveTypeConfigs,
  parseTargetMonth,
  monthStartInTimeZone,
  round2,
};
