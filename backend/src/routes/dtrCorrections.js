const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const { isValidIsoDate, validateDtrPunchDates } = require('../services/dtrPunchDateValidation');
const { enqueueEmployeeRangeReconciliation } = require('../services/dtrMonthEndReconciliation');
const { applyApprovedCorrectionToSummary, getCorrectionShift } = require('./dtrDailySummary');
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
  broadcast = broadcastBiometricUpdate } = {}) {
  const router = express.Router();
  router.use(auth);
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
    const result = await db.query(
      `SELECT c.*, u.full_name AS employee_name, reviewer.full_name AS reviewer_name,
              c.attendance_date::text AS attendance_date
         FROM dtr_corrections c JOIN users u ON u.id = c.employee_id
         LEFT JOIN users reviewer ON reviewer.id = c.reviewed_by
        WHERE ($1::boolean OR c.employee_id = $2::uuid)
        ORDER BY (c.status = 'pending') DESC, c.created_at DESC, c.id DESC
        LIMIT 50 OFFSET $3`, [review, req.user.id, offset]);
    res.json(result.rows);
  }));

  router.post('/', handle(async (req, res) => {
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
      await client.query('COMMIT');
      res.status(201).json(result.rows[0]);
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
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
    if (decision === 'approved') broadcast('dtr_refresh', { action: 'correction_approved', userId: row.employee_id, date: row.attendance_date });
    res.json({ status: decision });
  }));
  return router;
}
module.exports = createRouter();
module.exports.createRouter = createRouter;
