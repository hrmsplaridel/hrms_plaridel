const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/dtr-corrections - list (?status=pending|approved|rejected|All, ?employee_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'All';
    const employeeId = req.query.employee_id;

    let query = `
      SELECT c.id, c.employee_id, c.attendance_date, c.requested_time_in, c.requested_time_out,
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
    const { employee_id, attendance_date, requested_time_in, requested_time_out, reason } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr';
    const targetEmployeeId = isAdmin && employee_id ? employee_id : userId;

    if (!targetEmployeeId || !attendance_date || !reason || !reason.trim()) {
      return res.status(400).json({ error: 'Employee, attendance date, and reason are required' });
    }
    if (!isAdmin && targetEmployeeId !== userId) {
      return res.status(403).json({ error: 'You can only submit corrections for yourself' });
    }

    const result = await pool.query(
      `INSERT INTO dtr_corrections (employee_id, attendance_date, requested_time_in, requested_time_out, reason, status)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5, 'pending')
       RETURNING id, employee_id, attendance_date, requested_time_in, requested_time_out, reason, status, created_at`,
      [
        targetEmployeeId,
        attendance_date,
        requested_time_in || null,
        requested_time_out || null,
        reason.trim(),
      ]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[dtr-corrections POST]', err);
    res.status(500).json({ error: 'Failed to create DTR correction' });
  }
});

// PATCH /api/dtr-corrections/:id/review - approve or reject (admin only)
router.patch('/:id/review', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { status, review_notes } = req.body;
    if (!status || !['approved', 'rejected'].includes(status)) {
      return res.status(400).json({ error: 'status must be approved or rejected' });
    }
    const reviewerId = req.user?.id;

    const result = await pool.query(
      `UPDATE dtr_corrections SET status = $1, reviewed_by = $2, reviewed_at = now(), review_notes = $3, updated_at = now()
       WHERE id = $4 AND dtr_corrections.status = 'pending'
       RETURNING id, employee_id, attendance_date, requested_time_in, requested_time_out, reason, status, reviewed_by, reviewed_at, review_notes`,
      [status, reviewerId, review_notes?.trim() || null, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Correction not found or already reviewed' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[dtr-corrections PATCH]', err);
    res.status(500).json({ error: 'Failed to review DTR correction' });
  }
});

module.exports = router;
