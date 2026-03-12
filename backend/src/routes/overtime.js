const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin, requireAdminOrSupervisor } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/overtime - list (?status=pending|approved|rejected|All, ?employee_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'All';
    const employeeId = req.query.employee_id;

    let query = `
      SELECT o.id, o.employee_id, o.ot_date, o.time_start, o.time_end, o.total_hours, o.reason,
             o.status, o.approved_by, o.approved_at, o.review_notes, o.added_to_payroll, o.created_at,
             u.full_name AS employee_name
      FROM overtime_requests o
      JOIN users u ON u.id = o.employee_id
      WHERE 1=1`;
    const params = [];
    let i = 1;
    if (status === 'pending') { query += ` AND o.status = $${i++}`; params.push('pending'); }
    else if (status === 'approved') { query += ` AND o.status = $${i++}`; params.push('approved'); }
    else if (status === 'rejected') { query += ` AND o.status = $${i++}`; params.push('rejected'); }
    if (employeeId) { query += ` AND o.employee_id = $${i++}`; params.push(employeeId); }
    query += ' ORDER BY o.ot_date DESC, o.created_at DESC';

    const result = await pool.query(query, params);
    res.json(result.rows.map((r) => ({
      id: r.id,
      employee_id: r.employee_id,
      employee_name: r.employee_name,
      ot_date: r.ot_date,
      time_start: r.time_start,
      time_end: r.time_end,
      total_hours: parseFloat(r.total_hours),
      reason: r.reason,
      status: r.status,
      approved_by: r.approved_by,
      approved_at: r.approved_at,
      review_notes: r.review_notes,
      added_to_payroll: r.added_to_payroll ?? false,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('[overtime GET]', err);
    res.status(500).json({ error: 'Failed to fetch overtime requests' });
  }
});

// POST /api/overtime - submit (employee or admin on behalf of employee)
router.post('/', protect, async (req, res) => {
  try {
    const { employee_id, ot_date, time_start, time_end, total_hours, reason } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr' || req.user?.role === 'supervisor';
    const targetEmployeeId = isAdmin && employee_id ? employee_id : userId;

    if (!targetEmployeeId || !ot_date) {
      return res.status(400).json({ error: 'Employee and OT date are required' });
    }
    if (!time_start || !time_end || total_hours == null) {
      return res.status(400).json({ error: 'Time start, time end, and total hours are required' });
    }
    if (!isAdmin && targetEmployeeId !== userId) {
      return res.status(403).json({ error: 'You can only submit overtime for yourself' });
    }

    const result = await pool.query(
      `INSERT INTO overtime_requests (employee_id, ot_date, time_start, time_end, total_hours, reason, status)
       VALUES ($1, $2::date, $3::time, $4::time, $5::numeric, $6, 'pending')
       RETURNING id, employee_id, ot_date, time_start, time_end, total_hours, reason, status, created_at`,
      [targetEmployeeId, ot_date, time_start, time_end, parseFloat(total_hours) || 0, reason?.trim() || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[overtime POST]', err);
    res.status(500).json({ error: 'Failed to create overtime request' });
  }
});

// PATCH /api/overtime/:id/review - approve or reject (supervisor/hr/admin)
router.patch('/:id/review', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    const { id } = req.params;
    const { status, review_notes } = req.body;
    if (!status || !['approved', 'rejected'].includes(status)) {
      return res.status(400).json({ error: 'status must be approved or rejected' });
    }
    const reviewerId = req.user?.id;

    const result = await pool.query(
      `UPDATE overtime_requests SET status = $1, approved_by = $2, approved_at = now(), review_notes = $3, updated_at = now()
       WHERE id = $4 AND status = 'pending'
       RETURNING id, employee_id, ot_date, time_start, time_end, total_hours, reason, status, approved_by, approved_at, review_notes`,
      [status, reviewerId, review_notes?.trim() || null, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Overtime request not found or already reviewed' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[overtime PATCH review]', err);
    res.status(500).json({ error: 'Failed to review overtime request' });
  }
});

// PATCH /api/overtime/:id/payroll - mark as added to payroll (admin)
router.patch('/:id/payroll', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `UPDATE overtime_requests SET added_to_payroll = true, updated_at = now()
       WHERE id = $1 AND status = 'approved'
       RETURNING id, employee_id, ot_date, total_hours, added_to_payroll`,
      [id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Approved overtime request not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[overtime PATCH payroll]', err);
    res.status(500).json({ error: 'Failed to update payroll flag' });
  }
});

module.exports = router;
