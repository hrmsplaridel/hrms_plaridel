const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin, requireAdminOrHr } = require('../middleware/rbac');
const { validateEmployeeLeaveRequest } = require('./leaveTypeRules');
const {
  validateEmployeeUpdateTransition,
  validateEmployeeCancelTransition,
  validateDepartmentHeadTransition,
  validateAdminTransition,
} = require('../services/leaveWorkflowRules');
const {
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

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const LEAVE_ATTACHMENT_SUBDIR = 'leave-attachments';

initLeaveRequestHistory(pool);
initLeaveBalanceLedger(pool);
pool
  .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
  .then(() =>
    pool.query(`
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
      CREATE INDEX IF NOT EXISTS idx_leave_balance_deduction_history_user_applied
        ON leave_balance_deduction_history(user_id, applied_at DESC);
    `)
  )
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

  // Fetch active public holidays in the range from the DB (if client provided).
  const holidayDates = new Set();
  if (dbClient) {
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
      // Silently fall back to plain Mon–Fri count if holiday query fails.
    }
  }

  let count = 0;
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    if (!isWeekday(d)) continue;
    const ds = toIsoDateStr(d); // use the same shift-proof helper
    if (!holidayDates.has(ds)) count += 1;
  }
  return count;
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

async function ensureLeaveTypeIdByName(client, name) {
  const trimmed = (name || '').toString().trim();
  if (!trimmed) return null;
  // IMPORTANT: leave_types are predefined; do NOT auto-insert.
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
 * Maps a leave_requests.leave type name to the leave_balances row key.
 */
function balanceLedgerLeaveType(leaveTypeName) {
  if (!leaveTypeName) return leaveTypeName;
  return leaveTypeName === 'mandatoryForcedLeave' ? 'vacationLeave' : leaveTypeName;
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
  const ledgerType = balanceLedgerLeaveType(leaveTypeName);
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
    const err = new Error(
      `Insufficient leave balance for ${leaveTypeName}. Available ${available.toFixed(2)} (remaining ${remaining.toFixed(2)}, pending ${pending.toFixed(2)}), requested ${d.toFixed(2)}.`
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

  const ledgerType = balanceLedgerLeaveType(leaveTypeName);

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
      const err = new Error(
        `Insufficient leave balance for ${leaveTypeName}. Remaining ${remaining.toFixed(2)}, requested ${days.toFixed(2)}.`
      );
      err.statusCode = 400;
      throw err;
    }
  } else {
    // Forced deduction (and any use not tied to a pending reservation): cannot take more than available.
    if (!allowNegative && days > available) {
      const prefix =
        leaveTypeName === 'mandatoryForcedLeave'
          ? 'Insufficient vacation leave balance (mandatory/forced leave uses vacation credits)'
          : `Insufficient leave balance for ${leaveTypeName}`;
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
      // #12: Recompute with holiday awareness now that we have a DB client.
      const daysHolidayAware = await computeNumberOfDays(startStr, endStr, client);
      const effectiveDaysDraft = daysHolidayAware ?? days;
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (!leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      const validation = validateEmployeeLeaveRequest({
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: effectiveDaysDraft,
        hasAttachment: false,
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
      // #12: Holiday-aware recompute inside transaction.
      const daysHolidayAwareSubmit = await computeNumberOfDays(startStr, endStr, client);
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (!leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();

      // Validate the server-computed, holiday-aware working day count.
      const effectiveDaysSubmit = daysHolidayAwareSubmit ?? days;
      if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
      }

      const validation = validateEmployeeLeaveRequest({
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: effectiveDaysSubmit,
        hasAttachment: false,
      });
      if (!validation.valid) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: validation.error });
      }

      // FIX #6 (backend): POST /submit creates a new record — no attachment yet.
      // Block when a required attachment is missing (incl. sick leave ≥5 working days → medical certificate).
      const { mustBlockMissingAttachment, getRule: getLeaveRule } = require('./leaveTypeRules');
      const submitRule = getLeaveRule(leave_type);
      if (mustBlockMissingAttachment(submitRule, leave_type, effectiveDaysSubmit, false)) {
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
          await assertEnoughAvailableForPendingReservation(
            client,
            userId,
            leaveTypeName,
            pendingDeltaSubmit
          );
          const ledgerType = balanceLedgerLeaveType(leaveTypeName);
          const beforeSnapSubmit = await fetchBalanceSnapshot(client, userId, ledgerType);
          await client.query(
            `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
             VALUES ($1::uuid, $2::text, 0, 0, $3::numeric, 0, now()::date, now()::date, now(), now())
             ON CONFLICT (user_id, leave_type)
             DO UPDATE SET pending_days = COALESCE(leave_balances.pending_days, 0) + EXCLUDED.pending_days,
                           updated_at = now()`,
            [userId, ledgerType, pendingDeltaSubmit]
          );
          const afterSnapSubmit = await fetchBalanceSnapshot(client, userId, ledgerType);
          await insertLeaveBalanceLedger(client, {
            userId,
            leaveType: ledgerType,
            action: 'leave_submitted',
            affectedBucket: 'pending',
            daysChanged: afterSnapSubmit.pending_days - beforeSnapSubmit.pending_days,
            oldValue: beforeSnapSubmit.pending_days,
            newValue: afterSnapSubmit.pending_days,
            relatedLeaveRequestId: row.id,
            actorUserId: userId,
            actorKind: 'user',
            remarks: null,
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
    const days = await computeNumberOfDays(startStr, endStr);
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
      if (startStr && endStr) {
        const computedDays = await computeNumberOfDays(startStr, endStr, client);
        effectiveDays = computedDays ?? days;

        // Validate the server-computed, holiday-aware working day count.
        if (effectiveDays == null || effectiveDays <= 0) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
        }
      }

      if (leave_type && startStr && endStr) {

        const validation = validateEmployeeLeaveRequest({
          leaveType: leave_type,
          otherPurpose: otherPurpose || null,
          startDateStr: startStr,
          endDateStr: endStr,
          numberOfDays: effectiveDays,
          hasAttachment: false,
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
          const { getRule, mustBlockMissingAttachment } = require('./leaveTypeRules');
          const rule = getRule(leave_type);
          if (mustBlockMissingAttachment(rule, leave_type, effectiveDays, hasAttachment)) {
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
          await assertEnoughAvailableForPendingReservation(client, userId, leaveTypeName, effectiveDays);
          const ledgerType = balanceLedgerLeaveType(leaveTypeName);
          const beforePut = await fetchBalanceSnapshot(client, userId, ledgerType);
          await client.query(
            `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
             VALUES ($1::uuid, $2::text, 0, 0, $3::numeric, 0, now()::date, now()::date, now(), now())
             ON CONFLICT (user_id, leave_type)
             DO UPDATE SET pending_days = COALESCE(leave_balances.pending_days, 0) + EXCLUDED.pending_days,
                           updated_at = now()`,
            [userId, ledgerType, effectiveDays]
          );
          const afterPut = await fetchBalanceSnapshot(client, userId, ledgerType);
          const putAction =
            historyAction === 'resubmitted' ? 'leave_resubmitted' : 'leave_submitted';
          await insertLeaveBalanceLedger(client, {
            userId,
            leaveType: ledgerType,
            action: putAction,
            affectedBucket: 'pending',
            daysChanged: afterPut.pending_days - beforePut.pending_days,
            oldValue: beforePut.pending_days,
            newValue: afterPut.pending_days,
            relatedLeaveRequestId: row.id,
            actorUserId: userId,
            actorKind: 'user',
            remarks: null,
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
          const ledgerType = balanceLedgerLeaveType(ltName);
          const beforeCancel = await fetchBalanceSnapshot(client, cancelUserId, ledgerType);
          await client.query(
            `UPDATE leave_balances
             SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
                 updated_at = now()
             WHERE user_id = $1::uuid AND leave_type = $2::text`,
            [cancelUserId, ledgerType, cancelDays]
          );
          const afterCancel = await fetchBalanceSnapshot(client, cancelUserId, ledgerType);
          await insertLeaveBalanceLedger(client, {
            userId: cancelUserId,
            leaveType: ledgerType,
            action: 'leave_cancelled',
            affectedBucket: 'pending',
            daysChanged: afterCancel.pending_days - beforeCancel.pending_days,
            oldValue: beforeCancel.pending_days,
            newValue: afterCancel.pending_days,
            relatedLeaveRequestId: id,
            actorUserId: userId,
            actorKind: 'user',
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
router.get('/department-head', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const deptInfo = await isDepartmentHead(client, userId);
    if (!deptInfo.isDeptHead) {
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const rows = await client.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
       LEFT JOIN assignments a ON a.employee_id = COALESCE(lr.user_id, lr.employee_id)
                              AND (a.is_active IS NULL OR a.is_active = true)
       WHERE lr.status = 'pending_department_head'
         AND a.department_id = $1
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT 200`,
      [deptInfo.departmentId]
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
      `SELECT lr.id, lr.status, lr.user_id, lr.employee_id
       FROM leave_requests lr
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
      const ledgerType = balanceLedgerLeaveType(rejectLtName);
      const beforeDhRej = await fetchBalanceSnapshot(client, rejectUserId, ledgerType);
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric), updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [rejectUserId, ledgerType, rejectDays]
      );
      const afterDhRej = await fetchBalanceSnapshot(client, rejectUserId, ledgerType);
      await insertLeaveBalanceLedger(client, {
        userId: rejectUserId,
        leaveType: ledgerType,
        action: 'leave_rejected',
        affectedBucket: 'pending',
        daysChanged: afterDhRej.pending_days - beforeDhRej.pending_days,
        oldValue: beforeDhRej.pending_days,
        newValue: afterDhRej.pending_days,
        relatedLeaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'user',
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
      const ledgerType = balanceLedgerLeaveType(returnLtName);
      const beforeDhRet = await fetchBalanceSnapshot(client, returnUserId, ledgerType);
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric), updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [returnUserId, ledgerType, returnDays]
      );
      const afterDhRet = await fetchBalanceSnapshot(client, returnUserId, ledgerType);
      await insertLeaveBalanceLedger(client, {
        userId: returnUserId,
        leaveType: ledgerType,
        action: 'leave_returned',
        affectedBucket: 'pending',
        daysChanged: afterDhRet.pending_days - beforeDhRet.pending_days,
        oldValue: beforeDhRet.pending_days,
        newValue: afterDhRet.pending_days,
        relatedLeaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'user',
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

      // DTR integration: mark each date as on_leave and link leave_request_id.
      await applyApprovedLeaveToDtr(client, targetUserId, id, startStr, endStr);

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
      const ledgerType = balanceLedgerLeaveType(rejectLtName);
      const beforeHrRej = await fetchBalanceSnapshot(client, rejectUserId, ledgerType);
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
             updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [rejectUserId, ledgerType, rejectDays]
      );
      const afterHrRej = await fetchBalanceSnapshot(client, rejectUserId, ledgerType);
      await insertLeaveBalanceLedger(client, {
        userId: rejectUserId,
        leaveType: ledgerType,
        action: 'leave_rejected',
        affectedBucket: 'pending',
        daysChanged: afterHrRej.pending_days - beforeHrRej.pending_days,
        oldValue: beforeHrRej.pending_days,
        newValue: afterHrRej.pending_days,
        relatedLeaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'admin',
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
      const ledgerType = balanceLedgerLeaveType(ltName);
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
      const ledgerType = balanceLedgerLeaveType(returnLtName);
      const beforeHrRet = await fetchBalanceSnapshot(client, returnUserId, ledgerType);
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
             updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [returnUserId, ledgerType, returnDays]
      );
      const afterHrRet = await fetchBalanceSnapshot(client, returnUserId, ledgerType);
      await insertLeaveBalanceLedger(client, {
        userId: returnUserId,
        leaveType: ledgerType,
        action: 'leave_returned',
        affectedBucket: 'pending',
        daysChanged: afterHrRet.pending_days - beforeHrRet.pending_days,
        oldValue: beforeHrRet.pending_days,
        newValue: afterHrRet.pending_days,
        relatedLeaveRequestId: id,
        actorUserId: reviewerId,
        actorKind: 'admin',
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
      `SELECT lb.*, u.full_name AS employee_name
       FROM leave_balances lb
       LEFT JOIN users u ON u.id = lb.user_id
       WHERE lb.user_id = $1::uuid
       ORDER BY lb.leave_type ASC`,
      [targetId]
    );
    // Align response with Flutter LeaveBalance.fromJson keys.
    res.json(rows.rows.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      leave_type: r.leave_type,
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

const ALLOWED_BALANCE_LEAVE_TYPES = new Set([
  'vacationLeave',
  'mandatoryForcedLeave',
  'sickLeave',
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

// PUT /api/leave/balances/:userId — admin/HR: create or replace one leave_balances row
router.put('/balances/:userId', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  const targetId = req.params.userId;
  const b = req.body || {};
  const leaveType = (b.leave_type ?? b.leaveType ?? '').toString().trim();
  if (!leaveType || !ALLOWED_BALANCE_LEAVE_TYPES.has(leaveType)) {
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

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
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

// GET /api/leave/:id/attachment - download attachment (owner or admin)
router.get('/:id/attachment', protect, async (req, res) => {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  try {
    const isAdmin = role === 'admin' || role === 'hr';
    const rows = await pool.query(
      'SELECT attachment_path, attachment_name, attachment_mime_type FROM leave_requests WHERE id = $1 AND ($2 = true OR user_id = $3 OR employee_id = $3)',
      [id, isAdmin, userId]
    );
    if (rows.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const row = rows.rows[0];
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
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name,
              d.name AS assignment_department_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       ${SQL_LEAVE_ASSIGNMENT_DEPT_JOIN}
       WHERE lr.id = $1
         AND ($2::boolean = true OR (lr.user_id = $3 OR lr.employee_id = $3))
       LIMIT 1`,
      [id, isAdmin, userId]
    );
    if (rows.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    res.json(mapLeaveRowToApi(rows.rows[0]));
  } catch (err) {
    console.error('[leave GET /:id]', err);
    res.status(500).json({ error: 'Failed to fetch leave request' });
  }
});

module.exports = router;

