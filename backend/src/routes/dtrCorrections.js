const express = require('express');
const multer = require('multer');
const { MAX_SIZE, validateAttachment } = require('../services/dtrCorrectionAttachment');
const receiveAttachment = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_SIZE, files: 1, fields: 12, fieldSize: 4096 } }).single('file');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const { isValidIsoDate, validateDtrPunchDates } = require('../services/dtrPunchDateValidation');
const { enqueueEmployeeRangeReconciliation } = require('../services/dtrMonthEndReconciliation');
const { applyApprovedCorrectionToSummary, getCorrectionShift } = require('./dtrDailySummary');
const { getShiftType } = require('../services/shiftAttendance');
const { broadcastBiometricUpdate } = require('../websockets/biometricStream');

const fields = ['time_in', 'break_out', 'break_in', 'time_out'];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function fail(message, status = 400) { throw Object.assign(new Error(message), { status }); }
function fingerprint(row) {
  return JSON.stringify([row?.id ?? null, ...fields.map(k => row?.[k] ? new Date(row[k]).toISOString() : null),
    row?.source ?? null, row?.updated_at ? new Date(row.updated_at).toISOString() : null]);
}

function createRouter({ db = pool, auth = authMiddleware, apply = applyApprovedCorrectionToSummary,
  shiftFor = getCorrectionShift, enqueue = enqueueEmployeeRangeReconciliation,
  broadcast = broadcastBiometricUpdate,
  notifications = require('../services/dtrCorrectionNotifications') } = {}) {
  const router = express.Router();
  router.use(auth);
  async function notify(action) {
    try { await action(); } catch (error) { console.error('[dtrCorrections] notification delivery failed', error); }
  }
  const handle = fn => async (req, res) => {
    try { await fn(req, res); } catch (error) {
      if (!error.status) console.error('[dtrCorrections]', error);
      res.status(error.status || 500).json({ error: error.status ? error.message : 'Unable to process attendance correction.' });
    }
  };
  router.get('/', handle(async (req, res) => {
    const review = req.query.review === 'true';
    if (review && !['admin', 'hr'].includes(req.user.role)) fail('HR or admin access required.', 403);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
    const status = String(req.query.status || '').trim().toLowerCase();
    if (status && !['pending', 'approved', 'rejected'].includes(status)) fail('Invalid correction status.');
    const search = String(req.query.search || '').trim();
    if (search.length > 100) fail('Search is too long.');
    const values = [review, req.user.id, offset];
    let filters = '';
    if (status) {
      values.push(status);
      filters += ` AND c.status = $${values.length}`;
    }
    if (search) {
      values.push(`%${search.replace(/[\\%_]/g, '\\$&')}%`);
      filters += ` AND (u.full_name ILIKE $${values.length} ESCAPE '\\' OR u.employee_number::text ILIKE $${values.length} ESCAPE '\\')`;
    }
    const result = await db.query(
      `SELECT c.*, u.full_name AS employee_name, reviewer.full_name AS reviewer_name,
              c.attendance_date::text AS attendance_date
         FROM dtr_corrections c JOIN users u ON u.id = c.employee_id
         LEFT JOIN users reviewer ON reviewer.id = c.reviewed_by
        WHERE ($1::boolean OR c.employee_id = $2::uuid)${filters}
        ORDER BY (c.status = 'pending') DESC, c.created_at DESC, c.id DESC
        LIMIT 50 OFFSET $3`, values);
    res.json(result.rows);
  }));

  router.post('/', (req, res, next) => {
    receiveAttachment(req, res, error => error
      ? res.status(400).json({ error: error.code === 'LIMIT_FILE_SIZE' ? 'Attachment must be 5 MB or smaller.' : 'Invalid attachment upload.' })
      : next());
  }, handle(async (req, res) => {
    const attachment = validateAttachment(req.file);
    const date = req.body.attendance_date;
    const reason = String(req.body.reason || '').trim();
    if (!isValidIsoDate(date)) fail('Choose a valid attendance date.');
    if (reason.length < 10 || reason.length > 1000) fail('Reason must contain 10 to 1000 characters.');
    const punches = Object.fromEntries(fields.map(k => [k, req.body[`requested_${k}`] ?? null]));
    if (!Object.values(punches).some(Boolean)) fail('Enter at least one requested punch.');
    for (const value of Object.values(punches)) {
      if (value != null && (typeof value !== 'string' || !/(Z|[+-]\d{2}:\d{2})$/.test(value))) {
        fail('Punches must include their timezone.');
      }
    }
    const shift = await shiftFor(req.user.id, date);
    if (!shift) fail('No shift is assigned for this date.');
    const client = await db.connect();
    let submitted;
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`dtr-correction:${req.user.id}:${date}`]);
      const pending = await client.query("SELECT id FROM dtr_corrections WHERE employee_id=$1 AND attendance_date=$2 AND status='pending'", [req.user.id, date]);
      if (pending.rows.length) fail('A correction for this date is already pending.', 409);
      const before = await client.query('SELECT * FROM dtr_daily_summary WHERE employee_id=$1 AND attendance_date=$2 FOR UPDATE', [req.user.id, date]);
      const original = before.rows[0] || null;
      const merged = Object.fromEntries(fields.map(k => [k, punches[k] ?? original?.[k] ?? null]));
      const check = validateDtrPunchDates({ attendanceDate: date, punches: merged, shiftInfo: shift,
        todayDate: new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' }).format(new Date()) });
      if (!check.valid) fail(check.error);
      if (fields.every(k => !punches[k] || (original?.[k] && new Date(punches[k]).getTime() === new Date(original[k]).getTime()))) {
        fail('The requested punches are unchanged.');
      }
      const result = await client.query(
        `INSERT INTO dtr_corrections (employee_id, attendance_date, reason,
          requested_time_in, requested_break_out, requested_break_in, requested_time_out, original_record)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb) RETURNING *`,
        [req.user.id, date, reason, ...fields.map(k => punches[k]), JSON.stringify(original)]);
      if (attachment) await client.query(
        'INSERT INTO dtr_correction_attachments (correction_id, file_name, mime_type, content) VALUES ($1,$2,$3,$4)',
        [result.rows[0].id, attachment.name, attachment.mime, attachment.content]);
      await client.query('COMMIT');
      submitted = result.rows[0];
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
    await notify(() => notifications.submitted(db, { ...submitted, employee_id: req.user.id, attendance_date: date }));
    res.status(201).json(submitted);
  }));

  router.get('/original/:date', handle(async (req, res) => {
    if (!isValidIsoDate(req.params.date)) fail('Choose a valid attendance date.');
    const [result, shift] = await Promise.all([
      db.query(`SELECT time_in, break_out, break_in, time_out, status
        FROM dtr_daily_summary WHERE employee_id=$1 AND attendance_date=$2`,
        [req.user.id, req.params.date]),
      shiftFor(req.user.id, req.params.date),
    ]);
    res.json({ ...(result.rows[0] || {}), shift_punch_mode: getShiftType(shift) });
  }));

  router.get('/:id', handle(async (req, res) => {
    if (!uuid.test(req.params.id)) fail('Invalid correction ID.');
    const result = await db.query(`SELECT c.*, c.attendance_date::text AS attendance_date,
      u.full_name AS employee_name, r.full_name AS reviewer_name,
      evidence.file_name AS attachment_name, evidence.mime_type AS attachment_mime_type
      FROM dtr_corrections c JOIN users u ON u.id=c.employee_id
      LEFT JOIN users r ON r.id=c.reviewed_by
      LEFT JOIN dtr_correction_attachments evidence ON evidence.correction_id=c.id
      WHERE c.id=$1 AND (c.employee_id=$2 OR $3::boolean)`,
      [req.params.id, req.user.id, ['admin', 'hr'].includes(req.user.role)]);
    if (!result.rows.length) fail('Correction not found or access denied.', 404);
    res.json(result.rows[0]);
  }));

  router.get('/:id/attachment', handle(async (req, res) => {
    if (!uuid.test(req.params.id)) fail('Invalid correction ID.');
    const result = await db.query(`SELECT a.* FROM dtr_correction_attachments a
      JOIN dtr_corrections c ON c.id=a.correction_id
      WHERE c.id=$1 AND (c.employee_id=$2 OR $3::boolean)`,
      [req.params.id, req.user.id, ['admin', 'hr'].includes(req.user.role)]);
    if (!result.rows.length) fail('Attachment not found or access denied.', 404);
    const file = result.rows[0];
    res.set({ 'Content-Type': file.mime_type, 'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff', 'Content-Disposition': "attachment; filename*=UTF-8''" + encodeURIComponent(file.file_name) });
    res.send(file.content);
  }));

  router.post('/:id/review', requireAdminOrHr, handle(async (req, res) => {
    if (!uuid.test(req.params.id)) fail('Invalid correction ID.');
    const decision = req.body.decision;
    const notes = String(req.body.notes || '').trim();
    if (!['approved', 'rejected'].includes(decision)) fail('Invalid review decision.');
    if (notes.length < 10 || notes.length > 1000) fail('Review notes must contain 10 to 1000 characters.');
    const client = await db.connect();
    let row;
    try {
      await client.query('BEGIN');
      const result = await client.query('SELECT *, attendance_date::text AS attendance_date FROM dtr_corrections WHERE id=$1 FOR UPDATE', [req.params.id]);
      row = result.rows[0];
      if (!row) fail('Correction not found.', 404);
      if (row.employee_id === req.user.id) fail('You cannot review your own attendance correction.', 403);
      if (row.status !== 'pending') fail('This correction has already been reviewed.', 409);
      let applied = null;
      if (decision === 'approved') {
        const current = await client.query('SELECT * FROM dtr_daily_summary WHERE employee_id=$1 AND attendance_date=$2 FOR UPDATE', [row.employee_id, row.attendance_date]);
        if (fingerprint(current.rows[0]) !== fingerprint(row.original_record)) fail('Attendance changed after submission. Reject this request and ask the employee to submit a new one.', 409);
        const outcome = await apply(client, row);
        if (outcome.error) fail(outcome.error);
        const after = await client.query('SELECT * FROM dtr_daily_summary WHERE employee_id=$1 AND attendance_date=$2', [row.employee_id, row.attendance_date]);
        applied = after.rows[0];
        await enqueue(client, { employeeId: row.employee_id, dateFrom: row.attendance_date,
          dateTo: row.attendance_date, reason: 'attendance_correction_approved', metadata: { correctionId: row.id } });
      }
      await client.query(`UPDATE dtr_corrections SET status=$2, reviewed_by=$3, reviewed_at=now(),
        review_notes=$4, applied_record=$5::jsonb, updated_at=now() WHERE id=$1`,
        [row.id, decision, req.user.id, notes, JSON.stringify(applied)]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
    await notify(() => notifications.reviewed(db, row, decision));
    if (decision === 'approved') broadcast('dtr_refresh', { action: 'correction_approved', userId: row.employee_id, date: row.attendance_date });
    res.json({ status: decision });
  }));
  return router;
}
module.exports = createRouter();
module.exports.createRouter = createRouter;
