const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin, requireAdminOrHr } = require('../middleware/rbac');
const {
  LEAVE_TYPE_RULES,
  SPECIAL_PROCESS_PURPOSES,
  effectiveMaxDaysForRule,
  leaveEventDateFilingError,
  minimumAdvanceDaysFilingError,
  mustBlockMissingAttachment,
} = require('./leaveTypeRules');
const {
  validateEmployeeUpdateTransition,
  validateEmployeeCancelTransition,
  validateDepartmentHeadTransition,
  validateAdminTransition,
} = require('../services/leaveWorkflowRules');
const {
  getEmployeeDepartment,
  getDepartmentHeadForEmployee,
  isDepartmentHead,
} = require('../services/departmentHeadService');
const {
  initLeaveRequestHistory,
  insertLeaveRequestHistory,
} = require('../services/leaveRequestHistory');
const {
  initLeaveBalanceLedger,
  insertLeaveBalanceLedger,
  fetchBalanceSnapshot,
} = require('../services/leaveBalanceLedger');
const {
  expandNonRecurringToWindow,
  expandRecurringToWindow,
} = require('../services/holidayRangeUtils');
const leaveNotifications = require('../services/leaveNotifications');
const { runLeaveMonthlyAccrual } = require('../services/leaveMonthlyAccrual');
const {
  getYearEndForcedLeaveCompliance,
  applyYearEndForcedLeaveDeductions,
  manilaYearNow: yearEndManilaYearNow,
} = require('../services/leaveYearEndForcedLeave');
const { broadcastAppEvent } = require('../websockets/appEvents');
const { broadcastBiometricUpdate } = require('../websockets/biometricStream');

const router = express.Router();

/** Fire-and-forget in-app notifications; never fails the HTTP handler. */
function notifySafe(fn) {
  Promise.resolve()
    .then(() => fn())
    .catch((e) => console.error('[leave notification]', e));
}

function leaveRowUserId(row = {}) {
  return row.user_id || row.employee_id || row.userId || row.employeeId || null;
}

function broadcastLeaveUpdated(action, row = {}, extra = {}) {
  try {
    const requestId = row.id || extra.requestId || extra.leaveRequestId || null;
    broadcastAppEvent('leave_updated', {
      action,
      requestId,
      leaveRequestId: requestId,
      userId: leaveRowUserId(row) || extra.userId || null,
      status: row.status || extra.status || null,
      updatedAt: new Date().toISOString(),
      ...extra,
    });
  } catch (e) {
    console.error('[leave websocket]', e);
  }
}

function broadcastDtrLeaveRefresh(action, { userId, leaveRequestId, dateFrom, dateTo } = {}) {
  try {
    if (!userId) return;
    const normalizedUserId = String(userId);
    broadcastBiometricUpdate('dtr_refresh', {
      action,
      userId: normalizedUserId,
      userIds: [normalizedUserId],
      requestId: leaveRequestId || null,
      leaveRequestId: leaveRequestId || null,
      dateFrom: dateFrom || null,
      dateTo: dateTo || null,
    });
  } catch (e) {
    console.error('[leave dtr websocket]', e);
  }
}
const protect = [authMiddleware];

async function findActiveAssignmentProfileByUserId(db, userId) {
  if (!userId) return null;
  const result = await db.query(
    `SELECT u.id AS user_id,
            u.full_name,
            p.name AS position_title,
            a.department_id,
            d.name AS department_name
     FROM users u
     LEFT JOIN LATERAL (
       SELECT a.department_id, a.position_id, a.effective_from
       FROM assignments a
       WHERE a.employee_id = u.id
         AND (a.is_active IS NULL OR a.is_active = true)
       ORDER BY a.effective_from DESC NULLS LAST, a.created_at DESC NULLS LAST
       LIMIT 1
     ) a ON true
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN positions p ON p.id = a.position_id
     WHERE u.id = $1
     LIMIT 1`,
    [userId]
  );
  return result.rows[0] || null;
}

let ensureOtherPositionsPromise = null;

async function ensureEmployeeOtherPositionsTable(db) {
  if (!ensureOtherPositionsPromise) {
    ensureOtherPositionsPromise = (async () => {
      await db.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
      await db.query(`
        CREATE TABLE IF NOT EXISTS employee_other_positions (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
          position_id UUID NOT NULL REFERENCES positions(id) ON DELETE RESTRICT,
          effective_from DATE NOT NULL,
          effective_to DATE,
          is_active BOOLEAN NOT NULL DEFAULT true,
          remarks TEXT,
          created_by UUID REFERENCES users(id) ON DELETE SET NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `);
      await db.query(`
        CREATE INDEX IF NOT EXISTS idx_employee_other_positions_employee
          ON employee_other_positions(employee_id, effective_from DESC)
      `);
      await db.query(`
        CREATE INDEX IF NOT EXISTS idx_employee_other_positions_position
          ON employee_other_positions(position_id)
      `);
    })().catch((err) => {
      ensureOtherPositionsPromise = null;
      throw err;
    });
  }
  return ensureOtherPositionsPromise;
}

async function findActiveEmployeeByPositionTitle(db, positionTitle) {
  await ensureEmployeeOtherPositionsTable(db);
  const result = await db.query(
    `WITH candidates AS (
       SELECT u.id AS user_id,
              u.full_name,
              p.name AS position_title,
              a.department_id,
              d.name AS department_name,
              0 AS source_priority,
              a.effective_from
       FROM assignments a
       JOIN users u ON u.id = a.employee_id
       JOIN positions p ON p.id = a.position_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE (a.is_active IS NULL OR a.is_active = true)
         AND (u.is_active IS NULL OR u.is_active = true)
         AND (p.is_active IS NULL OR p.is_active = true)
         AND (a.effective_from IS NULL OR a.effective_from <= CURRENT_DATE)
         AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
         AND LOWER(p.name) = LOWER($1)

       UNION ALL

       SELECT u.id AS user_id,
              u.full_name,
              p.name AS position_title,
              eop.department_id,
              d.name AS department_name,
              1 AS source_priority,
              eop.effective_from
       FROM employee_other_positions eop
       JOIN users u ON u.id = eop.employee_id
       JOIN positions p ON p.id = eop.position_id
       LEFT JOIN departments d ON d.id = eop.department_id
       WHERE eop.is_active = true
         AND (u.is_active IS NULL OR u.is_active = true)
         AND (p.is_active IS NULL OR p.is_active = true)
         AND eop.effective_from <= CURRENT_DATE
         AND (eop.effective_to IS NULL OR eop.effective_to >= CURRENT_DATE)
         AND LOWER(p.name) = LOWER($1)
     )
     SELECT user_id, full_name, position_title, department_id, department_name
     FROM candidates
     ORDER BY source_priority, effective_from DESC NULLS LAST, full_name
     LIMIT 1`,
    [positionTitle]
  );
  return result.rows[0] || null;
}

function mapSignatoryProfile(row) {
  if (!row) return null;
  return {
    user_id: row.user_id || null,
    name: row.full_name || null,
    position_title: row.position_title || null,
    department_id: row.department_id || null,
    department_name: row.department_name || null,
  };
}

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const LEAVE_ATTACHMENT_SUBDIR = 'leave-attachments';
const SYSTEM_LEAVE_TYPE_NAMES = Object.freeze(Object.keys(LEAVE_TYPE_RULES));
const NO_CREDIT_LEDGER_TYPE = 'none';
const OWN_BALANCE_LEDGER_TYPE = 'ownBalance';
const BALANCE_LEDGER_CONFIG_TYPES = new Set([
  NO_CREDIT_LEDGER_TYPE,
  OWN_BALANCE_LEDGER_TYPE,
  'vacationLeave',
  'sickLeave',
]);
const SEX_ELIGIBILITY_TYPES = new Set(['any', 'female', 'male']);
const CREDIT_BALANCE_BUCKET_TYPES = new Set([
  'vacationLeave',
  'sickLeave',
]);
const HR_CERTIFICATION_POSITION_TITLE = 'Administrative Officer V';
const SYSTEM_NO_CREDIT_LEAVE_TYPES = new Set([
  'maternityLeave',
  'paternityLeave',
  'specialPrivilegeLeave',
  'soloParentLeave',
  'studyLeave',
  'tenDayVawcLeave',
  'rehabilitationPrivilege',
  'specialLeaveBenefitsForWomen',
  'specialEmergencyCalamityLeave',
  'adoptionLeave',
  'others',
]);
const LEGACY_NO_CREDIT_LEDGER_TYPES = new Set([
  ...SYSTEM_NO_CREDIT_LEAVE_TYPES,
  'others',
]);
const SPECIAL_PRIVILEGE_LEAVE_TYPE = 'specialPrivilegeLeave';
const SPECIAL_PRIVILEGE_LEAVE_ANNUAL_LIMIT = 3;
const LEAVE_REVOKE_WINDOW_DAYS = 3;
const LEAVE_REVOKE_WINDOW_MS = LEAVE_REVOKE_WINDOW_DAYS * 24 * 60 * 60 * 1000;
const SPECIAL_PRIVILEGE_LEAVE_USAGE_STATUSES = [
  'pending',
  'pending_department_head',
  'pending_hr',
  'approved',
];

initLeaveRequestHistory(pool);
initLeaveBalanceLedger(pool);
pool
  .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
  .then(async () => {
    await pool.query(`
      ALTER TABLE leave_types
        ADD COLUMN IF NOT EXISTS display_name TEXT,
        ADD COLUMN IF NOT EXISTS employee_can_file BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS admin_only BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS allows_past_dates BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS requires_attachment BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS requires_attachment_when_over_days NUMERIC,
        ADD COLUMN IF NOT EXISTS max_days NUMERIC,
        ADD COLUMN IF NOT EXISTS minimum_advance_days INTEGER,
        ADD COLUMN IF NOT EXISTS affects_dtr_normally BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS balance_ledger_type TEXT NOT NULL DEFAULT 'none',
        ADD COLUMN IF NOT EXISTS sex_eligibility TEXT NOT NULL DEFAULT 'any',
        ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
    `);

    await pool.query(`
      ALTER TABLE leave_types
        ALTER COLUMN balance_ledger_type SET DEFAULT 'none';
    `);

    await pool.query(`
      UPDATE leave_types
      SET balance_ledger_type = 'none',
          updated_at = COALESCE(updated_at, now())
      WHERE COALESCE(NULLIF(balance_ledger_type, ''), 'none') = 'others';
    `);

    await pool.query(`
      UPDATE leave_types
      SET sex_eligibility = 'any',
          updated_at = COALESCE(updated_at, now())
      WHERE sex_eligibility IS NULL
         OR sex_eligibility NOT IN ('any', 'female', 'male');
    `);

    await pool.query(`
      UPDATE leave_types
      SET display_name = COALESCE(NULLIF(display_name, ''), description, name),
          is_system = CASE
            WHEN name = ANY($1::text[]) THEN true
            ELSE is_system
          END,
          updated_at = COALESCE(updated_at, now());
    `, [SYSTEM_LEAVE_TYPE_NAMES]);

    await pool.query(`
      UPDATE leave_types
      SET employee_can_file = CASE WHEN name = 'mandatoryForcedLeave' THEN false ELSE true END,
          admin_only = CASE WHEN name = 'mandatoryForcedLeave' THEN true ELSE false END,
          allows_past_dates = CASE WHEN name IN ('vacationLeave', 'specialPrivilegeLeave') THEN false ELSE true END,
          requires_attachment = CASE
            WHEN name IN (
              'maternityLeave',
              'paternityLeave',
              'soloParentLeave',
              'studyLeave',
              'tenDayVawcLeave',
              'rehabilitationPrivilege',
              'specialLeaveBenefitsForWomen',
              'specialEmergencyCalamityLeave',
              'adoptionLeave',
              'others'
            ) THEN true
            ELSE false
          END,
          requires_attachment_when_over_days = CASE WHEN name = 'sickLeave' THEN 5 ELSE NULL END,
          max_days = CASE
            WHEN name = 'mandatoryForcedLeave' THEN 5
            WHEN name = 'maternityLeave' THEN 105
            WHEN name = 'paternityLeave' THEN 7
            WHEN name = 'specialPrivilegeLeave' THEN 3
            WHEN name = 'soloParentLeave' THEN 7
            WHEN name = 'studyLeave' THEN 180
            WHEN name = 'tenDayVawcLeave' THEN 10
            WHEN name = 'rehabilitationPrivilege' THEN 180
            WHEN name = 'specialLeaveBenefitsForWomen' THEN 60
            WHEN name = 'specialEmergencyCalamityLeave' THEN 5
            ELSE NULL
          END,
          minimum_advance_days = CASE
            WHEN name IN ('vacationLeave', 'soloParentLeave', 'specialLeaveBenefitsForWomen') THEN 5
            WHEN name = 'specialPrivilegeLeave' THEN 7
            ELSE NULL
          END,
          affects_dtr_normally = true,
          balance_ledger_type = CASE
            WHEN name = 'mandatoryForcedLeave' THEN 'vacationLeave'
            WHEN name IN ('vacationLeave', 'sickLeave') THEN name
            ELSE 'none'
          END,
          sex_eligibility = CASE
            WHEN name IN ('maternityLeave', 'tenDayVawcLeave', 'specialLeaveBenefitsForWomen') THEN 'female'
            WHEN name = 'paternityLeave' THEN 'male'
            ELSE 'any'
          END,
          is_active = true
      WHERE name = ANY($1::text[]);
    `, [SYSTEM_LEAVE_TYPE_NAMES]);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS leave_balance_deduction_history (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        leave_type TEXT NOT NULL,
        deducted_days NUMERIC NOT NULL,
        remaining_days NUMERIC,
        remarks TEXT,
        applied_by UUID REFERENCES users(id) ON DELETE SET NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        metadata_json JSONB
      );
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_leave_balance_deduction_history_user_applied
        ON leave_balance_deduction_history(user_id, applied_at DESC);
    `);
  })
  .catch((err) =>
    console.error('[leave] failed to ensure leave_balance_deduction_history table', err)
  );

function toIsoDateStr(val) {
  if (!val) return null;
  if (val instanceof Date) {
    // Manually format so we don't shift by timezone.
    const y = val.getFullYear();
    const m = String(val.getMonth() + 1).padStart(2, '0');
    const d = String(val.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  const s = String(val);
  const match = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return match ? match[0] : null;
}

function isWeekday(dateObj) {
  const d = dateObj.getDay(); // 0 Sun .. 6 Sat
  return d !== 0 && d !== 6;
}

function isoWeekdayFromDateString(dateStr) {
  const d = new Date(`${dateStr}T12:00:00`);
  if (isNaN(d.getTime())) return null;
  const day = d.getDay(); // 0 Sun .. 6 Sat
  return day === 0 ? 7 : day;
}

function normalizeWorkingDays(value) {
  const source = Array.isArray(value)
    ? value
    : (typeof value === 'string' ? (value.match(/\d+/g) || []) : [1, 2, 3, 4, 5]);
  const days = source
    .map((d) => parseInt(d, 10))
    .filter((d) => Number.isInteger(d) && d >= 1 && d <= 7);
  return days.length > 0 ? days : [1, 2, 3, 4, 5];
}

async function holidayDateSetForRange(startStr, endStr, dbClient = null) {
  const holidayDates = new Set();
  if (!dbClient) return holidayDates;
  try {
    const nonRec = await dbClient.query(
      `SELECT date_from, date_to FROM holidays
       WHERE is_active = true
        AND recurring = false
         AND holiday_type IN ('regular', 'special', 'local')
         AND date_from <= $2::date AND date_to >= $1::date`,
      [startStr, endStr]
    );
    for (const row of nonRec.rows) {
      const df = String(row.date_from).split('T')[0].slice(0, 10);
      const dt = String(row.date_to).split('T')[0].slice(0, 10);
      for (const ds of expandNonRecurringToWindow(df, dt, startStr, endStr)) {
        holidayDates.add(ds);
      }
    }
    const rec = await dbClient.query(
      `SELECT date_from, date_to FROM holidays
       WHERE is_active = true
         AND recurring = true
         AND holiday_type IN ('regular', 'special', 'local')`
    );
    for (const row of rec.rows) {
      const df = String(row.date_from).split('T')[0].slice(0, 10);
      const dt = String(row.date_to).split('T')[0].slice(0, 10);
      for (const ds of expandRecurringToWindow(df, dt, startStr, endStr)) {
        holidayDates.add(ds);
      }
    }
  } catch (_) {
    // Keep callers resilient; they can still count scheduled days without holidays.
  }
  return holidayDates;
}

/**
 * #12 Holiday-aware working day count (Mon–Fri, excluding public holidays).
 *
 * @param {string} startStr  YYYY-MM-DD
 * @param {string} endStr    YYYY-MM-DD
 * @param {import('pg').PoolClient|null} [dbClient]  optional DB client for holiday lookup.
 *        If null, falls back to simple Mon–Fri count (safe for contexts where a
 *        DB client is not available, e.g. validation before the transaction begins).
 * @returns {Promise<number|null>} count or null on invalid input
 */
async function computeNumberOfDays(startStr, endStr, dbClient = null) {
  if (!startStr || !endStr) return null;
  const start = new Date(`${startStr}T12:00:00`);
  const end = new Date(`${endStr}T12:00:00`);
  if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
  if (end < start) return null;

  const holidayDates = await holidayDateSetForRange(startStr, endStr, dbClient);

  let count = 0;
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    if (!isWeekday(d)) continue;
    const ds = toIsoDateStr(d); // use the same shift-proof helper
    if (!holidayDates.has(ds)) count += 1;
  }
  return count;
}

async function computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr) {
  if (!client || !userId || !startStr || !endStr) {
    return { days: await computeNumberOfDays(startStr, endStr, client), countedDates: [], scheduleSource: 'fallback' };
  }
  const start = new Date(`${startStr}T12:00:00`);
  const end = new Date(`${endStr}T12:00:00`);
  if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) {
    return { days: null, countedDates: [], scheduleSource: 'invalid' };
  }

  const holidayDates = await holidayDateSetForRange(startStr, endStr, client);
  const q = await client.query(
    `SELECT
        to_char(gs::date, 'YYYY-MM-DD') AS attendance_date,
        COALESCE(s.working_days, ARRAY[1,2,3,4,5]::int[]) AS working_days,
        eff.assignment_id IS NOT NULL AS has_assignment,
        s.id IS NOT NULL AS has_shift
     FROM generate_series($2::date, $3::date, '1 day'::interval) AS gs
     LEFT JOIN LATERAL (
       SELECT a.id AS assignment_id, a.shift_id
       FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND (a.is_active IS NULL OR a.is_active = true)
         AND a.effective_from <= gs::date
         AND (a.effective_to IS NULL OR a.effective_to >= gs::date)
       ORDER BY a.effective_from DESC
       LIMIT 1
     ) eff ON TRUE
     LEFT JOIN shifts s ON s.id = eff.shift_id
     ORDER BY gs::date`,
    [userId, startStr, endStr]
  );

  const countedDates = [];
  let sawShift = false;
  let sawAssignmentWithoutShift = false;
  let sawNoAssignment = false;
  for (const row of q.rows) {
    const ds = row.attendance_date;
    const isoWeekday = isoWeekdayFromDateString(ds);
    if (isoWeekday == null) continue;
    if (row.has_shift) sawShift = true;
    else if (row.has_assignment) sawAssignmentWithoutShift = true;
    else sawNoAssignment = true;
    if (holidayDates.has(ds)) continue;
    const workingDays = normalizeWorkingDays(row.working_days);
    if (workingDays.includes(isoWeekday)) countedDates.push(ds);
  }

  const scheduleSource = sawShift
    ? 'shift'
    : (sawAssignmentWithoutShift ? 'assignment_fallback' : (sawNoAssignment ? 'fallback' : 'none'));
  return {
    days: countedDates.length,
    countedDates,
    scheduleSource,
    holidayDates: Array.from(holidayDates).sort(),
  };
}

/** Synchronous fallback (Mon–Fri only), used where async is not possible. */
function computeNumberOfDaysSync(startStr, endStr) {
  if (!startStr || !endStr) return null;
  const start = new Date(`${startStr}T12:00:00`);
  const end = new Date(`${endStr}T12:00:00`);
  if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
  if (end < start) return null;
  let count = 0;
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    if (isWeekday(d)) count += 1;
  }
  return count;
}

async function hasOverlappingLeaveRequest(client, userId, startStr, endStr, excludeId = null) {
  if (!userId || !startStr || !endStr) return false;
  // FIX #10: prefer user_id; fallback to employee_id only for legacy records not yet backfilled.
  const q = await client.query(
    `SELECT 1
     FROM leave_requests
     WHERE (user_id = $1 OR employee_id = $1)
       AND status IN ('pending', 'pending_department_head', 'pending_hr', 'approved')
       AND start_date <= $3::date
       AND end_date >= $2::date
       AND ($4::uuid IS NULL OR id <> $4::uuid)
     LIMIT 1`,
    [userId, startStr, endStr, excludeId]
  );
  return q.rows.length > 0;
}

function calendarYearsForDateRange(startStr, endStr) {
  const startYear = parseInt(String(startStr || '').slice(0, 4), 10);
  const endYear = parseInt(String(endStr || '').slice(0, 4), 10);
  if (!Number.isInteger(startYear) || !Number.isInteger(endYear)) return [];
  const from = Math.min(startYear, endYear);
  const to = Math.max(startYear, endYear);
  const years = [];
  for (let year = from; year <= to; year += 1) years.push(year);
  return years;
}

function maxIsoDate(a, b) {
  if (!a) return b;
  if (!b) return a;
  return a > b ? a : b;
}

function minIsoDate(a, b) {
  if (!a) return b;
  if (!b) return a;
  return a < b ? a : b;
}

function formatDayCount(days) {
  const n = Number(days);
  if (!Number.isFinite(n)) return '0';
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, '');
}

async function workingDaysWithinYear(client, userId, startStr, endStr, year) {
  if (!startStr || !endStr) return 0;
  const from = maxIsoDate(startStr, `${year}-01-01`);
  const to = minIsoDate(endStr, `${year}-12-31`);
  if (!from || !to || to < from) return 0;
  const result = await computeEmployeeLeaveWorkingDays(client, userId, from, to);
  return result.days ?? 0;
}

async function assertSpecialPrivilegeLeaveAnnualLimit(
  client,
  { userId, leaveTypeName, startStr, endStr, excludeId = null }
) {
  if (leaveTypeName !== SPECIAL_PRIVILEGE_LEAVE_TYPE) return;
  if (!client || !userId || !startStr || !endStr) return;

  const years = calendarYearsForDateRange(startStr, endStr);
  if (years.length === 0) return;

  const queryFrom = `${Math.min(...years)}-01-01`;
  const queryTo = `${Math.max(...years)}-12-31`;
  const existing = await client.query(
    `SELECT lr.id, lr.start_date, lr.end_date
     FROM leave_requests lr
     INNER JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE (lr.user_id = $1::uuid OR lr.employee_id = $1::uuid)
       AND lt.name = $2
       AND lr.status = ANY($3::text[])
       AND lr.start_date <= $5::date
       AND lr.end_date >= $4::date
       AND ($6::uuid IS NULL OR lr.id <> $6::uuid)`,
    [
      userId,
      SPECIAL_PRIVILEGE_LEAVE_TYPE,
      SPECIAL_PRIVILEGE_LEAVE_USAGE_STATUSES,
      queryFrom,
      queryTo,
      excludeId,
    ]
  );

  for (const year of years) {
    const requestedDays = await workingDaysWithinYear(client, userId, startStr, endStr, year);
    if (requestedDays <= 0) continue;

    let usedDays = 0;
    for (const row of existing.rows) {
      const existingStart = toIsoDateStr(row.start_date);
      const existingEnd = toIsoDateStr(row.end_date);
      usedDays += await workingDaysWithinYear(client, userId, existingStart, existingEnd, year);
    }

    const remaining = Math.max(0, SPECIAL_PRIVILEGE_LEAVE_ANNUAL_LIMIT - usedDays);
    if (usedDays + requestedDays > SPECIAL_PRIVILEGE_LEAVE_ANNUAL_LIMIT + 0.0001) {
      const err = new Error(
        `Special Privilege Leave is limited to ${SPECIAL_PRIVILEGE_LEAVE_ANNUAL_LIMIT} days per calendar year. ` +
        `You only have ${formatDayCount(remaining)} day(s) remaining for ${year}; this request needs ${formatDayCount(requestedDays)} day(s).`
      );
      err.statusCode = 400;
      throw err;
    }
  }
}

function systemLeaveTypeDisplayName(name) {
  const labels = {
    vacationLeave: 'Vacation Leave',
    mandatoryForcedLeave: 'Mandatory/Forced Leave',
    sickLeave: 'Sick Leave',
    maternityLeave: 'Maternity Leave',
    paternityLeave: 'Paternity Leave',
    specialPrivilegeLeave: 'Special Privilege Leave',
    soloParentLeave: 'Solo Parent Leave',
    studyLeave: 'Study Leave',
    tenDayVawcLeave: '10-Day VAWC Leave',
    rehabilitationPrivilege: 'Rehabilitation Privilege',
    specialLeaveBenefitsForWomen: 'Special Leave Benefits for Women',
    specialEmergencyCalamityLeave: 'Special Emergency (Calamity) Leave',
    adoptionLeave: 'Adoption Leave',
    others: 'Others',
  };
  return labels[name] || name;
}

function slugLeaveTypeName(displayName) {
  const source = (displayName || '').toString().trim();
  const words = source.match(/[A-Za-z0-9]+/g) || [];
  if (words.length === 0) return null;
  const [first, ...rest] = words;
  const base = [
    first.toLowerCase(),
    ...rest.map((w) => `${w[0].toUpperCase()}${w.slice(1).toLowerCase()}`),
  ].join('');
  return base.endsWith('Leave') ? base : `${base}Leave`;
}

function leaveTypeRuleDefaults(name) {
  return LEAVE_TYPE_RULES[name] || {
    employee_can_file: true,
    admin_only: false,
    allows_past_dates: true,
    requires_attachment: true,
    requires_attachment_when_over_days: null,
    max_days: null,
    minimum_advance_days: null,
    affects_dtr_normally: true,
    sex_eligibility: defaultSexEligibilityForLeaveType(name),
  };
}

function defaultSexEligibilityForLeaveType(leaveTypeName) {
  if (
    leaveTypeName === 'maternityLeave' ||
    leaveTypeName === 'tenDayVawcLeave' ||
    leaveTypeName === 'specialLeaveBenefitsForWomen'
  ) {
    return 'female';
  }
  if (leaveTypeName === 'paternityLeave') return 'male';
  return 'any';
}

function normalizeSexEligibility(value, leaveTypeName) {
  const raw = (value || '').toString().trim().toLowerCase();
  if (raw === 'female_only' || raw === 'femaleonly') return 'female';
  if (raw === 'male_only' || raw === 'maleonly') return 'male';
  if (raw === 'both' || raw === 'all' || raw === 'bothsexes') return 'any';
  if (SEX_ELIGIBILITY_TYPES.has(raw)) return raw;
  return defaultSexEligibilityForLeaveType(leaveTypeName);
}

function defaultLedgerTypeForLeaveType(leaveTypeName) {
  if (leaveTypeName === 'mandatoryForcedLeave') return 'vacationLeave';
  if (leaveTypeName === 'vacationLeave' || leaveTypeName === 'sickLeave') {
    return leaveTypeName;
  }
  return NO_CREDIT_LEDGER_TYPE;
}

function normalizeLedgerType(value, leaveTypeName) {
  const raw = (value || '').toString().trim();
  if (raw === 'mandatoryForcedLeave') return 'vacationLeave';
  if (BALANCE_LEDGER_CONFIG_TYPES.has(raw)) return raw;
  if (CREDIT_BALANCE_BUCKET_TYPES.has(raw)) return raw;
  if (LEGACY_NO_CREDIT_LEDGER_TYPES.has(raw)) return NO_CREDIT_LEDGER_TYPE;
  if (raw && raw === leaveTypeName && !SYSTEM_LEAVE_TYPE_NAMES.includes(leaveTypeName)) {
    return OWN_BALANCE_LEDGER_TYPE;
  }
  return defaultLedgerTypeForLeaveType(leaveTypeName);
}

function creditBalanceLabel(ledgerType, leaveTypeName) {
  if (ledgerType === 'vacationLeave') return 'Vacation Leave';
  if (ledgerType === 'sickLeave') return 'Sick Leave';
  return systemLeaveTypeDisplayName(leaveTypeName || ledgerType || 'leave');
}

function leaveTypeRowToApi(row = {}) {
  const name = (row.name || '').toString();
  const fallback = leaveTypeRuleDefaults(name);
  const displayName =
    row.display_name || row.description || systemLeaveTypeDisplayName(name);
  return {
    id: row.id,
    name,
    display_name: displayName,
    description: row.description || null,
    is_active: row.is_active !== false,
    is_system: row.is_system === true || SYSTEM_LEAVE_TYPE_NAMES.includes(name),
    employee_can_file:
      row.employee_can_file != null
        ? row.employee_can_file === true
        : fallback.employee_can_file !== false,
    admin_only:
      row.admin_only != null ? row.admin_only === true : fallback.admin_only === true,
    allows_past_dates:
      row.allows_past_dates != null
        ? row.allows_past_dates === true
        : fallback.allows_past_dates !== false,
    requires_attachment:
      row.requires_attachment != null
        ? row.requires_attachment === true
        : fallback.requires_attachment === true,
    requires_attachment_when_over_days:
      row.requires_attachment_when_over_days != null
        ? parseFloat(row.requires_attachment_when_over_days)
        : fallback.requires_attachment_when_over_days ?? null,
    max_days:
      row.max_days != null ? parseFloat(row.max_days) : fallback.max_days ?? null,
    minimum_advance_days:
      row.minimum_advance_days != null
        ? parseInt(row.minimum_advance_days, 10)
        : fallback.minimum_advance_days ?? null,
    affects_dtr_normally:
      row.affects_dtr_normally != null
        ? row.affects_dtr_normally === true
        : fallback.affects_dtr_normally !== false,
    balance_ledger_type: normalizeLedgerType(row.balance_ledger_type, name),
    sex_eligibility: normalizeSexEligibility(
      row.sex_eligibility ?? fallback.sex_eligibility,
      name
    ),
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

async function getLeaveTypeDefinition(client, name) {
  const trimmed = (name || '').toString().trim();
  if (!trimmed) return null;
  const found = await client.query(
    `SELECT *
     FROM leave_types
     WHERE name = $1 AND (is_active IS NULL OR is_active = true)
     LIMIT 1`,
    [trimmed]
  );
  if (found.rows.length === 0) return null;
  return leaveTypeRowToApi(found.rows[0]);
}

function normalizeUserSexForLeave(value) {
  const sex = (value || '').toString().trim().toLowerCase();
  if (!sex) return null;
  if (sex === 'f' || sex === 'female') return 'female';
  if (sex === 'm' || sex === 'male') return 'male';
  return sex;
}

function leaveTypeSexEligibilityError({ leaveType, leaveTypeLabel, sexEligibility, userSex }) {
  const label = (leaveTypeLabel || systemLeaveTypeDisplayName(leaveType) || 'This leave type')
    .toString()
    .trim();
  const sex = normalizeUserSexForLeave(userSex);
  const eligibility = normalizeSexEligibility(sexEligibility, leaveType);
  if (eligibility === 'female') {
    if (!sex) {
      return `${label} requires your profile sex to be set to Female. Please update your profile or contact HR.`;
    }
    if (sex !== 'female') {
      return `${label} can only be filed by female accounts.`;
    }
  }
  if (eligibility === 'male') {
    if (!sex) {
      return `${label} requires your profile sex to be set to Male. Please update your profile or contact HR.`;
    }
    if (sex !== 'male') {
      return `${label} can only be filed by male accounts.`;
    }
  }
  return null;
}

async function getUserSexForLeaveValidation(client, userId) {
  if (!userId) return null;
  const result = await client.query(
    'SELECT sex FROM users WHERE id = $1 LIMIT 1',
    [userId]
  );
  return result.rows[0]?.sex || null;
}

function readMaternityDeliveryType(details) {
  if (!details || typeof details !== 'object') return null;
  return (
    details.maternity_delivery_type ||
    details.maternityDeliveryType ||
    details.maternity_delivery ||
    details.delivery_type ||
    null
  );
}

function readFirstDetailValue(details, keys) {
  if (!details || typeof details !== 'object') return null;
  for (const key of keys) {
    const value = details[key];
    if (value != null && `${value}`.trim() !== '') return value;
  }
  return null;
}

function readLeaveEventDates(details) {
  return {
    expectedDeliveryDate: readFirstDetailValue(details, [
      'expected_delivery_date',
      'expectedDeliveryDate',
      'maternity_expected_delivery_date',
      'maternityExpectedDeliveryDate',
    ]),
    childDeliveryDate: readFirstDetailValue(details, [
      'child_delivery_date',
      'childDeliveryDate',
      'delivery_date',
      'deliveryDate',
      'spouse_delivery_date',
      'spouseDeliveryDate',
    ]),
    accidentDate: readFirstDetailValue(details, [
      'accident_date',
      'accidentDate',
    ]),
    calamityDate: readFirstDetailValue(details, [
      'calamity_date',
      'calamityDate',
      'calamity_occurrence_date',
      'calamityOccurrenceDate',
    ]),
  };
}

function validateEmployeeLeaveRequestWithRule(opts) {
  const {
    rule,
    leaveType,
    otherPurpose,
    startDateStr,
    endDateStr,
    numberOfDays,
    userSex,
    maternityDeliveryType,
    eventDates,
    enforceEventDateRules = false,
  } = opts;

  if (!rule) return { valid: true };
  const sexEligibilityError = leaveTypeSexEligibilityError({
    leaveType,
    leaveTypeLabel: rule.display_name,
    sexEligibility: rule.sex_eligibility,
    userSex,
  });
  if (sexEligibilityError) {
    return {
      valid: false,
      error: sexEligibilityError,
    };
  }
  if (rule.admin_only) {
    return {
      valid: false,
      error: 'This leave type cannot be filed by employees. It is admin-assigned only.',
    };
  }
  if (rule.employee_can_file === false) {
    return {
      valid: false,
      error: 'This leave type is not available for employee filing.',
    };
  }
  if (leaveType === 'others' && otherPurpose) {
    const purpose = String(otherPurpose).trim().toLowerCase();
    if (
      SPECIAL_PROCESS_PURPOSES.some((p) =>
        purpose.includes(p.toLowerCase().replace(/_/g, ''))
      )
    ) {
      return {
        valid: false,
        error:
          'Monetization of Leave Credits and Terminal Leave are HR/admin processes. Please contact HR.',
      };
    }
  }
  if (rule.allows_past_dates === false && startDateStr) {
    const today = new Date().toISOString().slice(0, 10);
    if (startDateStr < today) {
      return {
        valid: false,
        error: 'Past-date filing is not allowed for this leave type. Please file in advance.',
      };
    }
  }
  const advanceError = minimumAdvanceDaysFilingError({
    rule,
    leaveType,
    leaveTypeLabel: rule.display_name,
    startDateStr,
  });
  if (advanceError) {
    return {
      valid: false,
      error: advanceError,
    };
  }
  if (enforceEventDateRules) {
    const eventDateError = leaveEventDateFilingError({
      leaveType,
      leaveTypeLabel: rule.display_name,
      startDateStr,
      endDateStr,
      eventDates,
    });
    if (eventDateError) {
      return {
        valid: false,
        error: eventDateError,
      };
    }
  }
  const maxDays = effectiveMaxDaysForRule({
    rule,
    leaveType,
    maternityDeliveryType,
  });
  if (maxDays != null && numberOfDays != null) {
    const days = parseFloat(numberOfDays);
    if (!Number.isNaN(days) && days > maxDays) {
      return {
        valid: false,
        error: `This leave type allows a maximum of ${maxDays} working days. Requested: ${days.toFixed(1)}.`,
      };
    }
  }
  return { valid: true };
}

async function ensureLeaveTypeIdByName(client, name) {
  const trimmed = (name || '').toString().trim();
  if (!trimmed) return null;
  const found = await client.query(
    'SELECT id FROM leave_types WHERE name = $1 AND (is_active IS NULL OR is_active = true) LIMIT 1',
    [trimmed]
  );
  if (found.rows.length > 0) return found.rows[0].id;
  return null;
}

/** Active assignment → department (employee-filed requests store office in details; admin-assigned MFL often does not). */
const SQL_LEAVE_ASSIGNMENT_DEPT_JOIN = `
LEFT JOIN assignments a ON a.employee_id = COALESCE(lr.user_id, lr.employee_id)
  AND (a.is_active IS NULL OR a.is_active = true)
LEFT JOIN departments d ON d.id = a.department_id`;

function mapLeaveRowToApi(row) {
  // Keep response aligned with Flutter LeaveRequest.fromJson keys.
  // Spread details FIRST so canonical DB fields (status, etc.) take precedence and are not overwritten.
  const details = row.details && typeof row.details === 'object' ? row.details : {};
  const employeeName = row.employee_name || row.full_name || row.employee_full_name || details.employee_name || details.employeeName || null;
  return {
    ...details,
    id: row.id,
    user_id: row.user_id || row.employee_id,
    employee_name: employeeName,
    start_date: toIsoDateStr(row.start_date),
    end_date: toIsoDateStr(row.end_date),
    working_days_applied: row.number_of_days != null ? parseFloat(row.number_of_days) : (row.total_days != null ? parseFloat(row.total_days) : null),
    reason: row.reason || null,
    status: row.status,
    reviewer_id: row.reviewer_id || row.approved_by || null,
    reviewer_name: row.reviewer_name || row.reviewer_full_name || null,
    reviewer_role: row.reviewer_role || null,
    reviewer_title: row.reviewer_title || null,
    department_head_reviewer_id: row.department_head_reviewer_id || null,
    department_head_reviewer_name: row.department_head_reviewer_name || null,
    department_head_reviewed_at: row.department_head_reviewed_at || null,
    department_head_remarks: row.department_head_remarks || null,
    department_head_action: row.department_head_action || null,
    hr_remarks: row.reviewer_remarks || null,
    recommendation_remarks:
      row.recommendation_remarks ||
      details.recommendation_remarks ||
      details.recommendationRemarks ||
      null,
    disapproval_reason:
      row.disapproval_reason ||
      details.disapproval_reason ||
      details.disapprovalReason ||
      row.reviewer_remarks ||
      null,
    approved_days_with_pay:
      row.approved_days_with_pay != null
        ? parseFloat(row.approved_days_with_pay)
        : (details.approved_days_with_pay != null
            ? parseFloat(details.approved_days_with_pay)
            : (details.approvedDaysWithPay != null
                ? parseFloat(details.approvedDaysWithPay)
                : null)),
    approved_days_without_pay:
      row.approved_days_without_pay != null
        ? parseFloat(row.approved_days_without_pay)
        : (details.approved_days_without_pay != null
            ? parseFloat(details.approved_days_without_pay)
            : (details.approvedDaysWithoutPay != null
                ? parseFloat(details.approvedDaysWithoutPay)
                : null)),
    approved_other_details:
      row.approved_other_details ||
      details.approved_other_details ||
      details.approvedOtherDetails ||
      null,
    reviewed_at: row.reviewed_at || row.approved_at || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
    leave_type: row.leave_type_name || row.leave_type || null,
    leave_type_display_name:
      row.leave_type_display_name ||
      details.leave_type_display_name ||
      details.leaveTypeDisplayName ||
      row.leave_type_description ||
      details.custom_leave_type_text ||
      details.customLeaveTypeText ||
      systemLeaveTypeDisplayName(row.leave_type_name || row.leave_type),
    attachment_name: row.attachment_name || null,
    attachment_path: row.attachment_path || null,
    attachment_mime_type: row.attachment_mime_type || null,
    attachment_uploaded_at: row.attachment_uploaded_at || null,
    office_department:
      details.office_department ||
      details.officeDepartment ||
      row.assignment_department_name ||
      null,
  };
}

// Ensure leave attachment directory exists
const leaveAttachmentDir = path.join(UPLOAD_DIR, LEAVE_ATTACHMENT_SUBDIR);
if (!fs.existsSync(leaveAttachmentDir)) {
  fs.mkdirSync(leaveAttachmentDir, { recursive: true });
}

const ALLOWED_LEAVE_ATTACHMENT_EXT = /\.(pdf|jpg|jpeg|png)$/i;
const MAX_LEAVE_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10MB

const leaveAttachmentStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, leaveAttachmentDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.pdf';
    const safeExt = ALLOWED_LEAVE_ATTACHMENT_EXT.test(ext) ? ext : '.pdf';
    cb(null, `lr_${uuidv4()}${safeExt}`);
  },
});

const uploadLeaveAttachment = multer({
  storage: leaveAttachmentStorage,
  limits: { fileSize: MAX_LEAVE_ATTACHMENT_SIZE },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const ok = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext);
    if (!ok) cb(new Error('Allowed file types: PDF, JPG, JPEG, PNG'), false);
    else cb(null, true);
  },
});

const uploadLeaveAttachmentMemory = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_LEAVE_ATTACHMENT_SIZE },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    const ok = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext);
    if (!ok) cb(new Error('Allowed file types: PDF, JPG, JPEG, PNG'), false);
    else cb(null, true);
  },
});

function uploadLeaveAttachmentMw(req, res, next) {
  uploadLeaveAttachment.single('file')(req, res, (err) => {
    if (err) {
      if (err.message === 'Allowed file types: PDF, JPG, JPEG, PNG') {
        return res.status(400).json({ error: err.message });
      }
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'File too large. Max 10MB.' });
      }
      return next(err);
    }
    next();
  });
}

function uploadLeaveAttachmentMemoryMw(req, res, next) {
  uploadLeaveAttachmentMemory.single('file')(req, res, (err) => {
    if (err) {
      if (err.message === 'Allowed file types: PDF, JPG, JPEG, PNG') {
        return res.status(400).json({ error: err.message });
      }
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'File too large. Max 10MB.' });
      }
      return next(err);
    }
    next();
  });
}

function storedLeaveAttachmentFromMemoryFile(file) {
  if (!file || !Buffer.isBuffer(file.buffer)) return null;
  const ext = path.extname(file.originalname || '').toLowerCase();
  const safeExt = ['.pdf', '.jpg', '.jpeg', '.png'].includes(ext) ? ext : '.pdf';
  const filename = `lr_${uuidv4()}${safeExt}`;
  const filePath = path.join(leaveAttachmentDir, filename);
  fs.writeFileSync(filePath, file.buffer);
  return {
    originalName: file.originalname || filename,
    relPath: `${LEAVE_ATTACHMENT_SUBDIR}/${filename}`,
    mimeType: file.mimetype || null,
  };
}

function cleanupStoredLeaveAttachment(relPath) {
  if (!relPath) return;
  try {
    const filePath = path.join(UPLOAD_DIR, relPath);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  } catch (err) {
    console.error('[leave attachment cleanup]', err);
  }
}

function parseJsonBodyField(value) {
  if (value == null || typeof value !== 'string') return value;
  const text = value.trim();
  if (!text) return value;
  try {
    return JSON.parse(text);
  } catch (_) {
    return value;
  }
}

function leaveTypePayloadFromBody(body = {}, existing = null) {
  const displayName = (body.display_name ?? body.displayName ?? body.description ?? '').toString().trim();
  const rawName = (body.name ?? '').toString().trim();
  const name = rawName || slugLeaveTypeName(displayName);
  const base = leaveTypeRuleDefaults(name);

  function camelKey(key) {
    return key.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
  }

  function bodyField(key) {
    const camel = camelKey(key);
    if (Object.prototype.hasOwnProperty.call(body, key)) return body[key];
    if (Object.prototype.hasOwnProperty.call(body, camel)) return body[camel];
    return undefined;
  }

  function boolField(key, fallback) {
    const value = bodyField(key);
    if (value === undefined || value == null) return fallback;
    if (typeof value === 'boolean') return value;
    return ['true', '1', 'yes', 'y'].includes(String(value).trim().toLowerCase());
  }

  function numberField(key, fallback = null) {
    const value = bodyField(key);
    if (value === undefined) return fallback;
    if (value == null || value === '') return null;
    const n = parseFloat(value);
    return Number.isFinite(n) ? n : fallback;
  }

  function integerField(key, fallback = null) {
    const value = bodyField(key);
    if (value === undefined) return fallback;
    if (value == null || value === '') return null;
    const n = parseInt(value, 10);
    return Number.isFinite(n) && n >= 0 ? n : fallback;
  }

  return {
    id: existing?.id || null,
    name,
    displayName: displayName || existing?.display_name || existing?.description || systemLeaveTypeDisplayName(name),
    description: (body.description ?? existing?.description ?? displayName ?? '').toString().trim() || null,
    isActive: boolField('is_active', existing?.is_active ?? true),
    employeeCanFile: boolField('employee_can_file', existing?.employee_can_file ?? base.employee_can_file !== false),
    adminOnly: boolField('admin_only', existing?.admin_only ?? base.admin_only === true),
    allowsPastDates: boolField('allows_past_dates', existing?.allows_past_dates ?? base.allows_past_dates !== false),
    requiresAttachment: boolField('requires_attachment', existing?.requires_attachment ?? base.requires_attachment === true),
    requiresAttachmentWhenOverDays: numberField(
      'requires_attachment_when_over_days',
      existing?.requires_attachment_when_over_days ?? base.requires_attachment_when_over_days ?? null
    ),
    maxDays: numberField('max_days', existing?.max_days ?? base.max_days ?? null),
    minimumAdvanceDays: integerField(
      'minimum_advance_days',
      existing?.minimum_advance_days ?? base.minimum_advance_days ?? null
    ),
    affectsDtrNormally: boolField('affects_dtr_normally', existing?.affects_dtr_normally ?? base.affects_dtr_normally !== false),
    balanceLedgerType: normalizeLedgerType(body.balance_ledger_type ?? body.balanceLedgerType ?? existing?.balance_ledger_type, name),
    sexEligibility: normalizeSexEligibility(
      body.sex_eligibility ??
        body.sexEligibility ??
        existing?.sex_eligibility ??
        base.sex_eligibility,
      name
    ),
  };
}

// GET /api/leave/types — active leave types for forms, or all for admin management.
router.get('/types', protect, async (req, res) => {
  try {
    const includeInactive =
      String(req.query.include_inactive || req.query.includeInactive || '').toLowerCase() === 'true' ||
      req.query.include_inactive === '1';
    const q = await pool.query(
      `SELECT *
       FROM leave_types
       WHERE ($1::boolean = true OR is_active = true)
       ORDER BY is_system DESC, display_name NULLS LAST, description NULLS LAST, name`,
      [includeInactive]
    );
    res.json(q.rows.map(leaveTypeRowToApi));
  } catch (err) {
    console.error('[leave GET /types]', err);
    res.status(500).json({ error: 'Failed to fetch leave types' });
  }
});

// POST /api/leave/types — admin/HR creates a custom leave type with rules.
router.post('/types', protect, requireAdminOrHr, async (req, res) => {
  try {
    const payload = leaveTypePayloadFromBody(req.body || {});
    if (!payload.name || !payload.displayName) {
      return res.status(400).json({ error: 'Leave type name is required' });
    }
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(payload.name)) {
      return res.status(400).json({
        error: 'Leave type key must start with a letter and contain only letters, numbers, or underscore.',
      });
    }
    const q = await pool.query(
      `INSERT INTO leave_types (
          name, display_name, description, is_active, is_system,
          employee_can_file, admin_only, allows_past_dates,
          requires_attachment, requires_attachment_when_over_days,
          max_days, minimum_advance_days, affects_dtr_normally, balance_ledger_type,
          sex_eligibility,
          created_at, updated_at
        )
        VALUES (
          $1, $2, $3, $4, false,
          $5, $6, $7,
          $8, $9,
          $10, $11, $12, $13,
          $14,
          now(), now()
        )
        RETURNING *`,
      [
        payload.name,
        payload.displayName,
        payload.description,
        payload.isActive,
        payload.employeeCanFile,
        payload.adminOnly,
        payload.allowsPastDates,
        payload.requiresAttachment,
        payload.requiresAttachmentWhenOverDays,
        payload.maxDays,
        payload.minimumAdvanceDays,
        payload.affectsDtrNormally,
        payload.balanceLedgerType,
        payload.sexEligibility,
      ]
    );
    res.status(201).json(leaveTypeRowToApi(q.rows[0]));
  } catch (err) {
    console.error('[leave POST /types]', err);
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Leave type key already exists' });
    }
    res.status(500).json({ error: 'Failed to create leave type' });
  }
});

// PUT /api/leave/types/:id — admin/HR updates display/rules.
router.put('/types/:id', protect, requireAdminOrHr, async (req, res) => {
  try {
    const existingQ = await pool.query('SELECT * FROM leave_types WHERE id = $1::uuid', [req.params.id]);
    if (existingQ.rows.length === 0) {
      return res.status(404).json({ error: 'Leave type not found' });
    }
    const existing = existingQ.rows[0];
    const isSystem = existing.is_system === true || SYSTEM_LEAVE_TYPE_NAMES.includes(existing.name);
    const payload = leaveTypePayloadFromBody(req.body || {}, existing);
    const nextName = isSystem ? existing.name : payload.name;
    const nextActive = isSystem ? true : payload.isActive;
    const nextBalanceLedgerType = isSystem
      ? defaultLedgerTypeForLeaveType(nextName)
      : payload.balanceLedgerType;
    if (!nextName || !payload.displayName) {
      return res.status(400).json({ error: 'Leave type name is required' });
    }
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(nextName)) {
      return res.status(400).json({
        error: 'Leave type key must start with a letter and contain only letters, numbers, or underscore.',
      });
    }
    const q = await pool.query(
      `UPDATE leave_types
       SET name = $1,
           display_name = $2,
           description = $3,
           is_active = $4,
           is_system = $5,
           employee_can_file = $6,
           admin_only = $7,
           allows_past_dates = $8,
           requires_attachment = $9,
           requires_attachment_when_over_days = $10,
           max_days = $11,
           minimum_advance_days = $12,
           affects_dtr_normally = $13,
           balance_ledger_type = $14,
           sex_eligibility = $15,
           updated_at = now()
       WHERE id = $16::uuid
       RETURNING *`,
      [
        nextName,
        payload.displayName,
        payload.description,
        nextActive,
        isSystem,
        payload.employeeCanFile,
        payload.adminOnly,
        payload.allowsPastDates,
        payload.requiresAttachment,
        payload.requiresAttachmentWhenOverDays,
        payload.maxDays,
        payload.minimumAdvanceDays,
        payload.affectsDtrNormally,
        nextBalanceLedgerType,
        isSystem ? defaultSexEligibilityForLeaveType(nextName) : payload.sexEligibility,
        req.params.id,
      ]
    );
    res.json(leaveTypeRowToApi(q.rows[0]));
  } catch (err) {
    console.error('[leave PUT /types/:id]', err);
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Leave type key already exists' });
    }
    res.status(500).json({ error: 'Failed to update leave type' });
  }
});

/** Check if user can access leave request (owner or admin). */
async function canAccessLeaveRequest(requestId, userId, isAdmin) {
  // FIX #10: prefer user_id first; employee_id kept as fallback for legacy rows.
  const q = await pool.query(
    'SELECT id FROM leave_requests WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)',
    [requestId, isAdmin, userId]
  );
  return q.rows.length > 0;
}

/** Check if attachment can be modified (draft, any pending, returned, rejected). */
function canModifyAttachment(status) {
  return (
    status === 'draft' ||
    status === 'pending' ||
    status === 'pending_department_head' ||
    status === 'pending_hr' ||
    status === 'returned' ||
    status === 'rejected_by_department_head' ||
    status === 'rejected_by_hr'
  );
}

/**
 * CSC practice: mandatory/forced leave is charged against vacation leave credits.
 * Maps a leave_requests.leave type name to a leave_balances row key, or null
 * when the type is configured as a no-credit entitlement/statutory leave.
 */
function balanceLedgerLeaveType(leaveTypeName) {
  if (!leaveTypeName) return leaveTypeName;
  const configured = defaultLedgerTypeForLeaveType(leaveTypeName);
  if (configured === NO_CREDIT_LEDGER_TYPE) return null;
  if (configured === OWN_BALANCE_LEDGER_TYPE) return leaveTypeName;
  return configured;
}

async function resolveBalanceLedgerConfigType(client, leaveTypeName) {
  if (!leaveTypeName) return NO_CREDIT_LEDGER_TYPE;
  const fallback = defaultLedgerTypeForLeaveType(leaveTypeName);
  if (!client) return fallback;
  const q = await client.query(
    'SELECT balance_ledger_type FROM leave_types WHERE name = $1 LIMIT 1',
    [leaveTypeName]
  );
  return normalizeLedgerType(q.rows[0]?.balance_ledger_type, leaveTypeName);
}

async function resolveBalanceLedgerLeaveType(client, leaveTypeName) {
  const configured = await resolveBalanceLedgerConfigType(client, leaveTypeName);
  if (configured === NO_CREDIT_LEDGER_TYPE) return null;
  if (configured === OWN_BALANCE_LEDGER_TYPE) return leaveTypeName;
  return configured;
}

/** Matches Flutter LeaveBalance.remainingDays: earned - used + adjusted */
function ledgerRemainingFromBalancesRow(row) {
  if (!row) return 0;
  const e = parseFloat(row.earned_days ?? 0);
  const u = parseFloat(row.used_days ?? 0);
  const a = parseFloat(row.adjusted_days ?? 0);
  return e - u + a;
}

/** Matches Flutter LeaveBalance.availableDays: remaining - pending */
function ledgerAvailableFromBalancesRow(row) {
  const pending = row ? parseFloat(row.pending_days ?? 0) : 0;
  return ledgerRemainingFromBalancesRow(row) - pending;
}

/** Normalized snapshot for leave_balance_ledger old/new values. */
function balanceRowToSnapshot(row) {
  if (!row) {
    return { earned_days: 0, used_days: 0, pending_days: 0, adjusted_days: 0 };
  }
  return {
    earned_days: parseFloat(row.earned_days ?? 0),
    used_days: parseFloat(row.used_days ?? 0),
    pending_days: parseFloat(row.pending_days ?? 0),
    adjusted_days: parseFloat(row.adjusted_days ?? 0),
  };
}

/**
 * New pending reservation (submit / resubmit): must not exceed available pool.
 * Same formula as Flutter: available = earned - used + adjusted - pending.
 */
async function assertEnoughAvailableForPendingReservation(client, userId, leaveTypeName, deltaDays) {
  const d = deltaDays != null ? parseFloat(deltaDays) : 0;
  if (!userId || !leaveTypeName || !Number.isFinite(d) || d <= 0) return;
  const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
  if (!ledgerType) return;
  const bal = await client.query(
    `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     LIMIT 1
     FOR UPDATE`,
    [userId, ledgerType]
  );
  const available = ledgerAvailableFromBalancesRow(bal.rows[0]);
  if (d > available) {
    const remaining = ledgerRemainingFromBalancesRow(bal.rows[0]);
    const pending = bal.rows.length > 0 ? parseFloat(bal.rows[0].pending_days ?? 0) : 0;
    const bucketLabel = creditBalanceLabel(ledgerType, leaveTypeName);
    const err = new Error(
      `Insufficient ${bucketLabel} balance. Available ${available.toFixed(2)} (remaining ${remaining.toFixed(2)}, pending ${pending.toFixed(2)}), requested ${d.toFixed(2)}.`
    );
    err.statusCode = 400;
    throw err;
  }
}

async function upsertLeaveBalanceDeduction(
  client,
  userId,
  leaveTypeName,
  daysToDeduct,
  options = {}
) {
  if (!userId || !leaveTypeName) return;
  const days = daysToDeduct != null ? parseFloat(daysToDeduct) : 0;
  if (!Number.isFinite(days) || days <= 0) return;
  const allowNegative = options.allowNegative === true;
  /** When true (HR final approval only): clear the submit-time pending reservation before adding used_days. */
  const decrementPendingDays = options.decrementPendingDays === true;

  const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
  if (!ledgerType) return null;

  const bal = await client.query(
    `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     LIMIT 1
     FOR UPDATE`,
    [userId, ledgerType]
  );
  const remaining = ledgerRemainingFromBalancesRow(bal.rows[0]);
  const pending = bal.rows.length > 0 ? parseFloat(bal.rows[0].pending_days ?? 0) : 0;
  const available = remaining - pending;

  if (decrementPendingDays) {
    // Final approval: convert pending → used. Pool headroom is "remaining" (earned - used + adj); days were already in pending.
    if (!allowNegative && days > remaining) {
      const bucketLabel = creditBalanceLabel(ledgerType, leaveTypeName);
      const err = new Error(
        `Insufficient ${bucketLabel} balance. Remaining ${remaining.toFixed(2)}, requested ${days.toFixed(2)}.`
      );
      err.statusCode = 400;
      throw err;
    }
  } else {
    // Forced deduction (and any use not tied to a pending reservation): cannot take more than available.
    if (!allowNegative && days > available) {
      const bucketLabel = creditBalanceLabel(ledgerType, leaveTypeName);
      const prefix = `Insufficient ${bucketLabel} balance`;
      const msg = `${prefix}. Available ${available.toFixed(2)} (remaining ${remaining.toFixed(2)}, pending ${pending.toFixed(2)}), requested ${days.toFixed(2)}.`;
      const err = new Error(msg);
      err.statusCode = 400;
      throw err;
    }
  }

  await client.query(
    `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
     VALUES ($1::uuid, $2::text, 0, $3::numeric, 0, 0, now()::date, now()::date, now(), now())
     ON CONFLICT (user_id, leave_type)
     DO UPDATE SET used_days = COALESCE(leave_balances.used_days, 0) + EXCLUDED.used_days,
                   updated_at = now()`,
    [userId, ledgerType, days]
  );

  // Final approval: move days out of pending (submit-time reservation) into used — same ledger row as submit/PUT.
  if (decrementPendingDays) {
    await client.query(
      `UPDATE leave_balances
       SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
           updated_at = now()
       WHERE user_id = $1::uuid AND leave_type = $2::text`,
      [userId, ledgerType, days]
    );
  }

  const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
  const remainingOut =
    afterSnap.earned_days - afterSnap.used_days + afterSnap.adjusted_days;

  const lc = options.ledgerContext;
  if (lc) {
    const beforeSnap = balanceRowToSnapshot(bal.rows[0]);
    if (decrementPendingDays) {
      await insertLeaveBalanceLedger(client, {
        userId,
        leaveType: ledgerType,
        action: lc.action || 'leave_approved',
        affectedBucket: 'used',
        daysChanged: afterSnap.used_days - beforeSnap.used_days,
        oldValue: beforeSnap.used_days,
        newValue: afterSnap.used_days,
        relatedLeaveRequestId: lc.leaveRequestId || null,
        actorUserId: lc.actorUserId || null,
        actorKind: lc.actorKind || 'admin',
        remarks: lc.remarks || null,
        metadataJson: lc.metadataJson || null,
      });
      await insertLeaveBalanceLedger(client, {
        userId,
        leaveType: ledgerType,
        action: lc.action || 'leave_approved',
        affectedBucket: 'pending',
        daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
        oldValue: beforeSnap.pending_days,
        newValue: afterSnap.pending_days,
        relatedLeaveRequestId: lc.leaveRequestId || null,
        actorUserId: lc.actorUserId || null,
        actorKind: lc.actorKind || 'admin',
        remarks: lc.remarks || null,
        metadataJson: lc.metadataJson || null,
      });
    } else {
      await insertLeaveBalanceLedger(client, {
        userId,
        leaveType: ledgerType,
        action: lc.action || 'forced_leave_deduction',
        affectedBucket: 'used',
        daysChanged: afterSnap.used_days - beforeSnap.used_days,
        oldValue: beforeSnap.used_days,
        newValue: afterSnap.used_days,
        relatedLeaveRequestId: lc.leaveRequestId || null,
        actorUserId: lc.actorUserId || null,
        actorKind: lc.actorKind || 'admin',
        remarks: lc.remarks || null,
        metadataJson: lc.metadataJson || null,
      });
    }
  }

  return remainingOut;
}

async function reservePendingLeaveBalance(
  client,
  { userId, leaveTypeName, days, leaveRequestId, actorUserId, actorKind = 'user', action = 'leave_submitted', remarks = null, metadataJson = null }
) {
  const d = days != null ? parseFloat(days) : 0;
  if (!userId || !leaveTypeName || !Number.isFinite(d) || d <= 0) return null;
  const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
  if (!ledgerType) return null;

  await assertEnoughAvailableForPendingReservation(client, userId, leaveTypeName, d);
  const beforeSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
  await client.query(
    `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
     VALUES ($1::uuid, $2::text, 0, 0, $3::numeric, 0, now()::date, now()::date, now(), now())
     ON CONFLICT (user_id, leave_type)
     DO UPDATE SET pending_days = COALESCE(leave_balances.pending_days, 0) + EXCLUDED.pending_days,
                   updated_at = now()`,
    [userId, ledgerType, d]
  );
  const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
  await insertLeaveBalanceLedger(client, {
    userId,
    leaveType: ledgerType,
    action,
    affectedBucket: 'pending',
    daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
    oldValue: beforeSnap.pending_days,
    newValue: afterSnap.pending_days,
    relatedLeaveRequestId: leaveRequestId || null,
    actorUserId: actorUserId || null,
    actorKind,
    remarks,
    metadataJson: metadataJson || { number_of_days: d },
  });
  return ledgerType;
}

async function releasePendingLeaveBalance(
  client,
  { userId, leaveTypeName, days, leaveRequestId, actorUserId, actorKind = 'admin', action, remarks = null, metadataJson = null }
) {
  const d = days != null ? parseFloat(days) : 0;
  if (!userId || !leaveTypeName || !Number.isFinite(d) || d <= 0) return null;
  const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
  if (!ledgerType) return null;

  const beforeSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
  await client.query(
    `UPDATE leave_balances
     SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
         updated_at = now()
     WHERE user_id = $1::uuid AND leave_type = $2::text`,
    [userId, ledgerType, d]
  );
  const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
  await insertLeaveBalanceLedger(client, {
    userId,
    leaveType: ledgerType,
    action,
    affectedBucket: 'pending',
    daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
    oldValue: beforeSnap.pending_days,
    newValue: afterSnap.pending_days,
    relatedLeaveRequestId: leaveRequestId || null,
    actorUserId: actorUserId || null,
    actorKind,
    remarks,
    metadataJson,
  });
  return ledgerType;
}

async function applyApprovedLeaveToDtr(client, userId, leaveRequestId, startDateStr, endDateStr) {
  if (!userId || !leaveRequestId || !startDateStr || !endDateStr) return;
  await client.query(
    `INSERT INTO dtr_daily_summary (
        employee_id,
        attendance_date,
        status,
        leave_request_id,
        source,
        created_at,
        updated_at
      )
      SELECT
        $1::uuid AS employee_id,
        gs::date AS attendance_date,
        'on_leave'::text AS status,
        $2::uuid AS leave_request_id,
        'adjusted'::text AS source,
        now() AS created_at,
        now() AS updated_at
      FROM generate_series($3::date, $4::date, '1 day'::interval) AS gs
      -- Shift-aware leave marking:
      -- 1) resolve effective assignment for each date
      -- 2) use shift.working_days when present
      -- 3) fallback to Mon-Fri only when assignment/shift schedule is unavailable
      LEFT JOIN LATERAL (
        SELECT a.id AS assignment_id, a.shift_id
        FROM assignments a
        WHERE a.employee_id = $1::uuid
          AND (a.is_active IS NULL OR a.is_active = true)
          AND a.effective_from <= gs::date
          AND (a.effective_to IS NULL OR a.effective_to >= gs::date)
        ORDER BY a.effective_from DESC
        LIMIT 1
      ) eff ON TRUE
      LEFT JOIN shifts s ON s.id = eff.shift_id
      WHERE (
        CASE
          WHEN s.working_days IS NOT NULL AND array_length(s.working_days, 1) > 0
            THEN EXTRACT(ISODOW FROM gs::date)::int = ANY(s.working_days)
          ELSE EXTRACT(ISODOW FROM gs::date) < 6
        END
      )
      ON CONFLICT (employee_id, attendance_date)
      DO UPDATE SET
        status = 'on_leave',
        leave_request_id = EXCLUDED.leave_request_id,
        source = 'adjusted',
        updated_at = now()
      WHERE dtr_daily_summary.status IS DISTINCT FROM 'present'`,
    [userId, leaveRequestId, startDateStr, endDateStr]
  );
}

// ============================
// EMPLOYEE ENDPOINTS
// ============================

// GET /api/leave/working-days?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
// Counts leave days using the employee's effective shift working days and holidays.
router.get('/working-days', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const startStr = toIsoDateStr(req.query.start_date || req.query.startDate);
  const endStr = toIsoDateStr(req.query.end_date || req.query.endDate);
  if (!startStr || !endStr) {
    return res.status(400).json({ error: 'start_date and end_date are required' });
  }
  try {
    const result = await computeEmployeeLeaveWorkingDays(pool, userId, startStr, endStr);
    if (result.days == null) {
      return res.status(400).json({ error: 'Invalid date range' });
    }
    res.json({
      start_date: startStr,
      end_date: endStr,
      working_days_applied: result.days,
      counted_dates: result.countedDates,
      holiday_dates: result.holidayDates || [],
      schedule_source: result.scheduleSource,
    });
  } catch (err) {
    console.error('[leave GET /working-days]', err);
    res.status(500).json({ error: 'Failed to compute working days' });
  }
});

// POST /api/leave/draft
router.post('/draft', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const {
      leave_type,
      start_date,
      end_date,
      reason,
      details,
      ...rest
    } = req.body || {};

    const startStr = toIsoDateStr(start_date);
    const endStr = toIsoDateStr(end_date);
    // #12: holiday-aware count — client connected below inside try.
    // We'll compute properly inside the transaction using the client.
    const days = computeNumberOfDaysSync(startStr, endStr);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const workingDayResult = await computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr);
      const effectiveDaysDraft = workingDayResult.days ?? days;
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (!leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
      const eventDates = readLeaveEventDates(payloadDetails);
      const leaveRule = await getLeaveTypeDefinition(client, leave_type);
      const userSex = await getUserSexForLeaveValidation(client, userId);
      const validation = validateEmployeeLeaveRequestWithRule({
        rule: leaveRule,
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: effectiveDaysDraft,
        hasAttachment: false,
        userSex,
        maternityDeliveryType,
        eventDates,
        enforceEventDateRules: false,
      });
      if (!validation.valid) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: validation.error });
      }
      if (startStr && endStr) {
        const hasOverlap = await hasOverlappingLeaveRequest(client, userId, startStr, endStr, null);
        if (hasOverlap) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Overlapping leave request exists' });
        }
      }
      const q = await client.query(
        `INSERT INTO leave_requests (
            employee_id,
            user_id,
            leave_type_id,
            start_date,
            end_date,
            total_days,
            number_of_days,
            reason,
            details,
            status,
            created_at,
            updated_at
          )
          VALUES ($1::uuid, $1::uuid, $2::uuid, $3::date, $4::date, $5::numeric, $5::numeric, $6::text, $7::jsonb, 'draft', now(), now())
          RETURNING *`,
        [userId, leaveTypeId, startStr, endStr, effectiveDaysDraft, reason || null, payloadDetails]
      );

      const row = q.rows[0];
      // FIX #2: Only one history row on create (removed duplicate 'created' + 'saved_draft' pair).
      await insertLeaveRequestHistory(client, {
        leaveRequestId: row.id,
        action: 'saved_draft',
        fromStatus: null,
        toStatus: 'draft',
        actedBy: userId,
        remarks: reason || null,
        metadataJson: {
          leave_type: leave_type || null,
          start_date: startStr,
          end_date: endStr,
          number_of_days: effectiveDaysDraft,
        },
      });
      const typeName = leave_type ? String(leave_type) : null;
      await client.query('COMMIT');
      const mapped = mapLeaveRowToApi({ ...row, leave_type_name: typeName });
      broadcastLeaveUpdated('saved_draft', mapped);
      res.status(201).json(mapped);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[leave POST /draft]', err);
    res.status(500).json({ error: 'Failed to save draft' });
  }
});

// POST /api/leave/submit
router.post('/submit', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const {
      leave_type,
      start_date,
      end_date,
      reason,
      details,
      ...rest
    } = req.body || {};

    const startStr = toIsoDateStr(start_date);
    const endStr = toIsoDateStr(end_date);
    if (!startStr || !endStr) return res.status(400).json({ error: 'start_date and end_date are required' });
    const days = computeNumberOfDaysSync(startStr, endStr); // holiday-aware recomputed inside tx

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const workingDayResult = await computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr);
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (!leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
      const eventDates = readLeaveEventDates(payloadDetails);

      // Validate the server-computed, holiday-aware working day count.
      const effectiveDaysSubmit = workingDayResult.days ?? days;
      if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
      }

      const leaveRule = await getLeaveTypeDefinition(client, leave_type);
      const userSex = await getUserSexForLeaveValidation(client, userId);
      const validation = validateEmployeeLeaveRequestWithRule({
        rule: leaveRule,
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: effectiveDaysSubmit,
        hasAttachment: false,
        userSex,
        maternityDeliveryType,
        eventDates,
        enforceEventDateRules: true,
      });
      if (!validation.valid) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: validation.error });
      }

      // FIX #6 (backend): POST /submit creates a new record — no attachment yet.
      // Block when a required attachment is missing (incl. sick leave ≥5 working days → medical certificate).
      if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDaysSubmit, false)) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          error: `${leave_type} requires a supporting document. Please save a draft, upload the document, then submit.`,
        });
      }

      const hasOverlap = await hasOverlappingLeaveRequest(client, userId, startStr, endStr, null);
      if (hasOverlap) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Overlapping leave request exists' });
      }

      await assertSpecialPrivilegeLeaveAnnualLimit(client, {
        userId,
        leaveTypeName: String(leave_type),
        startStr,
        endStr,
      });

      const q = await client.query(
        `INSERT INTO leave_requests (
            employee_id,
            user_id,
            leave_type_id,
            start_date,
            end_date,
            total_days,
            number_of_days,
            reason,
            details,
            status,
            created_at,
            updated_at
          )
          VALUES ($1::uuid, $1::uuid, $2::uuid, $3::date, $4::date, $5::numeric, $5::numeric, $6::text, $7::jsonb, 'draft', now(), now())
          RETURNING *`,
        [userId, leaveTypeId, startStr, endStr, effectiveDaysSubmit, reason || null, payloadDetails]
      );

      const row = q.rows[0];

      // Two-stage workflow: determine initial submitted status.
      const deptHeadInfo = await getDepartmentHeadForEmployee(client, userId);
      const submitStatus = deptHeadInfo ? 'pending_department_head' : 'pending_hr';

      await client.query(
        `UPDATE leave_requests SET status = $1 WHERE id = $2`,
        [submitStatus, row.id]
      );
      row.status = submitStatus;

      await insertLeaveRequestHistory(client, {
        leaveRequestId: row.id,
        action: 'submitted',
        fromStatus: null,
        toStatus: submitStatus,
        actedBy: userId,
        remarks: reason || null,
        metadataJson: {
          leave_type: leave_type || null,
          start_date: startStr,
          end_date: endStr,
          number_of_days: effectiveDaysSubmit,
          department_head: deptHeadInfo ? deptHeadInfo.departmentHeadUserId : null,
        },
      });
      // FIX #5a: Increment pending_days on direct submit (no existing draft ID).
      const pendingDeltaSubmit = effectiveDaysSubmit;
      if (pendingDeltaSubmit != null && pendingDeltaSubmit > 0) {
        const leaveTypeName = leave_type ? String(leave_type) : null;
        if (leaveTypeName) {
          await reservePendingLeaveBalance(client, {
            userId,
            leaveTypeName,
            days: pendingDeltaSubmit,
            leaveRequestId: row.id,
            actorUserId: userId,
            actorKind: 'user',
            action: 'leave_submitted',
            metadataJson: { number_of_days: pendingDeltaSubmit },
          });
        }
      }
      const typeName = leave_type ? String(leave_type) : null;
      await client.query('COMMIT');
      const nameRow = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      const submitEmpName = nameRow.rows[0]?.full_name || 'Employee';
      notifySafe(() =>
        leaveNotifications.notifyAfterSubmit(pool, {
          leaveRequestId: row.id,
          status: row.status,
          employeeUserId: userId,
          employeeName: submitEmpName,
          leaveTypeName: typeName,
          startDateStr: startStr,
          endDateStr: endStr,
          departmentHeadUserId: deptHeadInfo?.departmentHeadUserId ?? null,
        })
      );
      const mapped = mapLeaveRowToApi({ ...row, leave_type_name: typeName });
      broadcastLeaveUpdated('submitted', mapped);
      res.status(201).json(mapped);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[leave POST /submit]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to submit leave request' });
  }
});

// POST /api/leave/submit-with-attachment
// Creates a submitted leave request and links the supporting document in one action.
router.post('/submit-with-attachment', protect, uploadLeaveAttachmentMemoryMw, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded. Allowed: PDF, JPG, JPEG, PNG (max 10MB).' });
  }

  let storedAttachmentRelPath = null;
  try {
    const body = { ...(req.body || {}) };
    body.details = parseJsonBodyField(body.details);
    const {
      leave_type,
      start_date,
      end_date,
      reason,
      details,
      ...rest
    } = body;

    const startStr = toIsoDateStr(start_date);
    const endStr = toIsoDateStr(end_date);
    if (!startStr || !endStr) {
      return res.status(400).json({ error: 'start_date and end_date are required' });
    }
    const days = computeNumberOfDaysSync(startStr, endStr);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const workingDayResult = await computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr);
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (!leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }

      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
      const eventDates = readLeaveEventDates(payloadDetails);

      const effectiveDaysSubmit = workingDayResult.days ?? days;
      if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
      }

      const leaveRule = await getLeaveTypeDefinition(client, leave_type);
      const userSex = await getUserSexForLeaveValidation(client, userId);
      const validation = validateEmployeeLeaveRequestWithRule({
        rule: leaveRule,
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: effectiveDaysSubmit,
        hasAttachment: true,
        userSex,
        maternityDeliveryType,
        eventDates,
        enforceEventDateRules: true,
      });
      if (!validation.valid) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: validation.error });
      }

      if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDaysSubmit, true)) {
        await client.query('ROLLBACK');
        const label = leaveRule?.display_name || leave_type || 'This leave type';
        return res.status(400).json({
          error: `${label} requires a supporting document before submission.`,
        });
      }

      const hasOverlap = await hasOverlappingLeaveRequest(client, userId, startStr, endStr, null);
      if (hasOverlap) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Overlapping leave request exists' });
      }

      await assertSpecialPrivilegeLeaveAnnualLimit(client, {
        userId,
        leaveTypeName: String(leave_type),
        startStr,
        endStr,
      });

      const storedAttachment = storedLeaveAttachmentFromMemoryFile(req.file);
      if (!storedAttachment) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Could not read uploaded attachment.' });
      }
      storedAttachmentRelPath = storedAttachment.relPath;

      const q = await client.query(
        `INSERT INTO leave_requests (
            employee_id,
            user_id,
            leave_type_id,
            start_date,
            end_date,
            total_days,
            number_of_days,
            reason,
            details,
            attachment_name,
            attachment_path,
            attachment_mime_type,
            attachment_uploaded_at,
            status,
            created_at,
            updated_at
          )
          VALUES (
            $1::uuid, $1::uuid, $2::uuid, $3::date, $4::date,
            $5::numeric, $5::numeric, $6::text, $7::jsonb,
            $8::text, $9::text, $10::text, now(),
            'draft', now(), now()
          )
          RETURNING *`,
        [
          userId,
          leaveTypeId,
          startStr,
          endStr,
          effectiveDaysSubmit,
          reason || null,
          payloadDetails,
          storedAttachment.originalName,
          storedAttachment.relPath,
          storedAttachment.mimeType,
        ]
      );

      const row = q.rows[0];
      const deptHeadInfo = await getDepartmentHeadForEmployee(client, userId);
      const submitStatus = deptHeadInfo ? 'pending_department_head' : 'pending_hr';

      await client.query(
        `UPDATE leave_requests SET status = $1, updated_at = now() WHERE id = $2`,
        [submitStatus, row.id]
      );
      row.status = submitStatus;

      await insertLeaveRequestHistory(client, {
        leaveRequestId: row.id,
        action: 'submitted',
        fromStatus: null,
        toStatus: submitStatus,
        actedBy: userId,
        remarks: reason || null,
        metadataJson: {
          leave_type: leave_type || null,
          start_date: startStr,
          end_date: endStr,
          number_of_days: effectiveDaysSubmit,
          attachment_name: storedAttachment.originalName,
          department_head: deptHeadInfo ? deptHeadInfo.departmentHeadUserId : null,
        },
      });

      if (effectiveDaysSubmit != null && effectiveDaysSubmit > 0) {
        const leaveTypeName = leave_type ? String(leave_type) : null;
        if (leaveTypeName) {
          await reservePendingLeaveBalance(client, {
            userId,
            leaveTypeName,
            days: effectiveDaysSubmit,
            leaveRequestId: row.id,
            actorUserId: userId,
            actorKind: 'user',
            action: 'leave_submitted',
            metadataJson: {
              number_of_days: effectiveDaysSubmit,
              attachment_name: storedAttachment.originalName,
            },
          });
        }
      }

      const typeName = leave_type ? String(leave_type) : null;
      await client.query('COMMIT');
      storedAttachmentRelPath = null;

      const nameRow = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
      const submitEmpName = nameRow.rows[0]?.full_name || 'Employee';
      notifySafe(() =>
        leaveNotifications.notifyAfterSubmit(pool, {
          leaveRequestId: row.id,
          status: row.status,
          employeeUserId: userId,
          employeeName: submitEmpName,
          leaveTypeName: typeName,
          startDateStr: startStr,
          endDateStr: endStr,
          departmentHeadUserId: deptHeadInfo?.departmentHeadUserId ?? null,
        })
      );
      const mapped = mapLeaveRowToApi({ ...row, leave_type_name: typeName });
      broadcastLeaveUpdated('submitted', mapped);
      res.status(201).json(mapped);
    } catch (e) {
      try {
        await client.query('ROLLBACK');
      } catch (_) { }
      cleanupStoredLeaveAttachment(storedAttachmentRelPath);
      storedAttachmentRelPath = null;
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    cleanupStoredLeaveAttachment(storedAttachmentRelPath);
    console.error('[leave POST /submit-with-attachment]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to submit leave request with attachment' });
  }
});

// PUT /api/leave/:id (employee updates draft/returned)
router.put('/:id', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const existing = await pool.query(
      'SELECT id, status FROM leave_requests WHERE id = $1 AND (user_id = $2 OR employee_id = $2)',
      [id, userId]
    );
    if (existing.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const status = existing.rows[0].status;

    const { leave_type, start_date, end_date, reason, details, status: desiredStatus, ...rest } = req.body || {};
    let nextStatus;
    let historyAction;
    try {
      ({ nextStatus, historyAction } = validateEmployeeUpdateTransition({
        currentStatus: status,
        desiredStatus,
      }));
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }
    const startStr = toIsoDateStr(start_date);
    const endStr = toIsoDateStr(end_date);
    const days = computeNumberOfDaysSync(startStr, endStr);
    let effectiveDays = days;

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      // FIX #1: isNotEmpty is Dart/Swift, not JS. Use .length > 0 instead.
      if (leave_type != null && String(leave_type).trim().length > 0 && !leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      const maternityDeliveryType = readMaternityDeliveryType(payloadDetails);
      const eventDates = readLeaveEventDates(payloadDetails);
      if (startStr && endStr) {
        const workingDayResult = await computeEmployeeLeaveWorkingDays(client, userId, startStr, endStr);
        effectiveDays = workingDayResult.days ?? days;

        // Validate the server-computed, holiday-aware working day count.
        if (effectiveDays == null || effectiveDays <= 0) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
        }
      }

      if (leave_type && startStr && endStr) {

        const leaveRule = await getLeaveTypeDefinition(client, leave_type);
        const userSex = await getUserSexForLeaveValidation(client, userId);
        const validation = validateEmployeeLeaveRequestWithRule({
          rule: leaveRule,
          leaveType: leave_type,
          otherPurpose: otherPurpose || null,
          startDateStr: startStr,
          endDateStr: endStr,
          numberOfDays: effectiveDays,
          hasAttachment: false,
          userSex,
          maternityDeliveryType,
          eventDates,
          enforceEventDateRules:
            nextStatus === 'pending' ||
            nextStatus === 'pending_department_head' ||
            nextStatus === 'pending_hr',
        });
        if (!validation.valid) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: validation.error });
        }

        // FIX #6 (backend): When transitioning to a pending status via PUT, check attachment.
        if (nextStatus === 'pending' || nextStatus === 'pending_department_head' || nextStatus === 'pending_hr') {
          const existingRow = await client.query(
            'SELECT attachment_path FROM leave_requests WHERE id = $1',
            [id]
          );
          const hasAttachment = !!(existingRow.rows[0]?.attachment_path);
          if (mustBlockMissingAttachment(leaveRule, leave_type, effectiveDays, hasAttachment)) {
            await client.query('ROLLBACK');
            return res.status(400).json({
              error: `${leave_type} requires a supporting document before submission. Please upload one first.`,
            });
          }

          // Two-stage workflow: resolve actual target status.
          const deptHeadInfo = await getDepartmentHeadForEmployee(client, userId);
          nextStatus = deptHeadInfo ? 'pending_department_head' : 'pending_hr';
        }
      }
      // Prevent overlapping ranges when dates are being set/changed.
      if (startStr && endStr) {
        const hasOverlap = await hasOverlappingLeaveRequest(client, userId, startStr, endStr, id);
        if (hasOverlap) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Overlapping leave request exists' });
        }
      }

      if (
        (nextStatus === 'pending' || nextStatus === 'pending_department_head' || nextStatus === 'pending_hr') &&
        leave_type &&
        startStr &&
        endStr
      ) {
        await assertSpecialPrivilegeLeaveAnnualLimit(client, {
          userId,
          leaveTypeName: String(leave_type),
          startStr,
          endStr,
          excludeId: id,
        });
      }

      const q = await client.query(
        `UPDATE leave_requests
         SET leave_type_id = COALESCE($1::uuid, leave_type_id),
             start_date = COALESCE($2::date, start_date),
             end_date = COALESCE($3::date, end_date),
             total_days = COALESCE($4::numeric, total_days),
             number_of_days = COALESCE($4::numeric, number_of_days),
             reason = $5::text,
             details = COALESCE($6::jsonb, details),
             status = $9::text,
             updated_at = now()
         WHERE id = $7 AND (user_id = $8 OR employee_id = $8)
         RETURNING *`,
        [leaveTypeId, startStr, endStr, effectiveDays, reason || null, payloadDetails, id, userId, nextStatus]
      );
      const row = q.rows[0];
      await insertLeaveRequestHistory(client, {
        leaveRequestId: row.id,
        action: historyAction,
        fromStatus: status,
        toStatus: nextStatus,
        actedBy: userId,
        remarks: reason || null,
        metadataJson: {
          leave_type: leave_type || null,
          start_date: startStr,
          end_date: endStr,
          number_of_days: effectiveDays,
        },
      });
      // FIX #5b: Update pending_days when status transitions to a pending status via PUT.
      const leaveTypeName = leave_type ? String(leave_type) : null;
      const isPendingTarget = nextStatus === 'pending' || nextStatus === 'pending_department_head' || nextStatus === 'pending_hr';
      const wasPending = status === 'pending' || status === 'pending_department_head' || status === 'pending_hr';
      if (leaveTypeName && effectiveDays != null && effectiveDays > 0) {
        if (isPendingTarget && !wasPending) {
          // Moving INTO a pending status: increment pending_days.
          const putAction =
            historyAction === 'resubmitted' ? 'leave_resubmitted' : 'leave_submitted';
          await reservePendingLeaveBalance(client, {
            userId,
            leaveTypeName,
            days: effectiveDays,
            leaveRequestId: row.id,
            actorUserId: userId,
            actorKind: 'user',
            action: putAction,
            metadataJson: { number_of_days: effectiveDays, history_action: historyAction },
          });
        }
      }
      await client.query('COMMIT');
      if (
        (historyAction === 'submitted' || historyAction === 'resubmitted') &&
        ['pending', 'pending_department_head', 'pending_hr'].includes(row.status)
      ) {
        const dhPut = await getDepartmentHeadForEmployee(pool, userId);
        const namePut = await pool.query('SELECT full_name FROM users WHERE id = $1', [userId]);
        const putEmpName = namePut.rows[0]?.full_name || 'Employee';
        notifySafe(() =>
          leaveNotifications.notifyAfterSubmit(pool, {
            leaveRequestId: row.id,
            status: row.status,
            employeeUserId: userId,
            employeeName: putEmpName,
            leaveTypeName: leaveTypeName,
            startDateStr: startStr,
            endDateStr: endStr,
            departmentHeadUserId:
              row.status === 'pending_department_head' ? dhPut?.departmentHeadUserId ?? null : null,
          })
        );
      }
      const mapped = mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName });
      broadcastLeaveUpdated(historyAction || 'updated', mapped);
      res.json(mapped);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[leave PUT /:id]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to update leave request' });
  }
});

// PATCH /api/leave/:id/cancel
router.patch('/:id/cancel', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const reason = (req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const q = await client.query(
      'SELECT id, status FROM leave_requests WHERE id = $1 AND (user_id = $2 OR employee_id = $2)',
      [id, userId]
    );
    if (q.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found' });
    }
    const status = q.rows[0].status;

    const { nextStatus, historyAction } = validateEmployeeCancelTransition({
      currentStatus: status,
    });

    const cancelledReq = await client.query(
      `UPDATE leave_requests
       SET status = 'cancelled',
           details = COALESCE(details, '{}'::jsonb) || jsonb_build_object('cancel_reason', $3::text),
           updated_at = now()
       WHERE id = $1 AND (user_id = $2 OR employee_id = $2)
       RETURNING COALESCE(number_of_days, total_days) AS days, user_id, employee_id, leave_type_id`,
      [id, userId, reason]
    );

    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: status,
      toStatus: nextStatus,
      actedBy: userId,
      remarks: reason || null,
      metadataJson: null,
    });

    // FIX #5c: Decrement pending_days on cancel (only if it was in a pending status — not draft).
    if (status === 'pending' || status === 'pending_department_head' || status === 'pending_hr') {
      const cancelRow = cancelledReq.rows[0];
      const cancelDays = cancelRow?.days != null ? parseFloat(cancelRow.days) : null;
      const cancelUserId = cancelRow?.user_id || cancelRow?.employee_id;
      if (cancelDays && cancelDays > 0 && cancelUserId) {
        const ltRow = await client.query(
          'SELECT name FROM leave_types WHERE id = $1',
          [cancelRow.leave_type_id]
        );
        const ltName = ltRow.rows[0]?.name || null;
        if (ltName) {
          await releasePendingLeaveBalance(client, {
            userId: cancelUserId,
            leaveTypeName: ltName,
            days: cancelDays,
            leaveRequestId: id,
            actorUserId: userId,
            actorKind: 'user',
            action: 'leave_cancelled',
            remarks: reason || null,
            metadataJson: { cancel_days: cancelDays },
          });
        }
      }
    }

    const out = await client.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );

    await client.query('COMMIT');
    const mappedCancel = mapLeaveRowToApi(out.rows[0]);
    if (status === 'pending' || status === 'pending_department_head' || status === 'pending_hr') {
      notifySafe(async () => {
        const dhCancel = await getDepartmentHeadForEmployee(pool, userId);
        await leaveNotifications.notifyStakeholdersLeaveCancelled(pool, {
          leaveRequestId: id,
          employeeUserId: userId,
          employeeName: mappedCancel.employee_name,
          previousStatus: status,
          leaveTypeName: mappedCancel.leave_type_name || mappedCancel.leave_type,
          startDateStr: mappedCancel.start_date,
          endDateStr: mappedCancel.end_date,
          cancelReason: reason,
          departmentHeadUserId:
            status === 'pending_department_head' ? dhCancel?.departmentHeadUserId ?? null : null,
        });
      });
    }
    broadcastLeaveUpdated('cancelled', mappedCancel, { previousStatus: status });
    res.json(mappedCancel);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('[leave PATCH /:id/cancel]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to cancel leave request' });
  } finally {
    client.release();
  }
});

// GET /api/leave/my
// GET /api/leave/my
router.get('/my', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    // FIX #14 (Phase 4 preview): Pagination on /my with a safe default cap.
    const limitRaw = req.query?.limit ? parseInt(req.query.limit, 10) : 100;
    const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : 100;
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       WHERE (lr.user_id = $1 OR lr.employee_id = $1)
         AND ($2::text IS NULL OR lr.status = $2)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT $3`,
      [userId, status, limit]
    );
    res.json(rows.rows.map(mapLeaveRowToApi));
  } catch (err) {
    console.error('[leave GET /my]', err);
    res.status(500).json({ error: 'Failed to fetch my leave requests' });
  }
});

// GET /api/leave/signatories?employee_id=uuid
// Printable leave form signatories:
// 7.A = active employee with Administrative Officer V position.
// 7.B = department head of the requesting employee's current department.
router.get('/signatories', protect, async (req, res) => {
  const requesterId = req.user?.id;
  const role = req.user?.role;
  if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
  const employeeId = (req.query?.employee_id || '').toString().trim();
  if (!employeeId) return res.status(400).json({ error: 'employee_id is required' });

  try {
    const privileged = role === 'admin' || role === 'hr';
    if (!privileged && requesterId !== employeeId) {
      const requesterDept = await isDepartmentHead(pool, requesterId);
      const employeeDept = await getEmployeeDepartment(pool, employeeId);
      if (
        !requesterDept.isDeptHead ||
        !requesterDept.departmentId ||
        !employeeDept?.departmentId ||
        requesterDept.departmentId !== employeeDept.departmentId
      ) {
        return res.status(403).json({ error: 'Not authorized to view leave form signatories' });
      }
    }

    const hrCertifier = await findActiveEmployeeByPositionTitle(
      pool,
      HR_CERTIFICATION_POSITION_TITLE
    );
    const departmentHeadInfo = await getDepartmentHeadForEmployee(pool, employeeId);
    const departmentHeadProfile = departmentHeadInfo?.departmentHeadUserId
      ? await findActiveAssignmentProfileByUserId(pool, departmentHeadInfo.departmentHeadUserId)
      : null;

    res.json({
      hr_certification_officer: mapSignatoryProfile(hrCertifier),
      recommendation_officer: departmentHeadProfile
        ? mapSignatoryProfile({
            ...departmentHeadProfile,
            department_id: departmentHeadInfo.departmentId || departmentHeadProfile.department_id,
            department_name:
              departmentHeadInfo.departmentName || departmentHeadProfile.department_name,
          })
        : null,
    });
  } catch (err) {
    console.error('[leave GET /signatories]', err);
    res.status(500).json({ error: 'Failed to fetch leave form signatories' });
  }
});

// ============================
// ADMIN ENDPOINTS
// ============================

// POST /api/leave/admin/forced-leave-deduction
// Admin/HR-only: applies a direct vacation leave balance deduction (no leave request row).
router.post('/admin/forced-leave-deduction', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const userId = (req.body?.user_id || '').toString().trim();
  const daysRaw = req.body?.days_to_deduct ?? req.body?.daysToDeduct;
  const days = daysRaw != null && daysRaw !== '' ? parseFloat(daysRaw) : NaN;
  const yearRaw = req.body?.year ?? req.body?.deduction_year ?? req.body?.deductionYear;
  const yearText = yearRaw != null ? String(yearRaw).trim() : '';
  const year = /^\d{4}$/.test(yearText) ? parseInt(yearText, 10) : NaN;
  const remarks = (req.body?.remarks || '').toString().trim() || null;
  const allowNegative = req.body?.allow_negative_balance === true;
  if (!userId) return res.status(400).json({ error: 'user_id is required' });
  if (!Number.isFinite(days) || days <= 0) {
    return res.status(400).json({ error: 'days_to_deduct must be greater than 0' });
  }
  const maxAllowedYear = new Date().getFullYear() + 1;
  if (!Number.isInteger(year) || year < 1900 || year > maxAllowedYear) {
    return res.status(400).json({ error: `year must be between 1900 and ${maxAllowedYear}` });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const userQ = await client.query(
      'SELECT id FROM users WHERE id = $1::uuid AND (is_active IS NULL OR is_active = true) LIMIT 1',
      [userId]
    );
    if (userQ.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Target employee not found or inactive' });
    }
    const duplicateQ = await client.query(
      `SELECT id, created_at
       FROM leave_balance_ledger
       WHERE user_id = $1::uuid
         AND leave_type = 'vacationLeave'
         AND action = 'forced_leave_deduction'
         AND (
           metadata_json->>'year' = $2::text
           OR metadata_json->>'deduction_year' = $2::text
         )
       LIMIT 1`,
      [userId, String(year)]
    );
    if (duplicateQ.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: `Year-end forced leave deduction for ${year} has already been applied for this employee.`,
        year,
        existing_ledger_id: duplicateQ.rows[0].id,
        applied_at: duplicateQ.rows[0].created_at,
      });
    }
    const remaining = await upsertLeaveBalanceDeduction(
      client,
      userId,
      'mandatoryForcedLeave',
      days,
      {
        allowNegative,
        ledgerContext: {
          action: 'forced_leave_deduction',
          actorUserId: reviewerId,
          actorKind: 'admin',
          remarks,
          metadataJson: {
            source: 'forced_leave_deduction',
            year,
            deduction_year: year,
            requested_leave_type: 'mandatoryForcedLeave',
            deducted_days: days,
            allow_negative_balance: allowNegative,
          },
        },
      }
    );
    const balSnap = await client.query(
      `SELECT
         COALESCE(earned_days, 0) - COALESCE(used_days, 0) + COALESCE(adjusted_days, 0) AS rem,
         COALESCE(earned_days, 0) - COALESCE(used_days, 0) + COALESCE(adjusted_days, 0) - COALESCE(pending_days, 0) AS avail
       FROM leave_balances
       WHERE user_id = $1::uuid AND leave_type = 'vacationLeave'
       LIMIT 1`,
      [userId]
    );
    const remainingAfter = balSnap.rows.length > 0 ? parseFloat(balSnap.rows[0].rem ?? 0) : remaining;
    const availableAfter = balSnap.rows.length > 0 ? parseFloat(balSnap.rows[0].avail ?? 0) : remainingAfter;

    await client.query('COMMIT');
    notifySafe(() =>
      leaveNotifications.notifyForcedLeaveDeductionApplied(pool, {
        employeeUserId: userId,
        deductedDays: days,
        remainingDays: availableAfter,
        year,
        remarks,
      })
    );
    const response = {
      user_id: userId,
      leave_type: 'vacationLeave',
      deducted_days: days,
      year,
      remaining_days: remainingAfter,
      available_days: availableAfter,
      remarks,
      applied_at: new Date().toISOString(),
    };
    broadcastLeaveUpdated('forced_leave_deduction', { user_id: userId }, response);
    res.status(201).json(response);
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    console.error('[leave POST /admin/forced-leave-deduction]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to apply forced leave deduction' });
  } finally {
    client.release();
  }
});

// POST /api/leave/admin/monthly-accrual — admin/HR: apply VL + SL monthly accrual (1.25 days each per month credited)
// Body/query (optional): dry_run, target_month (YYYY-MM), max_catch_up_months (default 1)
router.post('/admin/monthly-accrual', protect, requireAdminOrHr, async (req, res) => {
  try {
    const dryRun =
      req.body?.dry_run === true ||
      req.query?.dry_run === '1' ||
      req.query?.dry_run === 'true';
    const rawMax = req.body?.max_catch_up_months ?? req.query?.max_catch_up_months;
    const maxCatchUpMonths =
      rawMax != null && rawMax !== '' ? parseInt(String(rawMax), 10) : undefined;
    const targetMonth =
      req.body?.target_month ??
      req.body?.year_month ??
      req.query?.target_month ??
      req.query?.year_month;

    const result = await runLeaveMonthlyAccrual(pool, {
      dryRun,
      maxCatchUpMonths: Number.isFinite(maxCatchUpMonths) ? maxCatchUpMonths : undefined,
      targetMonth: targetMonth ? String(targetMonth).trim() : undefined,
    });
    if (!result.dryRun && (result.rowsUpdated > 0 || result.missingBalanceRowsCreated > 0)) {
      const affectedUserIds = [
        ...new Set(
          (Array.isArray(result.details) ? result.details : [])
            .filter((item) => item.action === 'applied' || item.created_balance_row === true)
            .map((item) => item.user_id)
            .filter(Boolean)
            .map((id) => String(id))
        ),
      ];
      if (affectedUserIds.length > 0) {
        broadcastLeaveUpdated('monthly_accrual', { user_id: affectedUserIds[0] }, {
          userIds: affectedUserIds,
          user_ids: affectedUserIds,
          targetYearMonth: result.targetYearMonth,
          rowsUpdated: result.rowsUpdated,
          rowsSkipped: result.rowsSkipped,
          missingBalanceRowsCreated: result.missingBalanceRowsCreated || 0,
          leaveTypes: result.leaveTypes,
          balanceChanged: true,
        });
      }
    }
    res.status(200).json(result);
  } catch (err) {
    console.error('[leave POST /admin/monthly-accrual]', err);
    res.status(400).json({ error: err.message || 'Monthly accrual failed' });
  }
});

// GET /api/leave (admin/HR list)
// Query params: status, leave_type, user_id, limit,
//               start_date_from, start_date_to, created_from, created_to
router.get('/', protect, requireAdminOrHr, async (req, res) => {
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    const leaveType = (req.query?.leave_type || '').toString().trim() || null;
    const userId = (req.query?.user_id || '').toString().trim() || null;
    const limitRaw = req.query?.limit ? parseInt(req.query.limit, 10) : null;
    const safeLimit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : null;

    // FIX #12 (Phase 4 preview wired here): Date range filters.
    const startDateFrom = (req.query?.start_date_from || '').toString().trim() || null;
    const startDateTo = (req.query?.start_date_to || '').toString().trim() || null;
    const createdFrom = (req.query?.created_from || '').toString().trim() || null;
    const createdTo = (req.query?.created_to || '').toString().trim() || null;

    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       WHERE ($1::text IS NULL OR lr.status = $1)
         AND ($2::text IS NULL OR lt.name = $2)
         AND ($3::uuid IS NULL OR lr.user_id = $3 OR lr.employee_id = $3)
         AND ($4::date IS NULL OR lr.start_date >= $4)
         AND ($5::date IS NULL OR lr.start_date <= $5)
         AND ($6::timestamptz IS NULL OR lr.created_at >= $6)
         AND ($7::timestamptz IS NULL OR lr.created_at <= $7)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       ${safeLimit ? 'LIMIT ' + safeLimit : ''}`,
      [status, leaveType, userId, startDateFrom, startDateTo, createdFrom, createdTo]
    );
    res.json(rows.rows.map(mapLeaveRowToApi));
  } catch (err) {
    console.error('[leave GET /]', err);
    res.status(500).json({ error: 'Failed to fetch leave requests' });
  }
});

// GET /api/leave/pending (admin/HR — returns pending_hr + legacy pending)
router.get('/pending', protect, requireAdminOrHr, async (_req, res) => {
  try {
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       WHERE lr.status IN ('pending', 'pending_hr')
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT 200`
    );
    res.json(rows.rows.map(mapLeaveRowToApi));
  } catch (err) {
    console.error('[leave GET /pending]', err);
    res.status(500).json({ error: 'Failed to fetch pending leave requests' });
  }
});

// ============================
// DEPARTMENT HEAD ENDPOINTS
// ============================

// GET /api/leave/department-head/check — is current user a department head?
router.get('/department-head/check', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const result = await isDepartmentHead(client, userId);
    res.json(result);
  } catch (err) {
    console.error('[leave GET /department-head/check]', err);
    res.status(500).json({ error: 'Failed to check department head status' });
  } finally {
    client.release();
  }
});

// GET /api/leave/department-head — list requests pending dept head approval
// plus requests already handled by the current department head.
router.get('/department-head', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const deptInfo = await isDepartmentHead(client, userId);
    if (!deptInfo.isDeptHead) {
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const status = (req.query?.status || '').toString().trim() || null;
    const leaveType = (req.query?.leave_type || '').toString().trim() || null;
    const employeeUserId = (req.query?.user_id || '').toString().trim() || null;
    const startDateFrom = (req.query?.start_date_from || '').toString().trim() || null;
    const startDateTo = (req.query?.start_date_to || '').toString().trim() || null;
    const createdFrom = (req.query?.created_from || '').toString().trim() || null;
    const createdTo = (req.query?.created_to || '').toString().trim() || null;
    const limitRaw = req.query?.limit ? parseInt(req.query.limit, 10) : 200;
    const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : 200;

    const rows = await client.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       LEFT JOIN users rv ON rv.id = COALESCE(lr.reviewer_id, lr.approved_by)
       LEFT JOIN LATERAL (
         SELECT h.action AS department_head_action,
                h.acted_by AS department_head_reviewer_id,
                actor.full_name AS department_head_reviewer_name,
                h.acted_at AS department_head_reviewed_at,
                h.remarks AS department_head_remarks
         FROM leave_request_history h
         LEFT JOIN users actor ON actor.id = h.acted_by
         WHERE h.leave_request_id = lr.id
           AND h.acted_by = $2::uuid
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE a.department_id = $1
         AND (
           lr.status = 'pending_department_head'
           OR dhh.department_head_reviewer_id IS NOT NULL
         )
         AND ($3::text IS NULL OR lr.status = $3)
         AND ($4::text IS NULL OR lt.name = $4)
         AND ($5::uuid IS NULL OR lr.user_id = $5 OR lr.employee_id = $5)
         AND ($6::date IS NULL OR lr.start_date >= $6)
         AND ($7::date IS NULL OR lr.start_date <= $7)
         AND ($8::timestamptz IS NULL OR lr.created_at >= $8)
         AND ($9::timestamptz IS NULL OR lr.created_at <= $9)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT ${limit}`,
      [
        deptInfo.departmentId,
        userId,
        status,
        leaveType,
        employeeUserId,
        startDateFrom,
        startDateTo,
        createdFrom,
        createdTo,
      ]
    );
    res.json(rows.rows.map(mapLeaveRowToApi));
  } catch (err) {
    console.error('[leave GET /department-head]', err);
    res.status(500).json({ error: 'Failed to fetch department head leave requests' });
  } finally {
    client.release();
  }
});

// PATCH /api/leave/:id/department-head-approve
router.patch('/:id/department-head-approve', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Verify caller is a department head
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const existing = await client.query(
      `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              lr.start_date, lr.end_date,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN assignments a ON a.employee_id = COALESCE(lr.user_id, lr.employee_id)
                              AND (a.is_active IS NULL OR a.is_active = true)
       WHERE lr.id = $1
         AND a.department_id = $2
       FOR UPDATE OF lr`,
      [id, deptInfo.departmentId]
    );
    if (existing.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found or not in your department' });
    }
    const r = existing.rows[0];
    const { nextStatus, historyAction } = validateDepartmentHeadTransition({
      currentStatus: r.status,
      desiredStatus: 'pending_hr',
    });
    await assertSpecialPrivilegeLeaveAnnualLimit(client, {
      userId: r.user_id || r.employee_id,
      leaveTypeName: r.leave_type_name || null,
      startStr: toIsoDateStr(r.start_date),
      endStr: toIsoDateStr(r.end_date),
      excludeId: id,
    });
    await client.query(
      `UPDATE leave_requests
       SET status = $2, reviewer_id = $3, reviewer_remarks = $4, reviewed_at = now(), updated_at = now()
       WHERE id = $1`,
      [id, nextStatus, reviewerId, remarks]
    );
    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: r.status,
      toStatus: nextStatus,
      actedBy: reviewerId,
      remarks,
      metadataJson: { department_id: deptInfo.departmentId },
    });
    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedDhApprove = mapLeaveRowToApi(out.rows[0]);
    notifySafe(() =>
      leaveNotifications.notifyDepartmentHeadApprovedForHr(pool, {
        leaveRequestId: id,
        employeeName: mappedDhApprove.employee_name,
        leaveTypeName: mappedDhApprove.leave_type_name || mappedDhApprove.leave_type,
        startDateStr: mappedDhApprove.start_date,
        endDateStr: mappedDhApprove.end_date,
      })
    );
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: r.user_id || r.employee_id,
        leaveRequestId: id,
        type: 'leave_endorsed_department_head',
        title: 'Leave request endorsed by department head',
        body: remarks
          ? `Your leave request has been endorsed by your department head and forwarded to HR for final approval. ${remarks}`
          : 'Your leave request has been endorsed by your department head and forwarded to HR for final approval.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    broadcastLeaveUpdated('department_head_approved', mappedDhApprove);
    res.json(mappedDhApprove);
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    console.error('[leave PATCH /:id/department-head-approve]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to approve (department head)' });
  } finally {
    client.release();
  }
});

// PATCH /api/leave/:id/department-head-reject
router.patch('/:id/department-head-reject', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const existing = await client.query(
      `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              COALESCE(lr.number_of_days, lr.total_days) AS days, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN assignments a ON a.employee_id = COALESCE(lr.user_id, lr.employee_id)
                              AND (a.is_active IS NULL OR a.is_active = true)
       WHERE lr.id = $1 AND a.department_id = $2
       FOR UPDATE OF lr`,
      [id, deptInfo.departmentId]
    );
    if (existing.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found or not in your department' });
    }
    const r = existing.rows[0];
    const { nextStatus, historyAction } = validateDepartmentHeadTransition({
      currentStatus: r.status,
      desiredStatus: 'rejected_by_department_head',
    });
    await client.query(
      `UPDATE leave_requests
       SET status = $2, reviewer_id = $3, reviewer_remarks = $4, reviewed_at = now(), updated_at = now()
       WHERE id = $1`,
      [id, nextStatus, reviewerId, remarks]
    );
    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: r.status,
      toStatus: nextStatus,
      actedBy: reviewerId,
      remarks,
      metadataJson: null,
    });
    // Decrement pending_days on dept head reject
    const rejectDays = r.days != null ? parseFloat(r.days) : null;
    const rejectUserId = r.user_id || r.employee_id;
    const rejectLtName = r.leave_type_name || null;
    if (rejectDays && rejectDays > 0 && rejectUserId && rejectLtName) {
      await releasePendingLeaveBalance(client, {
        userId: rejectUserId,
        leaveTypeName: rejectLtName,
        days: rejectDays,
        leaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'user',
        action: 'leave_rejected',
        remarks,
        metadataJson: { stage: 'department_head' },
      });
    }
    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedDhReject = mapLeaveRowToApi(out.rows[0]);
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: r.user_id || r.employee_id,
        leaveRequestId: id,
        type: 'leave_rejected_department_head',
        title: 'Leave request not approved by department head',
        body: remarks
          ? `Your request was not approved. ${remarks}`
          : 'Your leave request was not approved by your department head.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    broadcastLeaveUpdated('department_head_rejected', mappedDhReject);
    res.json(mappedDhReject);
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    console.error('[leave PATCH /:id/department-head-reject]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to reject (department head)' });
  } finally {
    client.release();
  }
});

// PATCH /api/leave/:id/department-head-return
router.patch('/:id/department-head-return', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const existing = await client.query(
      `SELECT lr.id, lr.status, lr.user_id, lr.employee_id,
              COALESCE(lr.number_of_days, lr.total_days) AS days, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN assignments a ON a.employee_id = COALESCE(lr.user_id, lr.employee_id)
                              AND (a.is_active IS NULL OR a.is_active = true)
       WHERE lr.id = $1 AND a.department_id = $2
       FOR UPDATE OF lr`,
      [id, deptInfo.departmentId]
    );
    if (existing.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found or not in your department' });
    }
    const r = existing.rows[0];
    const { nextStatus, historyAction } = validateDepartmentHeadTransition({
      currentStatus: r.status,
      desiredStatus: 'returned',
    });
    await client.query(
      `UPDATE leave_requests
       SET status = $2, reviewer_id = $3, reviewer_remarks = $4, reviewed_at = now(), updated_at = now()
       WHERE id = $1`,
      [id, nextStatus, reviewerId, remarks]
    );
    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: r.status,
      toStatus: nextStatus,
      actedBy: reviewerId,
      remarks,
      metadataJson: null,
    });
    // Decrement pending_days on dept head return
    const returnDays = r.days != null ? parseFloat(r.days) : null;
    const returnUserId = r.user_id || r.employee_id;
    const returnLtName = r.leave_type_name || null;
    if (returnDays && returnDays > 0 && returnUserId && returnLtName) {
      await releasePendingLeaveBalance(client, {
        userId: returnUserId,
        leaveTypeName: returnLtName,
        days: returnDays,
        leaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'user',
        action: 'leave_returned',
        remarks,
        metadataJson: { stage: 'department_head' },
      });
    }
    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedDhReturn = mapLeaveRowToApi(out.rows[0]);
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: r.user_id || r.employee_id,
        leaveRequestId: id,
        type: 'leave_returned_department_head',
        title: 'Leave request returned for correction',
        body: remarks
          ? `Your department head returned this request for correction. ${remarks}`
          : 'Your department head returned this leave request for correction.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    broadcastLeaveUpdated('department_head_returned', mappedDhReturn);
    res.json(mappedDhReturn);
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    console.error('[leave PATCH /:id/department-head-return]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to return (department head)' });
  } finally {
    client.release();
  }
});

// PATCH /api/leave/:id/approve (admin/HR)
router.patch('/:id/approve', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
  const recommendationRemarks = (req.body?.recommendation_remarks || req.body?.recommendationRemarks || '').toString().trim() || null;
  const approvedOtherDetails = (req.body?.approved_other_details || req.body?.approvedOtherDetails || '').toString().trim() || null;
  const approvedDaysWithPayRaw = req.body?.approved_days_with_pay ?? req.body?.approvedDaysWithPay;
  const approvedDaysWithoutPayRaw = req.body?.approved_days_without_pay ?? req.body?.approvedDaysWithoutPay;
  const approvedDaysWithPay = approvedDaysWithPayRaw != null && approvedDaysWithPayRaw !== ''
    ? parseFloat(approvedDaysWithPayRaw)
    : null;
  const approvedDaysWithoutPay = approvedDaysWithoutPayRaw != null && approvedDaysWithoutPayRaw !== ''
    ? parseFloat(approvedDaysWithoutPayRaw)
    : null;
  const reviewDetailsPatch = {};
  if (recommendationRemarks) reviewDetailsPatch.recommendation_remarks = recommendationRemarks;
  if (approvedOtherDetails) reviewDetailsPatch.approved_other_details = approvedOtherDetails;
  if (approvedDaysWithPay != null && !Number.isNaN(approvedDaysWithPay)) {
    reviewDetailsPatch.approved_days_with_pay = approvedDaysWithPay;
  }
  if (approvedDaysWithoutPay != null && !Number.isNaN(approvedDaysWithoutPay)) {
    reviewDetailsPatch.approved_days_without_pay = approvedDaysWithoutPay;
  }
  try {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT lr.id, lr.status, lr.user_id, lr.employee_id, lr.start_date, lr.end_date,
                COALESCE(lr.number_of_days, lr.total_days) AS days,
                lt.name AS leave_type_name
         FROM leave_requests lr
         LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
         WHERE lr.id = $1
         FOR UPDATE OF lr`,
        [id]
      );
      if (existing.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Leave request not found' });
      }
      const r = existing.rows[0];
      // Prevent double deduction: if already approved, return current record and skip updates.
      if (r.status === 'approved') {
        await client.query('COMMIT');
        const out = await pool.query(
          `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
           FROM leave_requests lr
           LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
           LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
           WHERE lr.id = $1`,
          [id]
        );
        return res.json(mapLeaveRowToApi(out.rows[0]));
      }
      const { historyAction } = validateAdminTransition({
        currentStatus: r.status,
        desiredStatus: 'approved',
      });

      const updated = await client.query(
        `UPDATE leave_requests
         SET status = 'approved',
             reviewer_id = $2::uuid,
             reviewer_remarks = $3::text,
             details = COALESCE(details, '{}'::jsonb) || $4::jsonb,
             reviewed_at = now(),
             approved_by = COALESCE(approved_by, $2::uuid),
             approved_at = COALESCE(approved_at, now()),
             updated_at = now()
         WHERE id = $1
         RETURNING *`,
        [id, reviewerId, remarks, JSON.stringify(reviewDetailsPatch)]
      );
      const row = updated.rows[0];
      const targetUserId = row.user_id || row.employee_id;
      const startStr = toIsoDateStr(row.start_date);
      const endStr = toIsoDateStr(row.end_date);
      const days = row.number_of_days != null ? parseFloat(row.number_of_days) : (row.total_days != null ? parseFloat(row.total_days) : null);
      const leaveTypeName = r.leave_type_name || null;

      // Prevent approving if another pending/approved leave overlaps this range.
      const hasOverlap = await hasOverlappingLeaveRequest(client, targetUserId, startStr, endStr, id);
      if (hasOverlap) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Overlapping leave request exists' });
      }

      await assertSpecialPrivilegeLeaveAnnualLimit(client, {
        userId: targetUserId,
        leaveTypeName,
        startStr,
        endStr,
        excludeId: id,
      });

      // Deduct balance ONLY on approval (and only once because we block re-approving approved status).
      // Clear submit-time pending_days and add to used_days (same days, same balanceLedgerLeaveType as submit).
      await upsertLeaveBalanceDeduction(client, targetUserId, leaveTypeName, days, {
        decrementPendingDays: true,
        ledgerContext: {
          action: 'leave_approved',
          leaveRequestId: id,
          actorUserId: reviewerId,
          actorKind: 'admin',
        },
      });

      // DTR integration: mark each date as on_leave and link leave_request_id when the leave type affects DTR.
      const leaveTypeRuleForDtr = leaveTypeName
        ? await getLeaveTypeDefinition(client, leaveTypeName)
        : null;
      if (leaveTypeRuleForDtr?.affects_dtr_normally !== false) {
        await applyApprovedLeaveToDtr(client, targetUserId, id, startStr, endStr);
      }

      await insertLeaveRequestHistory(client, {
        leaveRequestId: id,
        action: historyAction,
        fromStatus: r.status,
        toStatus: 'approved',
        actedBy: reviewerId,
        remarks: remarks || null,
        metadataJson: {
          leave_type: leaveTypeName,
          start_date: startStr,
          end_date: endStr,
          number_of_days: days,
        },
      });

      await client.query('COMMIT');
      notifySafe(() =>
        leaveNotifications.notifyEmployee(pool, {
          employeeUserId: targetUserId,
          leaveRequestId: id,
          type: 'leave_approved',
          title: 'Leave request approved',
          body: remarks
            ? `Your leave request was approved. ${remarks}`
            : 'Your leave request was approved.',
          metadata: {
            reviewer_remarks: remarks,
            leave_type: leaveTypeName,
            start_date: startStr,
            end_date: endStr,
          },
        })
      );
      const mapped = mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName });
      broadcastDtrLeaveRefresh('leave_approved_applied_to_dtr', {
        userId: targetUserId,
        leaveRequestId: id,
        dateFrom: startStr,
        dateTo: endStr,
      });
      broadcastLeaveUpdated('approved', mapped);
      res.json(mapped);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    if (err && err.statusCode) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[leave PATCH /:id/approve]', err);
    const msg = err && err.message ? err.message : 'Failed to approve leave request';
    res.status(500).json({ error: msg });
  }
});

// PATCH /api/leave/:id/reject (admin/HR)
router.patch('/:id/reject', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '').toString().trim() || null;
  const disapprovalReason = (req.body?.disapproval_reason || req.body?.disapprovalReason || req.body?.reason || req.body?.reviewer_remarks || '').toString().trim() || null;
  const rejectDetailsPatch = {};
  if (disapprovalReason) rejectDetailsPatch.disapproval_reason = disapprovalReason;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT lr.status, COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.user_id, lr.employee_id, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found' });
    }
    const currentRow = current.rows[0];

    const { historyAction } = validateAdminTransition({
      currentStatus: currentRow.status,
      desiredStatus: 'rejected',
    });

    const { nextStatus: rejectNextStatus } = validateAdminTransition({
      currentStatus: currentRow.status,
      desiredStatus: 'rejected',
    });

    await client.query(
      `UPDATE leave_requests
       SET status = $4::text,
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           details = COALESCE(details, '{}'::jsonb) || $5::jsonb,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1`,
      [id, reviewerId, remarks, rejectNextStatus, JSON.stringify(rejectDetailsPatch)]
    );

    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: currentRow.status,
      toStatus: rejectNextStatus,
      actedBy: reviewerId,
      remarks: remarks || null,
      metadataJson: null,
    });

    // FIX #5d: Decrement pending_days on reject.
    const rejectDays = currentRow.days != null ? parseFloat(currentRow.days) : null;
    const rejectUserId = currentRow.user_id || currentRow.employee_id;
    const rejectLtName = currentRow.leave_type_name || null;
    if (rejectDays && rejectDays > 0 && rejectUserId && rejectLtName) {
      await releasePendingLeaveBalance(client, {
        userId: rejectUserId,
        leaveTypeName: rejectLtName,
        days: rejectDays,
        leaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'admin',
        action: 'leave_rejected',
        remarks,
        metadataJson: { stage: 'hr' },
      });
    }

    await client.query('COMMIT');
    // FIX #3: Re-fetch with full join so leave_type_name is in the response.
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedReject = mapLeaveRowToApi(out.rows[0]);
    const empRejectId = currentRow.user_id || currentRow.employee_id;
    const disapproval =
      disapprovalReason ||
      remarks ||
      mappedReject.disapproval_reason ||
      null;
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: empRejectId,
        leaveRequestId: id,
        type: 'leave_rejected_hr',
        title: 'Leave request not approved',
        body: disapproval
          ? `HR did not approve this leave request. ${disapproval}`
          : 'HR did not approve this leave request.',
        metadata: { reviewer_remarks: remarks, disapproval_reason: disapprovalReason },
      })
    );
    broadcastLeaveUpdated('rejected', mappedReject);
    res.json(mappedReject);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('[leave PATCH /:id/reject]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to reject leave request' });
  } finally {
    client.release();
  }
});

// ============================================================
// PATCH /api/leave/:id/revoke  (Phase 4 #15 — Admin only)
// Revoke an approved leave: restore used_days balance + clean DTR.
// ============================================================
router.patch('/:id/revoke', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT lr.id, lr.status,
              COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.user_id, lr.employee_id,
              lr.start_date, lr.end_date,
              lr.approved_at, lr.reviewed_at,
              lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1
       FOR UPDATE OF lr`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found' });
    }
    const r = current.rows[0];
    if (r.status !== 'approved') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot revoke a leave request with status '${r.status}'. Only approved requests can be revoked.`,
      });
    }

    const approvalTimestamp = r.approved_at || r.reviewed_at;
    if (!approvalTimestamp) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'Cannot determine the HR approval date for this request. Approval can only be revoked within 3 days.',
      });
    }
    const approvedAt = new Date(approvalTimestamp);
    const revokeDeadline = new Date(approvedAt.getTime() + LEAVE_REVOKE_WINDOW_MS);
    if (Date.now() > revokeDeadline.getTime()) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Revoke period expired. Approved leave can only be revoked within ${LEAVE_REVOKE_WINDOW_DAYS} days after HR approval.`,
      });
    }

    const targetUserId = r.user_id || r.employee_id;
    const revokeDays = r.days != null ? parseFloat(r.days) : null;
    const ltName = r.leave_type_name || null;
    const startStr = toIsoDateStr(r.start_date);
    const endStr = toIsoDateStr(r.end_date);

    // 1. Set status back to 'returned' (employee must re-file or Admin closes it separately).
    await client.query(
      `UPDATE leave_requests
       SET status = 'returned',
           reviewer_id   = $2::uuid,
           reviewer_remarks = $3::text,
           reviewed_at   = now(),
           updated_at    = now()
       WHERE id = $1`,
      [id, reviewerId, remarks || 'Approval revoked by admin.']
    );

    // 2. Restore used_days balance (reverse final approval). Pending was cleared on approve; do not re-add to pending
    //    — request status is 'returned', not a pending workflow; employee may resubmit (submit adds pending again).
    if (revokeDays && revokeDays > 0 && targetUserId && ltName) {
      const ledgerType = await resolveBalanceLedgerLeaveType(client, ltName);
      if (ledgerType) {
        const beforeRev = await fetchBalanceSnapshot(client, targetUserId, ledgerType);
        await client.query(
          `UPDATE leave_balances
           SET used_days = GREATEST(0, COALESCE(used_days, 0) - $3::numeric),
               updated_at = now()
           WHERE user_id = $1::uuid AND leave_type = $2::text`,
          [targetUserId, ledgerType, revokeDays]
        );
        const afterRev = await fetchBalanceSnapshot(client, targetUserId, ledgerType);
        await insertLeaveBalanceLedger(client, {
          userId: targetUserId,
          leaveType: ledgerType,
          action: 'leave_revoked',
          affectedBucket: 'used',
          daysChanged: afterRev.used_days - beforeRev.used_days,
          oldValue: beforeRev.used_days,
          newValue: afterRev.used_days,
          relatedLeaveRequestId: id,
          actorUserId: reviewerId,
          actorKind: 'admin',
          remarks: remarks || null,
          metadataJson: { revoke_days: revokeDays },
        });
      }
    }

    // 3. Remove DTR on_leave entries that were written by this approval.
    //    Only removes rows that are still 'on_leave' and linked to this request.
    //    Rows already changed to 'present' (employee actually showed up) are untouched.
    await client.query(
      `DELETE FROM dtr_daily_summary
       WHERE leave_request_id = $1
         AND status = 'on_leave'`,
      [id]
    );

    // 4. Audit trail.
    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: 'revoked',
      fromStatus: 'approved',
      toStatus: 'returned',
      actedBy: reviewerId,
      remarks: remarks || 'Approval revoked.',
      metadataJson: {
        leave_type: ltName,
        start_date: startStr,
        end_date: endStr,
        number_of_days: revokeDays,
        revoked_by: reviewerId,
      },
    });

    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedRevoke = mapLeaveRowToApi(out.rows[0]);
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: targetUserId,
        leaveRequestId: id,
        type: 'leave_revoked',
        title: 'Approved leave was revoked',
        body:
          remarks ||
          'HR revoked the approval for this leave request. Please review your record and contact HR if needed.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    broadcastDtrLeaveRefresh('leave_revoked_removed_from_dtr', {
      userId: targetUserId,
      leaveRequestId: id,
      dateFrom: startStr,
      dateTo: endStr,
    });
    broadcastLeaveUpdated('revoked', mappedRevoke);
    res.json(mappedRevoke);
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    console.error('[leave PATCH /:id/revoke]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to revoke leave approval' });
  } finally {
    client.release();
  }
});

// PATCH /api/leave/:id/return
router.patch('/:id/return', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT lr.status, COALESCE(lr.number_of_days, lr.total_days) AS days,
              lr.user_id, lr.employee_id, lt.name AS leave_type_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE lr.id = $1`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Leave request not found' });
    }
    const currentRow = current.rows[0];

    // Admin can return from pending_hr or legacy pending
    if (currentRow.status !== 'pending_hr' && currentRow.status !== 'pending') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: `Cannot return request with status '${currentRow.status}'` });
    }
    const historyAction = 'returned';

    await client.query(
      `UPDATE leave_requests
       SET status = 'returned',
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1`,
      [id, reviewerId, remarks]
    );

    await insertLeaveRequestHistory(client, {
      leaveRequestId: id,
      action: historyAction,
      fromStatus: currentRow.status,
      toStatus: 'returned',
      actedBy: reviewerId,
      remarks: remarks || null,
      metadataJson: null,
    });

    // FIX #5e: Decrement pending_days when a request is returned to employee.
    const returnDays = currentRow.days != null ? parseFloat(currentRow.days) : null;
    const returnUserId = currentRow.user_id || currentRow.employee_id;
    const returnLtName = currentRow.leave_type_name || null;
    if (returnDays && returnDays > 0 && returnUserId && returnLtName) {
      await releasePendingLeaveBalance(client, {
        userId: returnUserId,
        leaveTypeName: returnLtName,
        days: returnDays,
        leaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'admin',
        action: 'leave_returned',
        remarks,
        metadataJson: { stage: 'hr' },
      });
    }

    await client.query('COMMIT');
    // FIX #3: Re-fetch with full join so leave_type_name is in the response.
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mappedHrReturn = mapLeaveRowToApi(out.rows[0]);
    const empReturnId = currentRow.user_id || currentRow.employee_id;
    notifySafe(() =>
      leaveNotifications.notifyEmployee(pool, {
        employeeUserId: empReturnId,
        leaveRequestId: id,
        type: 'leave_returned_hr',
        title: 'Leave request returned for correction',
        body: remarks
          ? `HR returned this request for correction. ${remarks}`
          : 'HR returned this leave request for correction.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    broadcastLeaveUpdated('returned', mappedHrReturn);
    res.json(mappedHrReturn);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('[leave PATCH /:id/return]', err);
    if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    res.status(500).json({ error: 'Failed to return leave request' });
  } finally {
    client.release();
  }
});

// ============================
// BALANCES & LEDGER
// ============================

// GET /api/leave/ledger — balance movement audit (self: own rows; admin/HR: filterable)
router.get('/ledger', protect, async (req, res) => {
  const requesterId = req.user?.id;
  const role = req.user?.role;
  if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
  const isPrivileged = role === 'admin' || role === 'hr';

  const limitRaw = req.query?.limit ? parseInt(String(req.query.limit), 10) : 50;
  const offsetRaw = req.query?.offset ? parseInt(String(req.query.offset), 10) : 0;
  const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 200) : 50;
  const offset = Number.isFinite(offsetRaw) && offsetRaw >= 0 ? offsetRaw : 0;

  const filterUserId = (req.query?.user_id || '').toString().trim() || null;
  const leaveType = (req.query?.leave_type || '').toString().trim() || null;
  const action = (req.query?.action || '').toString().trim() || null;
  const from = (req.query?.from || req.query?.created_from || '').toString().trim() || null;
  const to = (req.query?.to || req.query?.created_to || '').toString().trim() || null;

  if (!isPrivileged && filterUserId && filterUserId !== requesterId) {
    return res.status(403).json({ error: 'Not allowed to view ledger for other users' });
  }

  const scopeSelfOnly = !isPrivileged;
  const scopeAdminAllUsers = isPrivileged && !filterUserId;

  const params = [];
  let p = 1;
  const where = [];
  if (scopeSelfOnly) {
    where.push(`l.user_id = $${p}::uuid`);
    params.push(requesterId);
    p += 1;
  } else if (!scopeAdminAllUsers) {
    where.push(`l.user_id = $${p}::uuid`);
    params.push(filterUserId);
    p += 1;
  }
  if (leaveType) {
    where.push(`l.leave_type = $${p}`);
    params.push(leaveType);
    p += 1;
  }
  if (action) {
    where.push(`l.action = $${p}`);
    params.push(action);
    p += 1;
  }
  if (from && /^\d{4}-\d{2}-\d{2}$/.test(from)) {
    where.push(`l.created_at >= $${p}::date`);
    params.push(from);
    p += 1;
  }
  if (to && /^\d{4}-\d{2}-\d{2}$/.test(to)) {
    where.push(`l.created_at < ($${p}::date + interval '1 day')`);
    params.push(to);
    p += 1;
  }

  const whereSql = where.length > 0 ? where.join(' AND ') : 'true';

  try {
    const countQ = await pool.query(
      `SELECT count(*)::int AS c FROM leave_balance_ledger l WHERE ${whereSql}`,
      params
    );
    const total = countQ.rows[0]?.c ?? 0;

    const listParams = [...params, limit, offset];
    const limIdx = p;
    const offIdx = p + 1;
    const list = await pool.query(
      `SELECT l.*, u.full_name AS employee_name,
              actor.full_name AS actor_name
       FROM leave_balance_ledger l
       LEFT JOIN users u ON u.id = l.user_id
       LEFT JOIN users actor ON actor.id = l.actor_user_id
       WHERE ${whereSql}
       ORDER BY l.created_at DESC
       LIMIT $${limIdx} OFFSET $${offIdx}`,
      listParams
    );

    res.json({
      total,
      limit,
      offset,
      rows: list.rows.map((r) => ({
        id: r.id,
        user_id: r.user_id,
        employee_name: r.employee_name || null,
        leave_type: r.leave_type,
        action: r.action,
        affected_bucket: r.affected_bucket,
        days_changed: r.days_changed != null ? parseFloat(r.days_changed) : 0,
        old_value: r.old_value != null ? parseFloat(r.old_value) : null,
        new_value: r.new_value != null ? parseFloat(r.new_value) : null,
        related_leave_request_id: r.related_leave_request_id,
        actor_user_id: r.actor_user_id,
        actor_name: r.actor_name || null,
        actor_kind: r.actor_kind,
        remarks: r.remarks,
        metadata_json: r.metadata_json,
        created_at: r.created_at,
      })),
    });
  } catch (err) {
    console.error('[leave GET /ledger]', err);
    if (err.code === '42P01') {
      return res.status(503).json({ error: 'Leave ledger table not ready yet' });
    }
    res.status(500).json({ error: 'Failed to fetch leave ledger' });
  }
});

// GET /api/leave/balances/:userId (self or admin)
router.get('/balances/:userId', protect, async (req, res) => {
  const requesterId = req.user?.id;
  const role = req.user?.role;
  if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
  const targetId = req.params.userId;
  const isPrivileged = role === 'admin' || role === 'hr';
  if (!isPrivileged && requesterId !== targetId) {
    return res.status(403).json({ error: 'Not allowed to view balances for this user' });
  }
  try {
    const rows = await pool.query(
      `SELECT lb.*, u.full_name AS employee_name,
              COALESCE(lt.display_name, lt.description, lb.leave_type) AS leave_type_display_name
       FROM leave_balances lb
       LEFT JOIN users u ON u.id = lb.user_id
       LEFT JOIN leave_types lt ON lt.name = lb.leave_type
       WHERE lb.user_id = $1::uuid
         AND (
           lb.leave_type IN ('vacationLeave', 'sickLeave')
           OR lt.balance_ledger_type = 'ownBalance'
         )
       ORDER BY lb.leave_type ASC`,
      [targetId]
    );
    // Align response with Flutter LeaveBalance.fromJson keys.
    res.json(rows.rows.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      leave_type: r.leave_type,
      leave_type_display_name: r.leave_type_display_name || r.leave_type,
      employee_name: r.employee_name || null,
      earned_days: r.earned_days != null ? parseFloat(r.earned_days) : 0,
      used_days: r.used_days != null ? parseFloat(r.used_days) : 0,
      pending_days: r.pending_days != null ? parseFloat(r.pending_days) : 0,
      adjusted_days: r.adjusted_days != null ? parseFloat(r.adjusted_days) : 0,
      as_of_date: r.as_of_date ? String(r.as_of_date).slice(0, 10) : null,
      last_accrual_date: r.last_accrual_date ? String(r.last_accrual_date).slice(0, 10) : null,
      created_at: r.created_at,
      updated_at: r.updated_at,
    })));
  } catch (err) {
    console.error('[leave GET /balances/:userId]', err);
    res.status(500).json({ error: 'Failed to fetch leave balances' });
  }
});

// PUT /api/leave/balances/:userId — admin/HR: create or replace one leave_balances row
router.put('/balances/:userId', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  const targetId = req.params.userId;
  const b = req.body || {};
  const leaveType = (b.leave_type ?? b.leaveType ?? '').toString().trim();
  if (!leaveType) {
    return res.status(400).json({ error: 'Invalid or missing leave_type' });
  }
  const earned = parseFloat(b.earned_days ?? b.earnedDays);
  const used = parseFloat(b.used_days ?? b.usedDays);
  const pending = parseFloat(b.pending_days ?? b.pendingDays);
  const adjusted = parseFloat(b.adjusted_days ?? b.adjustedDays ?? 0);
  if (!Number.isFinite(earned) || earned < 0) {
    return res.status(400).json({ error: 'earned_days must be a number >= 0' });
  }
  if (!Number.isFinite(used) || used < 0) {
    return res.status(400).json({ error: 'used_days must be a number >= 0' });
  }
  if (!Number.isFinite(pending) || pending < 0) {
    return res.status(400).json({ error: 'pending_days must be a number >= 0' });
  }
  if (!Number.isFinite(adjusted)) {
    return res.status(400).json({ error: 'adjusted_days must be a number' });
  }
  let asOf = b.as_of_date ?? b.asOfDate;
  let lastAccrual = b.last_accrual_date ?? b.lastAccrualDate;
  if (asOf === '' || asOf === undefined) asOf = null;
  if (lastAccrual === '' || lastAccrual === undefined) lastAccrual = null;

  // Enhancement 9 — last_accrual_date edit guard:
  // Prevent setting last_accrual_date to a future date; this would silently skip
  // upcoming automated accrual runs for the employee.
  if (lastAccrual != null) {
    const parsedLastAccrual = new Date(lastAccrual);
    if (!Number.isNaN(parsedLastAccrual.getTime())) {
      const todayUtc = new Date();
      todayUtc.setHours(0, 0, 0, 0);
      if (parsedLastAccrual > todayUtc) {
        return res.status(400).json({
          error:
            'last_accrual_date cannot be set to a future date. ' +
            'Setting it in the future would cause the automated accrual cron to skip upcoming months for this employee.',
        });
      }
    }
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const balanceBucket = await resolveBalanceLedgerLeaveType(client, leaveType);
    if (!balanceBucket) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'This leave type does not use leave credits and cannot have a leave balance row.',
      });
    }
    if (balanceBucket !== leaveType) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `${systemLeaveTypeDisplayName(leaveType)} uses the ${creditBalanceLabel(balanceBucket, leaveType)} balance bucket. Update that bucket instead.`,
      });
    }
    const prev = await client.query(
      `SELECT earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date
       FROM leave_balances
       WHERE user_id = $1::uuid AND leave_type = $2::text
       FOR UPDATE`,
      [targetId, leaveType]
    );
    const beforeSnap = balanceRowToSnapshot(prev.rows[0]);

    const out = await client.query(
      `INSERT INTO leave_balances (
         user_id, leave_type, earned_days, used_days, pending_days, adjusted_days,
         as_of_date, last_accrual_date, created_at, updated_at
       )
       VALUES (
         $1::uuid, $2, $3, $4, $5, $6,
         $7::date, $8::date, now(), now()
       )
       ON CONFLICT (user_id, leave_type)
       DO UPDATE SET
         earned_days = EXCLUDED.earned_days,
         used_days = EXCLUDED.used_days,
         pending_days = EXCLUDED.pending_days,
         adjusted_days = EXCLUDED.adjusted_days,
         as_of_date = EXCLUDED.as_of_date,
         last_accrual_date = EXCLUDED.last_accrual_date,
         updated_at = now()
       RETURNING *`,
      [targetId, leaveType, earned, used, pending, adjusted, asOf, lastAccrual],
    );
    if (out.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(500).json({ error: 'Failed to save leave balance' });
    }
    const r = out.rows[0];
    const afterSnap = balanceRowToSnapshot(r);

    await insertLeaveBalanceLedger(client, {
      userId: targetId,
      leaveType,
      action: 'admin_adjustment',
      affectedBucket: 'multiple',
      daysChanged: 0,
      oldValue: null,
      newValue: null,
      relatedLeaveRequestId: null,
      actorUserId: reviewerId || null,
      actorKind: 'admin',
      remarks: (b.remarks || b.ledger_remarks || '').toString().trim() || null,
      metadataJson: {
        before: beforeSnap,
        after: afterSnap,
        as_of_date: asOf,
        last_accrual_date: lastAccrual,
      },
    });

    await client.query('COMMIT');

    const nameRow = await pool.query('SELECT full_name FROM users WHERE id = $1::uuid', [targetId]);
    const employeeName = nameRow.rows[0]?.full_name || null;
    const response = {
      id: r.id,
      user_id: r.user_id,
      leave_type: r.leave_type,
      employee_name: employeeName,
      earned_days: r.earned_days != null ? parseFloat(r.earned_days) : 0,
      used_days: r.used_days != null ? parseFloat(r.used_days) : 0,
      pending_days: r.pending_days != null ? parseFloat(r.pending_days) : 0,
      adjusted_days: r.adjusted_days != null ? parseFloat(r.adjusted_days) : 0,
      as_of_date: r.as_of_date ? String(r.as_of_date).slice(0, 10) : null,
      last_accrual_date: r.last_accrual_date ? String(r.last_accrual_date).slice(0, 10) : null,
      created_at: r.created_at,
      updated_at: r.updated_at,
    };
    broadcastLeaveUpdated('balance_updated', { user_id: targetId }, response);
    res.json(response);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('[leave PUT /balances/:userId]', err);
    if (err && err.code === '23503') {
      return res.status(400).json({ error: 'Invalid user or leave type reference' });
    }
    res.status(500).json({ error: err.message || 'Failed to save leave balance' });
  } finally {
    client.release();
  }
});

// POST /api/leave/:id/attachment - upload attachment (owner or admin; draft/pending/returned only)
router.post('/:id/attachment', protect, uploadLeaveAttachmentMw, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded. Allowed: PDF, JPG, JPEG, PNG (max 10MB).' });
    }
    const isAdmin = role === 'admin' || role === 'hr';
    const existing = await pool.query(
      'SELECT id, status, attachment_path FROM leave_requests WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)',
      [id, isAdmin, userId]
    );
    if (existing.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const row = existing.rows[0];
    if (!canModifyAttachment(row.status)) {
      return res.status(400).json({ error: 'Attachment cannot be changed for this request status.' });
    }
    const relPath = `${LEAVE_ATTACHMENT_SUBDIR}/${req.file.filename}`;
    const mimeType = req.file.mimetype || null;
    if (row.attachment_path) {
      const oldPath = path.join(UPLOAD_DIR, row.attachment_path);
      if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
    }
    await pool.query(
      `UPDATE leave_requests
       SET attachment_name = $1, attachment_path = $2, attachment_mime_type = $3, attachment_uploaded_at = now(), updated_at = now()
       WHERE id = $4`,
      [req.file.originalname || req.file.filename, relPath, mimeType, id]
    );
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mapped = mapLeaveRowToApi(out.rows[0]);
    broadcastLeaveUpdated('attachment_uploaded', mapped);
    res.json(mapped);
  } catch (err) {
    console.error('[leave POST /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to upload attachment' });
  }
});

// DELETE /api/leave/:id/attachment - remove attachment
router.delete('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const isAdmin = role === 'admin' || role === 'hr';
    const existing = await pool.query(
      'SELECT id, status, attachment_path FROM leave_requests WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)',
      [id, isAdmin, userId]
    );
    if (existing.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const row = existing.rows[0];
    if (!canModifyAttachment(row.status)) {
      return res.status(400).json({ error: 'Attachment cannot be changed for this request status.' });
    }
    if (row.attachment_path) {
      const filePath = path.join(UPLOAD_DIR, row.attachment_path);
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    }
    await pool.query(
      `UPDATE leave_requests
       SET attachment_name = NULL, attachment_path = NULL, attachment_mime_type = NULL, attachment_uploaded_at = NULL, updated_at = now()
       WHERE id = $1`,
      [id]
    );
    const out = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.id = $1`,
      [id]
    );
    const mapped = mapLeaveRowToApi(out.rows[0]);
    broadcastLeaveUpdated('attachment_removed', mapped);
    res.json(mapped);
  } catch (err) {
    console.error('[leave DELETE /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to remove attachment' });
  }
});

// GET /api/leave/:id/attachment - download attachment (owner, admin/HR, or reviewing department head)
router.get('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const isAdmin = role === 'admin' || role === 'hr';
    const rows = await pool.query(
      'SELECT user_id, employee_id, attachment_path, attachment_name, attachment_mime_type FROM leave_requests WHERE id = $1',
      [id]
    );
    if (rows.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const row = rows.rows[0];
    const targetUserId = row.user_id || row.employee_id;
    let canAccess = isAdmin || targetUserId === userId;
    if (!canAccess) {
      const deptInfo = await isDepartmentHead(pool, userId);
      if (deptInfo?.isDeptHead && deptInfo.departmentId && targetUserId) {
        const employeeDept = await getEmployeeDepartment(pool, targetUserId);
        canAccess = employeeDept?.departmentId === deptInfo.departmentId;
      }
    }
    if (!canAccess) return res.status(404).json({ error: 'Leave request not found' });
    if (!row.attachment_path) return res.status(404).json({ error: 'No attachment for this request' });
    const filePath = path.join(UPLOAD_DIR, row.attachment_path);
    if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'Attachment file not found' });
    const filename = row.attachment_name || 'attachment';
    res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
    if (row.attachment_mime_type) res.setHeader('Content-Type', row.attachment_mime_type);
    res.sendFile(path.resolve(filePath));
  } catch (err) {
    console.error('[leave GET /:id/attachment]', err);
    res.status(500).json({ error: 'Failed to fetch attachment' });
  }
});

// GET /api/leave/:id
// IMPORTANT: keep this AFTER fixed-path endpoints like /pending
router.get('/:id', protect, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const isAdmin = role === 'admin' || role === 'hr';
    const deptInfo = isAdmin
      ? { isDeptHead: false, departmentId: null }
      : await isDepartmentHead(pool, userId);
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name,
              rv.full_name AS reviewer_name,
              rv.role AS reviewer_role,
              dhh.department_head_action,
              dhh.department_head_reviewer_id,
              dhh.department_head_reviewer_name,
              dhh.department_head_reviewed_at,
              dhh.department_head_remarks
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       LEFT JOIN users rv ON rv.id = COALESCE(lr.reviewer_id, lr.approved_by)
       LEFT JOIN LATERAL (
         SELECT h.action AS department_head_action,
                h.acted_by AS department_head_reviewer_id,
                actor.full_name AS department_head_reviewer_name,
                h.acted_at AS department_head_reviewed_at,
                h.remarks AS department_head_remarks
         FROM leave_request_history h
         LEFT JOIN users actor ON actor.id = h.acted_by
         WHERE h.leave_request_id = lr.id
           AND ($2::boolean = true OR h.acted_by = $3::uuid)
           AND h.action IN (
             'department_head_approved',
             'department_head_rejected',
             'department_head_returned'
           )
         ORDER BY h.acted_at DESC
         LIMIT 1
       ) dhh ON true
       WHERE lr.id = $1
         AND (
           $2::boolean = true
           OR (lr.user_id = $3 OR lr.employee_id = $3)
           OR (
             $4::uuid IS NOT NULL
             AND a.department_id = $4
             AND (
               lr.status = 'pending_department_head'
               OR dhh.department_head_reviewer_id IS NOT NULL
             )
           )
         )
       LIMIT 1`,
      [id, isAdmin, userId, deptInfo.departmentId]
    );
    if (rows.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    res.json(mapLeaveRowToApi(rows.rows[0]));
  } catch (err) {
    console.error('[leave GET /:id]', err);
    res.status(500).json({ error: 'Failed to fetch leave request' });
  }
});

// ============================================================
// Year-end Forced Leave Compliance + Bulk Deduction
// ============================================================

// GET /api/leave/admin/year-end-forced-leave?year=YYYY
// Returns per-employee forced leave compliance data for the given year.
router.get('/admin/year-end-forced-leave', protect, requireAdminOrHr, async (req, res) => {
  try {
    const yearRaw = req.query.year;
    const year = yearRaw ? parseInt(String(yearRaw).trim(), 10) : yearEndManilaYearNow();
    const maxYear = new Date().getFullYear() + 1;
    if (!Number.isInteger(year) || year < 1900 || year > maxYear) {
      return res.status(400).json({ error: `year must be between 1900 and ${maxYear}` });
    }
    const result = await getYearEndForcedLeaveCompliance(pool, { year });
    res.json(result);
  } catch (err) {
    console.error('[leave GET /admin/year-end-forced-leave]', err);
    res.status(500).json({ error: 'Failed to fetch year-end forced leave compliance' });
  }
});

// POST /api/leave/admin/year-end-forced-leave/apply
// Body: { year, dry_run?, employee_ids?, remarks? }
// If dry_run=true: returns preview without writing. Otherwise applies deductions.
router.post('/admin/year-end-forced-leave/apply', protect, requireAdminOrHr, async (req, res) => {
  try {
    const actorUserId = req.user?.id;
    const yearRaw = req.body?.year ?? req.query?.year;
    const year = yearRaw ? parseInt(String(yearRaw).trim(), 10) : yearEndManilaYearNow();
    const maxYear = new Date().getFullYear() + 1;
    if (!Number.isInteger(year) || year < 1900 || year > maxYear) {
      return res.status(400).json({ error: `year must be between 1900 and ${maxYear}` });
    }

    const dryRun =
      req.body?.dry_run === true ||
      req.body?.dryRun === true ||
      req.query?.dry_run === '1' ||
      req.query?.dry_run === 'true';

    const rawIds = req.body?.employee_ids ?? req.body?.employeeIds;
    const employeeIds = Array.isArray(rawIds) && rawIds.length > 0
      ? rawIds.map((id) => String(id).trim()).filter(Boolean)
      : null;

    const remarks = (req.body?.remarks || '').toString().trim() || null;

    const result = await applyYearEndForcedLeaveDeductions(pool, {
      year,
      actorUserId,
      dryRun,
      employeeIds,
      remarks,
    });

    if (!dryRun && result.summary?.applied > 0) {
      broadcastAppEvent('leave_updated', {
        action: 'forced_leave_deduction',
        source: 'year_end_bulk',
        year,
        applied: result.summary.applied,
      });
    }

    res.status(dryRun ? 200 : 201).json(result);
  } catch (err) {
    console.error('[leave POST /admin/year-end-forced-leave/apply]', err);
    res.status(500).json({ error: 'Failed to apply year-end forced leave deductions' });
  }
});

module.exports = router;

