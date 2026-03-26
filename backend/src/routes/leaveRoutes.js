const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { validateEmployeeLeaveRequest } = require('./leaveTypeRules');
const {
  validateEmployeeUpdateTransition,
  validateEmployeeCancelTransition,
  validateAdminTransition,
} = require('../services/leaveWorkflowRules');
const {
  initLeaveRequestHistory,
  insertLeaveRequestHistory,
} = require('../services/leaveRequestHistory');

const router = express.Router();
const protect = [authMiddleware];

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const LEAVE_ATTACHMENT_SUBDIR = 'leave-attachments';

initLeaveRequestHistory(pool);

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
      const hq = await dbClient.query(
        `SELECT holiday_date::text AS hd
         FROM holidays
         WHERE is_active = true
           AND holiday_date BETWEEN $1::date AND $2::date
           AND holiday_type IN ('regular', 'special', 'local')`,
        [startStr, endStr]
      );
      for (const row of hq.rows) {
        holidayDates.add(row.hd.slice(0, 10));
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
       AND status IN ('pending', 'approved')
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
    reviewed_at: row.reviewed_at || row.approved_at || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
    leave_type: row.leave_type_name || row.leave_type || null,
    attachment_name: row.attachment_name || null,
    attachment_path: row.attachment_path || null,
    attachment_mime_type: row.attachment_mime_type || null,
    attachment_uploaded_at: row.attachment_uploaded_at || null,
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

/** Check if attachment can be modified (draft, pending, returned). */
function canModifyAttachment(status) {
  return status === 'draft' || status === 'pending' || status === 'returned';
}

async function upsertLeaveBalanceDeduction(client, userId, leaveTypeName, daysToDeduct) {
  if (!userId || !leaveTypeName) return;
  const days = daysToDeduct != null ? parseFloat(daysToDeduct) : 0;
  if (!Number.isFinite(days) || days <= 0) return;

  // Balance protection: ensure sufficient remaining credits (earned - used + adjusted).
  const bal = await client.query(
    `SELECT earned_days, used_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     LIMIT 1
     FOR UPDATE`,
    [userId, leaveTypeName]
  );
  const earned = bal.rows.length > 0 ? parseFloat(bal.rows[0].earned_days ?? 0) : 0;
  const used = bal.rows.length > 0 ? parseFloat(bal.rows[0].used_days ?? 0) : 0;
  const adjusted = bal.rows.length > 0 ? parseFloat(bal.rows[0].adjusted_days ?? 0) : 0;
  const remaining = earned - used + adjusted;
  if (days > remaining) {
    const msg = `Insufficient leave balance for ${leaveTypeName}. Remaining ${remaining.toFixed(
      2
    )}, requested ${days.toFixed(2)}.`;
    const err = new Error(msg);
    err.statusCode = 400;
    throw err;
  }

  await client.query(
    `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
     VALUES ($1::uuid, $2::text, 0, $3::numeric, 0, 0, now()::date, now()::date, now(), now())
     ON CONFLICT (user_id, leave_type)
     DO UPDATE SET used_days = COALESCE(leave_balances.used_days, 0) + EXCLUDED.used_days,
                   updated_at = now()`,
    [userId, leaveTypeName, days]
  );
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
      WHERE EXTRACT(ISODOW FROM gs::date) < 6
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
        numberOfDays: days,
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
        [userId, leaveTypeId, startStr, endStr, daysHolidayAware ?? days, reason || null, payloadDetails]
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
          number_of_days: daysHolidayAware ?? days,
        },
      });
      const typeName = leave_type ? String(leave_type) : null;
      await client.query('COMMIT');
      res.status(201).json(mapLeaveRowToApi({ ...row, leave_type_name: typeName }));
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

      // FIX #7 (backend): Validate numberOfDays is positive and <= computed (holiday-aware) days.
      const effectiveDaysSubmit = daysHolidayAwareSubmit ?? days;
      if (effectiveDaysSubmit == null || effectiveDaysSubmit <= 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
      }
      if (effectiveDaysSubmit != null && days > effectiveDaysSubmit) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          error: `Requested days (${days}) exceed the computed Mon–Fri working days for the selected range (${effectiveDaysSubmit}).`,
        });
      }

      const validation = validateEmployeeLeaveRequest({
        leaveType: leave_type,
        otherPurpose: otherPurpose || null,
        startDateStr: startStr,
        endDateStr: endStr,
        numberOfDays: days,
        hasAttachment: false,
      });
      if (!validation.valid) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: validation.error });
      }

      // FIX #6 (backend): POST /submit creates a new record — no attachment yet.
      // Block attachment-required leave types from direct submit. Employee must save draft first.
      const { getRule: getLeaveRule } = require('./leaveTypeRules');
      const submitRule = getLeaveRule(leave_type);
      if (submitRule && submitRule.requires_attachment) {
        const needsAttach = leave_type === 'sickLeave'
          ? (days > (submitRule.requires_attachment_when_over_days || 5))
          : true;
        if (needsAttach) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `${leave_type} requires a supporting document. Please save a draft, upload the document, then submit.`,
          });
        }
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
          VALUES ($1::uuid, $1::uuid, $2::uuid, $3::date, $4::date, $5::numeric, $5::numeric, $6::text, $7::jsonb, 'pending', now(), now())
          RETURNING *`,
        [userId, leaveTypeId, startStr, endStr, daysHolidayAwareSubmit ?? days, reason || null, payloadDetails]
      );

      const row = q.rows[0];
      // FIX #2: Only one history row on submit (removed duplicate 'created' + 'submitted' pair).
      await insertLeaveRequestHistory(client, {
        leaveRequestId: row.id,
        action: 'submitted',
        fromStatus: null,
        toStatus: 'pending',
        actedBy: userId,
        remarks: reason || null,
        metadataJson: {
          leave_type: leave_type || null,
          start_date: startStr,
          end_date: endStr,
          number_of_days: days,
        },
      });
      // FIX #5a: Increment pending_days on direct submit (no existing draft ID).
      if (days != null && days > 0) {
        const leaveTypeName = leave_type ? String(leave_type) : null;
        if (leaveTypeName) {
          await client.query(
            `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
             VALUES ($1::uuid, $2::text, 0, 0, $3::numeric, 0, now()::date, now()::date, now(), now())
             ON CONFLICT (user_id, leave_type)
             DO UPDATE SET pending_days = COALESCE(leave_balances.pending_days, 0) + EXCLUDED.pending_days,
                           updated_at = now()`,
            [userId, leaveTypeName, days]
          );
        }
      }
      const typeName = leave_type ? String(leave_type) : null;
      await client.query('COMMIT');
      res.status(201).json(mapLeaveRowToApi({ ...row, leave_type_name: typeName }));
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[leave POST /submit]', err);
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
      if (leave_type && startStr && endStr && days != null) {
        // FIX #7 (backend): Validate numberOfDays correctness on PUT.
        if (days <= 0) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Number of working days must be greater than 0.' });
        }
        const computedDays = await computeNumberOfDays(startStr, endStr, client);
        if (computedDays != null && days > computedDays) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `Requested days (${days}) exceed the computed Mon–Fri working days for the selected range (${computedDays}).`,
          });
        }

        const validation = validateEmployeeLeaveRequest({
          leaveType: leave_type,
          otherPurpose: otherPurpose || null,
          startDateStr: startStr,
          endDateStr: endStr,
          numberOfDays: days,
          hasAttachment: false,
        });
        if (!validation.valid) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: validation.error });
        }

        // FIX #6 (backend): When transitioning to pending via PUT, check attachment.
        if (nextStatus === 'pending') {
          const existingRow = await client.query(
            'SELECT attachment_path FROM leave_requests WHERE id = $1',
            [id]
          );
          const hasAttachment = !!(existingRow.rows[0]?.attachment_path);
          const { getRule } = require('./leaveTypeRules');
          const rule = getRule(leave_type);
          if (rule && rule.requires_attachment && !hasAttachment) {
            const needsAttach = leave_type === 'sickLeave'
              ? (days > (rule.requires_attachment_when_over_days || 5))
              : true;
            if (needsAttach) {
              await client.query('ROLLBACK');
              return res.status(400).json({
                error: `${leave_type} requires a supporting document before submission. Please upload one first.`,
              });
            }
          }
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
        [leaveTypeId, startStr, endStr, days, reason || null, payloadDetails, id, userId, nextStatus]
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
          number_of_days: days,
        },
      });
      // FIX #5b: Update pending_days when status transitions to/from pending via PUT.
      // Cases: draft→pending (+pending_days), returned→pending (+pending_days),
      //        draft→draft or returned→returned (no balance change).
      const leaveTypeName = leave_type ? String(leave_type) : null;
      if (leaveTypeName && days != null && days > 0) {
        if (nextStatus === 'pending' && status !== 'pending') {
          // Moving INTO pending: increment pending_days.
          await client.query(
            `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
             VALUES ($1::uuid, $2::text, 0, 0, $3::numeric, 0, now()::date, now()::date, now(), now())
             ON CONFLICT (user_id, leave_type)
             DO UPDATE SET pending_days = COALESCE(leave_balances.pending_days, 0) + EXCLUDED.pending_days,
                           updated_at = now()`,
            [userId, leaveTypeName, days]
          );
        }
      }
      await client.query('COMMIT');
      res.json(mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName }));
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

    // FIX #5c: Decrement pending_days on cancel (only if it was pending — not draft).
    if (status === 'pending') {
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
          await client.query(
            `UPDATE leave_balances
             SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
                 updated_at = now()
             WHERE user_id = $1::uuid AND leave_type = $2::text`,
            [cancelUserId, ltName, cancelDays]
          );
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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

// GET /api/leave (admin list)
// Query params: status, leave_type, user_id, limit,
//               start_date_from, start_date_to, created_from, created_to
router.get('/', protect, requireAdmin, async (req, res) => {
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
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.user_id, lr.employee_id)
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

// GET /api/leave/pending
router.get('/pending', protect, requireAdmin, async (_req, res) => {
  try {
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE lr.status = 'pending'
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       LIMIT 200`
    );
    res.json(rows.rows.map(mapLeaveRowToApi));
  } catch (err) {
    console.error('[leave GET /pending]', err);
    res.status(500).json({ error: 'Failed to fetch pending leave requests' });
  }
});

// PATCH /api/leave/:id/approve
router.patch('/:id/approve', protect, requireAdmin, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
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
             reviewed_at = now(),
             approved_by = COALESCE(approved_by, $2::uuid),
             approved_at = COALESCE(approved_at, now()),
             updated_at = now()
         WHERE id = $1
         RETURNING *`,
        [id, reviewerId, remarks]
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
      await upsertLeaveBalanceDeduction(client, targetUserId, leaveTypeName, days);

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
      res.json(mapLeaveRowToApi({ ...row, leave_type_name: leaveTypeName }));
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

// PATCH /api/leave/:id/reject
router.patch('/:id/reject', protect, requireAdmin, async (req, res) => {
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

    const { historyAction } = validateAdminTransition({
      currentStatus: currentRow.status,
      desiredStatus: 'rejected',
    });

    await client.query(
      `UPDATE leave_requests
       SET status = 'rejected',
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
      fromStatus: 'pending',
      toStatus: 'rejected',
      actedBy: reviewerId,
      remarks: remarks || null,
      metadataJson: null,
    });

    // FIX #5d: Decrement pending_days on reject.
    const rejectDays = currentRow.days != null ? parseFloat(currentRow.days) : null;
    const rejectUserId = currentRow.user_id || currentRow.employee_id;
    const rejectLtName = currentRow.leave_type_name || null;
    if (rejectDays && rejectDays > 0 && rejectUserId && rejectLtName) {
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
             updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [rejectUserId, rejectLtName, rejectDays]
      );
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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
router.patch('/:id/revoke', protect, requireAdmin, async (req, res) => {
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

    // 2. Restore used_days balance (reverse the deduction from approval).
    if (revokeDays && revokeDays > 0 && targetUserId && ltName) {
      await client.query(
        `UPDATE leave_balances
         SET used_days  = GREATEST(0, COALESCE(used_days, 0)  - $3::numeric),
             pending_days = COALESCE(pending_days, 0) + $3::numeric,
             updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [targetUserId, ltName, revokeDays]
      );
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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
router.patch('/:id/return', protect, requireAdmin, async (req, res) => {
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

    const { historyAction } = validateAdminTransition({
      currentStatus: currentRow.status,
      desiredStatus: 'returned',
    });

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
      fromStatus: 'pending',
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
      await client.query(
        `UPDATE leave_balances
         SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
             updated_at = now()
         WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [returnUserId, returnLtName, returnDays]
      );
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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
// BALANCES
// ============================

// GET /api/leave/balances/:userId (self or admin)
router.get('/balances/:userId', protect, async (req, res) => {
  const requesterId = req.user?.id;
  const role = req.user?.role;
  if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
  const targetId = req.params.userId;
  const isAdmin = role === 'admin';
  if (!isAdmin && requesterId !== targetId) {
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
    const isAdmin = role === 'admin';
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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
    const isAdmin = role === 'admin';
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
    res.json(mapLeaveRowToApi(out.rows[0]));
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
    const isAdmin = role === 'admin';
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
    const isAdmin = role === 'admin';
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
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

