/**
 * Monthly earned-days accrual for Vacation and Sick leave (1.25 days / month per type).
 * There is no fixed starting balance: new employees start at earned_days = 0; credits are
 * added only here. Over 12 months, 1.25 × 12 = 15 days (policy “annual” total), not a seed.
 *
 * Uses leave_balances.last_accrual_date as the calendar month key for the last month
 * that was credited (stored as the 1st of that month). Duplicate runs for the same
 * target month are no-ops for rows already credited through that month.
 *
 * **First accrual only (last_accrual_date IS NULL):** Option B hire-date proration when the
 * employee was hired during the target month (not on the 1st). Other first-month cases:
 * full 1.25 if hired before the target month or on the 1st; skip if hired after the target
 * month. Once last_accrual_date is set, later months always use full 1.25 per month (catch-up
 * unchanged).
 *
 * @module services/leaveMonthlyAccrual
 */

const {
  insertLeaveBalanceLedger,
  initLeaveBalanceLedger,
} = require('./leaveBalanceLedger');

const ACCRUAL_LEAVE_TYPES = ['vacationLeave', 'sickLeave'];
const DAYS_PER_MONTH = 1.25;

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

/**
 * How many consecutive months from the first due month through targetMonthStart (inclusive)
 * to credit, capped at maxCatchUpMonths. Returns 0 if already up to date.
 *
 * - If lastAccrualDate is null: first automated run credits exactly one month (target month only).
 * - Otherwise: credit each month after last credited through target, up to the cap.
 */
function countMonthsToCredit(lastAccrualDate, targetMonthStart, maxCatchUpMonths) {
  const cap = Math.max(0, Math.min(120, parseInt(maxCatchUpMonths, 10) || 1));
  if (cap === 0) return 0;

  const target = startOfMonth(targetMonthStart);

  if (!lastAccrualDate) {
    return Math.min(1, cap);
  }

  const lastStart = startOfMonth(lastAccrualDate);
  if (monthKey(lastStart) > monthKey(target)) {
    return 0;
  }
  if (monthKey(lastStart) === monthKey(target)) {
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

function toDateStr(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isValidDate(d) {
  return d instanceof Date && !Number.isNaN(d.getTime());
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
  if (
    dt.getFullYear() !== y ||
    dt.getMonth() !== mo ||
    dt.getDate() !== d
  ) {
    return null;
  }
  return dt;
}

/**
 * First automated accrual only: amount for the single target month using hire date.
 *
 * @returns {{
 *   addDays: number,
 *   skipped: boolean,
 *   reason?: string,
 *   prorated: boolean,
 *   days_worked?: number,
 *   days_in_month?: number,
 * }}
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

  // Case 4 — hired after target month: no accrual for this month
  if (monthKey(hireMonthStart) > monthKey(target)) {
    return {
      addDays: 0,
      skipped: true,
      reason: 'hired_after_target_month',
    };
  }

  // Case 1 — hired before target month: full month
  if (monthKey(hireMonthStart) < monthKey(target)) {
    return {
      addDays: round2(daysPerMonth),
      skipped: false,
      prorated: false,
    };
  }

  // Same calendar month as target
  // Case 2 — hired on 1st: full month
  if (hire.getDate() === 1) {
    return {
      addDays: round2(daysPerMonth),
      skipped: false,
      prorated: false,
    };
  }

  // Case 3 — hired during target month (day 2..last): prorate
  const daysWorked = dim - hire.getDate() + 1;
  if (daysWorked < 1) {
    return {
      addDays: 0,
      skipped: true,
      reason: 'invalid_hire_day',
    };
  }
  const raw = (daysWorked / dim) * daysPerMonth;
  const addDays = Math.max(0, round2(raw));
  return {
    addDays,
    skipped: false,
    prorated: true,
    days_worked: daysWorked,
    days_in_month: dim,
  };
}

/**
 * @param {import('pg').Pool} pgPool
 * @param {object} [options]
 * @param {Date|string} [options.targetMonth] - Defaults to current Asia/Manila month.
 * @param {number} [options.maxCatchUpMonths=1] - Max months to credit per row per run (catch-up cap).
 * @param {boolean} [options.dryRun=false]
 * @param {boolean} [options.allowFutureTargetMonth=false] - Explicit override for simulations/backfills.
 * @param {Date|string} [options.now] - Testing hook for the current month guard.
 * @param {string} [options.timeZone='Asia/Manila'] - Time zone used for the current month guard.
 * @returns {Promise<{ targetYearMonth: string, rate: number, dryRun: boolean, rowsUpdated: number, rowsSkipped: number, details: Array<object> }>}
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

  initLeaveBalanceLedger(pgPool);

  const client = await pgPool.connect();
  const details = [];
  let rowsUpdated = 0;
  let rowsSkipped = 0;

  try {
    if (!dryRun) {
      await client.query('BEGIN');
    }
    const missingBalanceResult = await client.query(
      `SELECT u.id AS user_id, u.full_name, u.date_hired, t.leave_type
       FROM users u
       CROSS JOIN unnest($1::text[]) AS t(leave_type)
       LEFT JOIN leave_balances lb
         ON lb.user_id = u.id
        AND lb.leave_type = t.leave_type
       WHERE (u.is_active IS NULL OR u.is_active = true)
         AND lb.id IS NULL`,
      [ACCRUAL_LEAVE_TYPES]
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
           AND lb.id IS NULL
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [ACCRUAL_LEAVE_TYPES]
      );
    }

    const { rows } = await client.query(
      `SELECT lb.id, lb.user_id, lb.leave_type, lb.earned_days, lb.last_accrual_date, u.full_name, u.date_hired
       FROM leave_balances lb
       INNER JOIN users u ON u.id = lb.user_id
       WHERE lb.leave_type = ANY($1::text[])
         AND (u.is_active IS NULL OR u.is_active = true)`,
      [ACCRUAL_LEAVE_TYPES]
    );
    if (dryRun && missingBalanceResult.rows.length > 0) {
      rows.push(
        ...missingBalanceResult.rows.map((row) => ({
          id: null,
          user_id: row.user_id,
          leave_type: row.leave_type,
          earned_days: 0,
          last_accrual_date: null,
          full_name: row.full_name,
          date_hired: row.date_hired,
        }))
      );
    }

    for (const row of rows) {
      const createdBalanceRow = missingBalanceKeys.has(`${row.user_id}|${row.leave_type}`);
      const lastAccrual = row.last_accrual_date ? new Date(row.last_accrual_date) : null;
      const months = countMonthsToCredit(lastAccrual, targetMonth, maxCatchUpMonths);

      if (months <= 0) {
        rowsSkipped += 1;
        let reason = 'no_months_due';
        if (lastAccrual && monthKey(startOfMonth(lastAccrual)) >= monthKey(targetMonth)) {
          reason = 'already_credited_through_target_month';
        } else if (maxCatchUpMonths <= 0) {
          reason = 'max_catch_up_months_is_zero';
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

      let firstMonthStart;
      if (!lastAccrual) {
        firstMonthStart = targetMonth;
      } else {
        firstMonthStart = addMonths(startOfMonth(lastAccrual), 1);
      }
      const lastMonthStart = lastCreditedMonthStart(firstMonthStart, months);
      const lastAccrualStr = toDateStr(lastMonthStart);

      /** @type {number} */
      let addDays;
      /** @type {object|null} */
      let firstMonthInfo = null;

      if (!lastAccrual && months === 1) {
        firstMonthInfo = firstMonthAccrualAmount(targetMonth, row.date_hired, DAYS_PER_MONTH);
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
        addDays = firstMonthInfo.addDays;
      } else {
        addDays = months * DAYS_PER_MONTH;
      }

      if (dryRun) {
        rowsUpdated += 1;
        details.push({
          user_id: row.user_id,
          employee_name: row.full_name,
          leave_type: row.leave_type,
          action: 'would_apply',
          months_credited: months,
          days_added: addDays,
          last_accrual_date: lastAccrualStr,
          created_balance_row: createdBalanceRow,
          hire_prorated: !!(firstMonthInfo && firstMonthInfo.prorated),
          ...(firstMonthInfo && firstMonthInfo.days_worked != null
            ? {
                days_worked: firstMonthInfo.days_worked,
                days_in_month: firstMonthInfo.days_in_month,
              }
            : {}),
        });
        continue;
      }

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
      };
      if (firstMonthInfo && firstMonthInfo.prorated) {
        meta.hire_date_proration = true;
        meta.days_worked = firstMonthInfo.days_worked;
        meta.days_in_month = firstMonthInfo.days_in_month;
      }

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
      details.push({
        user_id: row.user_id,
        employee_name: row.full_name,
        leave_type: row.leave_type,
        action: 'applied',
        months_credited: months,
        days_added: addDays,
        last_accrual_date: lastAccrualStr,
        created_balance_row: createdBalanceRow,
        hire_prorated: !!(firstMonthInfo && firstMonthInfo.prorated),
        ...(firstMonthInfo && firstMonthInfo.days_worked != null
          ? {
              days_worked: firstMonthInfo.days_worked,
              days_in_month: firstMonthInfo.days_in_month,
            }
          : {}),
      });
    }

    if (!dryRun) {
      await client.query('COMMIT');
    }

    return {
      targetYearMonth,
      rate: DAYS_PER_MONTH,
      leaveTypes: ACCRUAL_LEAVE_TYPES,
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
  parseTargetMonth,
  monthStartInTimeZone,
  round2,
};
