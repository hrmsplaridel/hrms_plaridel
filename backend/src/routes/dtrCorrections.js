const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const { applyApprovedCorrectionToSummary } = require('./dtrDailySummary');
const {
  notifyHrAdminNewCorrection,
  notifyEmployeeCorrectionDecision,
} = require('../services/dtrCorrectionNotifications');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/dtr-corrections - list (?status=pending|approved|rejected|All, ?employee_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'All';
    const employeeIdRaw = req.query.employee_id;
    const role = req.user?.role;
    const isAdminOrHr = role === 'admin' || role === 'hr';
    const selfId = req.user?.id;

    let employeeId = employeeIdRaw;
    if (!isAdminOrHr) {
      if (employeeIdRaw && employeeIdRaw !== selfId) {
        return res.status(403).json({ error: 'You can only view your own correction requests' });
      }
      employeeId = selfId;
    }

    let query = `
      SELECT c.id, c.employee_id, c.attendance_date, c.requested_time_in, c.requested_time_out,
             c.requested_break_in, c.requested_break_out,
             c.reason, c.status, c.reviewed_by, c.reviewed_at, c.review_notes, c.created_at,
             u.full_name AS employee_name
      FROM dtr_corrections c
      JOIN users u ON u.id = c.employee_id
      WHERE 1=1`;
    const params = [];
    let i = 1;
    if (status === 'pending') { query += ` AND c.status = $${i++}`; params.push('pending'); }
    else if (status === 'approved') { query += ` AND c.status = $${i++}`; params.push('approved'); }
    else if (status === 'rejected') { query += ` AND c.status = $${i++}`; params.push('rejected'); }
    if (employeeId) { query += ` AND c.employee_id = $${i++}`; params.push(employeeId); }
    query += ' ORDER BY c.created_at DESC';

    const result = await pool.query(query, params);
    res.json(result.rows.map((r) => ({
      id: r.id,
      employee_id: r.employee_id,
      employee_name: r.employee_name,
      attendance_date: r.attendance_date,
      requested_time_in: r.requested_time_in,
      requested_time_out: r.requested_time_out,
      requested_break_in: r.requested_break_in,
      requested_break_out: r.requested_break_out,
      reason: r.reason,
      status: r.status,
      reviewed_by: r.reviewed_by,
      reviewed_at: r.reviewed_at,
      review_notes: r.review_notes,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('[dtr-corrections GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR corrections' });
  }
});

// POST /api/dtr-corrections - create (employee or admin)
router.post('/', protect, async (req, res) => {
  try {
    const {
      employee_id,
      attendance_date,
      requested_time_in,
      requested_time_out,
      requested_break_in,
      requested_break_out,
      reason,
    } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr';
    const targetEmployeeId = isAdmin && employee_id ? employee_id : userId;

    if (!targetEmployeeId || !attendance_date || !reason || !String(reason).trim()) {
      return res.status(400).json({ error: 'Employee, attendance date, and reason are required' });
    }
    if (!isAdmin && targetEmployeeId !== userId) {
      return res.status(403).json({ error: 'You can only submit corrections for yourself' });
    }

    const hasTime =
      requested_time_in != null ||
      requested_time_out != null ||
      requested_break_in != null ||
      requested_break_out != null;
    if (!hasTime) {
      return res.status(400).json({ error: 'At least one requested time is required' });
    }

    const dup = await pool.query(
      `SELECT id FROM dtr_corrections
       WHERE employee_id = $1::uuid AND attendance_date = $2::date AND status = 'pending'
       LIMIT 1`,
      [targetEmployeeId, attendance_date]
    );
    if (dup.rows.length > 0) {
      return res.status(409).json({
        error: 'You already have a pending correction request for this date',
      });
    }

    const result = await pool.query(
      `INSERT INTO dtr_corrections (
         employee_id, attendance_date,
         requested_time_in, requested_time_out, requested_break_in, requested_break_out,
         reason, status)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5::timestamptz, $6::timestamptz, $7, 'pending')
       RETURNING id, employee_id, attendance_date, requested_time_in, requested_time_out,
                 requested_break_in, requested_break_out, reason, status, created_at`,
      [
        targetEmployeeId,
        attendance_date,
        requested_time_in || null,
        requested_time_out || null,
        requested_break_in || null,
        requested_break_out || null,
        String(reason).trim(),
      ]
    );
    const row = result.rows[0];
    try {
      const empRes = await pool.query(
        'SELECT full_name FROM users WHERE id = $1::uuid',
        [targetEmployeeId]
      );
      await notifyHrAdminNewCorrection(pool, {
        correctionId: row.id,
        employeeUserId: targetEmployeeId,
        employeeName: empRes.rows[0]?.full_name,
        attendanceDate: row.attendance_date,
        filedByUserId: userId,
      });
    } catch (nErr) {
      console.error('[dtr-corrections POST] notify HR failed', nErr);
    }
    res.status(201).json(row);
  } catch (err) {
    console.error('[dtr-corrections POST]', err);
    res.status(500).json({ error: 'Failed to create DTR correction' });
  }
});

// PATCH /api/dtr-corrections/:id/review - approve or reject (admin or HR)
router.patch('/:id/review', protect, requireAdminOrHr, async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const { status, review_notes } = req.body;
    if (!status || !['approved', 'rejected'].includes(status)) {
      return res.status(400).json({ error: 'status must be approved or rejected' });
    }
    const reviewerId = req.user?.id;

    await client.query('BEGIN');

    const result = await client.query(
      `UPDATE dtr_corrections SET status = $1, reviewed_by = $2, reviewed_at = now(), review_notes = $3, updated_at = now()
       WHERE id = $4::uuid AND dtr_corrections.status = 'pending'
       RETURNING *`,
      [status, reviewerId, review_notes?.trim() || null, id]
    );
    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Correction not found or already reviewed' });
    }

    const row = result.rows[0];

    if (status === 'approved') {
      const apply = await applyApprovedCorrectionToSummary(client, row);
      if (apply.error) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: apply.error });
      }
    }

    await client.query('COMMIT');

    try {
      await notifyEmployeeCorrectionDecision(pool, {
        employeeUserId: row.employee_id,
        correctionId: row.id,
        status: row.status,
        attendanceDate: row.attendance_date,
        reviewNotes: row.review_notes,
      });
    } catch (nErr) {
      console.error('[dtr-corrections PATCH] notify employee failed', nErr);
    }

    res.json({
      id: row.id,
      employee_id: row.employee_id,
      attendance_date: row.attendance_date,
      requested_time_in: row.requested_time_in,
      requested_time_out: row.requested_time_out,
      requested_break_in: row.requested_break_in,
      requested_break_out: row.requested_break_out,
      reason: row.reason,
      status: row.status,
      reviewed_by: row.reviewed_by,
      reviewed_at: row.reviewed_at,
      review_notes: row.review_notes,
    });
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { /* noop */ }
    console.error('[dtr-corrections PATCH]', err);
    res.status(500).json({ error: 'Failed to review DTR correction' });
  } finally {
    client.release();
  }
});

module.exports = router;
