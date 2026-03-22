const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { validateEmployeeLeaveRequest } = require('./leaveTypeRules');

const router = express.Router();
const protect = [authMiddleware];

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const LEAVE_ATTACHMENT_SUBDIR = 'leave-attachments';

function toIsoDateStr(val) {
  if (!val) return null;
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  const s = String(val);
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? m[0] : null;
}

function isWeekday(dateObj) {
  const d = dateObj.getDay(); // 0 Sun .. 6 Sat
  return d !== 0 && d !== 6;
}

/** Mon–Fri day count (inclusive), acceptable for now. */
function computeNumberOfDays(startStr, endStr) {
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

function canEmployeeEdit(status) {
  return status === 'draft' || status === 'returned';
}

function canEmployeeCancel(status) {
  // Strict: pending -> cancelled only
  return status === 'pending';
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
    const days = computeNumberOfDays(startStr, endStr);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
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
        [userId, leaveTypeId, startStr, endStr, days, reason || null, payloadDetails]
      );

      const row = q.rows[0];
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
    const days = computeNumberOfDays(startStr, endStr);
    if (!startStr || !endStr) return res.status(400).json({ error: 'start_date and end_date are required' });

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
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
        [userId, leaveTypeId, startStr, endStr, days, reason || null, payloadDetails]
      );

      const row = q.rows[0];
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
    if (!canEmployeeEdit(status)) return res.status(400).json({ error: 'Only draft or returned requests can be updated' });

    const { leave_type, start_date, end_date, reason, details, status: desiredStatus, ...rest } = req.body || {};
    const startStr = toIsoDateStr(start_date);
    const endStr = toIsoDateStr(end_date);
    const days = computeNumberOfDays(startStr, endStr);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const leaveTypeId = await ensureLeaveTypeIdByName(client, leave_type);
      if (leave_type != null && String(leave_type).trim().isNotEmpty && !leaveTypeId) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid leave type' });
      }
      const payloadDetails = details && typeof details === 'object'
        ? details
        : { ...rest, leave_type, start_date: startStr, end_date: endStr };
      const otherPurpose = (payloadDetails.other_purpose || payloadDetails.otherPurpose || '').toString();
      if (leave_type && startStr && endStr && days != null) {
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
      }
      // Prevent overlapping ranges when dates are being set/changed.
      if (startStr && endStr) {
        const hasOverlap = await hasOverlappingLeaveRequest(client, userId, startStr, endStr, id);
        if (hasOverlap) {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: 'Overlapping leave request exists' });
        }
      }

      // Strict transitions:
      // - draft -> pending
      // - returned -> pending
      // - draft stays draft; returned stays returned (if not resubmitting)
      // - No other transitions allowed from this endpoint.
      let nextStatus = status;
      if (desiredStatus != null) {
        const want = String(desiredStatus).trim();
        if (want === 'pending') {
          if (status === 'draft' || status === 'returned') nextStatus = 'pending';
          else {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: `Invalid status transition: ${status} -> pending` });
          }
        } else if (want === 'draft') {
          if (status === 'draft') nextStatus = 'draft';
          else {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: `Invalid status transition: ${status} -> draft` });
          }
        } else if (want === 'returned') {
          if (status === 'returned') nextStatus = 'returned';
          else {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: `Invalid status transition: ${status} -> returned` });
          }
        } else {
          await client.query('ROLLBACK');
          return res.status(400).json({ error: `Invalid status value '${want}'` });
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
      await client.query('COMMIT');
      const row = q.rows[0];
      res.json(mapLeaveRowToApi({ ...row, leave_type_name: leave_type ? String(leave_type) : null }));
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('[leave PUT /:id]', err);
    res.status(500).json({ error: 'Failed to update leave request' });
  }
});

// PATCH /api/leave/:id/cancel
router.patch('/:id/cancel', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const reason = (req.body?.reason || '').toString().trim() || null;
  try {
    const q = await pool.query(
      'SELECT id, status FROM leave_requests WHERE id = $1 AND (user_id = $2 OR employee_id = $2)',
      [id, userId]
    );
    if (q.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const status = q.rows[0].status;
    if (!canEmployeeCancel(status)) {
      return res.status(400).json({ error: `Invalid status transition: ${status} -> cancelled` });
    }

    await pool.query(
      `UPDATE leave_requests
       SET status = 'cancelled',
           details = COALESCE(details, '{}'::jsonb) || jsonb_build_object('cancel_reason', $3::text),
           updated_at = now()
       WHERE id = $1 AND (user_id = $2 OR employee_id = $2)`,
      [id, userId, reason]
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
    console.error('[leave PATCH /:id/cancel]', err);
    res.status(500).json({ error: 'Failed to cancel leave request' });
  }
});

// GET /api/leave/my
router.get('/my', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE (lr.user_id = $1 OR lr.employee_id = $1)
         AND ($2::text IS NULL OR lr.status = $2)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC`,
      [userId, status]
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

// GET /api/leave (admin list; optional status/leave_type/user_id)
router.get('/', protect, requireAdmin, async (req, res) => {
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    const leaveType = (req.query?.leave_type || '').toString().trim() || null;
    const userId = (req.query?.user_id || '').toString().trim() || null;
    const limit = req.query?.limit ? parseInt(req.query.limit, 10) : null;
    const safeLimit = Number.isFinite(limit) && limit > 0 ? Math.min(limit, 500) : null;

    const rows = await pool.query(
      `SELECT lr.*, lt.name AS leave_type_name, u.full_name AS employee_full_name
       FROM leave_requests lr
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       LEFT JOIN users u ON u.id = COALESCE(lr.employee_id, lr.user_id)
       WHERE ($1::text IS NULL OR lr.status = $1)
         AND ($2::text IS NULL OR lt.name = $2)
         AND ($3::uuid IS NULL OR lr.user_id = $3 OR lr.employee_id = $3)
       ORDER BY lr.updated_at DESC NULLS LAST, lr.created_at DESC
       ${safeLimit ? 'LIMIT ' + safeLimit : ''}`,
      [status, leaveType, userId]
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
      // Strict: ONLY allow approve from pending.
      if (r.status !== 'pending') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: `Invalid status transition: ${r.status} -> approved` });
      }

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
  try {
    const current = await pool.query('SELECT status FROM leave_requests WHERE id = $1', [id]);
    if (current.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    if (current.rows[0].status !== 'pending') {
      return res.status(400).json({
        error: `Invalid status transition: ${current.rows[0].status} -> rejected`,
      });
    }

    const updated = await pool.query(
      `UPDATE leave_requests
       SET status = 'rejected',
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [id, reviewerId, remarks]
    );
    res.json(mapLeaveRowToApi(updated.rows[0]));
  } catch (err) {
    console.error('[leave PATCH /:id/reject]', err);
    res.status(500).json({ error: 'Failed to reject leave request' });
  }
});

// PATCH /api/leave/:id/return
router.patch('/:id/return', protect, requireAdmin, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '').toString().trim() || null;
  try {
    const current = await pool.query('SELECT status FROM leave_requests WHERE id = $1', [id]);
    if (current.rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    if (current.rows[0].status !== 'pending') {
      return res.status(400).json({
        error: `Invalid status transition: ${current.rows[0].status} -> returned`,
      });
    }

    const updated = await pool.query(
      `UPDATE leave_requests
       SET status = 'returned',
           reviewer_id = $2::uuid,
           reviewer_remarks = $3::text,
           reviewed_at = now(),
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [id, reviewerId, remarks]
    );
    res.json(mapLeaveRowToApi(updated.rows[0]));
  } catch (err) {
    console.error('[leave PATCH /:id/return]', err);
    res.status(500).json({ error: 'Failed to return leave request' });
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

