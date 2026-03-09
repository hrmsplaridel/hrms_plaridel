const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

function parseDate(val) {
  if (!val) return null;
  const d = new Date(val);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

function parseTime(val) {
  if (!val) return null;
  const s = String(val);
  return s.match(/^\d{1,2}:\d{2}/) ? (s.length <= 5 ? s + ':00' : s.substring(0, 8)) : null;
}

// GET /api/assignments?employee_id=uuid - list assignments for employee
router.get('/', protect, async (req, res) => {
  try {
    const employeeId = req.query.employee_id;
    const status = req.query.status || 'Active';

    if (!employeeId) {
      return res.status(400).json({ error: 'employee_id is required' });
    }

    let statusWhere = '';
    if (status === 'Active') statusWhere = 'AND (a.is_active IS NULL OR a.is_active = true)';
    else if (status === 'Inactive') statusWhere = 'AND a.is_active = false';

    const result = await pool.query(
      `SELECT a.id, a.employee_id, a.department_id, a.position_id, a.shift_id,
              a.start_time, a.end_time, a.date_assigned, a.is_active,
              d.name AS department_name, p.name AS position_name, s.name AS shift_name
       FROM assignments a
       LEFT JOIN departments d ON a.department_id = d.id
       LEFT JOIN positions p ON a.position_id = p.id
       LEFT JOIN shifts s ON a.shift_id = s.id
       WHERE a.employee_id = $1 ${statusWhere}
       ORDER BY a.date_assigned DESC`,
      [employeeId]
    );

    res.json(result.rows.map((r) => ({
      id: r.id,
      employee_id: r.employee_id,
      department_id: r.department_id,
      position_id: r.position_id,
      shift_id: r.shift_id,
      start_time: r.start_time,
      end_time: r.end_time,
      date_assigned: r.date_assigned,
      is_active: r.is_active ?? true,
      department_name: r.department_name,
      position_name: r.position_name,
      shift_name: r.shift_name,
      departments: r.department_name ? { name: r.department_name } : null,
      positions: r.position_name ? { name: r.position_name } : null,
      shifts: r.shift_name ? { name: r.shift_name } : null,
    })));
  } catch (err) {
    console.error('[assignments GET]', err);
    res.status(500).json({ error: 'Failed to fetch assignments' });
  }
});

// POST /api/assignments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { employee_id, department_id, position_id, shift_id, start_time, end_time, date_assigned, is_active = true } = req.body;
    if (!employee_id || !date_assigned) {
      return res.status(400).json({ error: 'employee_id and date_assigned are required' });
    }
    const da = parseDate(date_assigned);
    if (!da) return res.status(400).json({ error: 'Invalid date_assigned' });

    const st = parseTime(start_time) || null;
    const et = parseTime(end_time) || null;

    const result = await pool.query(
      `INSERT INTO assignments (employee_id, department_id, position_id, shift_id, start_time, end_time, date_assigned, is_active)
       VALUES ($1, $2, $3, $4, $5::time, $6::time, $7::date, $8)
       RETURNING id, employee_id, department_id, position_id, shift_id, start_time, end_time, date_assigned, is_active`,
      [employee_id, department_id || null, position_id || null, shift_id || null, st || '00:00:00', et || '00:00:00', da, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[assignments POST]', err);
    res.status(500).json({ error: 'Failed to create assignment' });
  }
});

// PUT /api/assignments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { department_id, position_id, shift_id, start_time, end_time, date_assigned, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (department_id !== undefined) { updates.push(`department_id = $${i++}`); values.push(department_id || null); }
    if (position_id !== undefined) { updates.push(`position_id = $${i++}`); values.push(position_id || null); }
    if (shift_id !== undefined) { updates.push(`shift_id = $${i++}`); values.push(shift_id || null); }
    if (start_time !== undefined) { updates.push(`start_time = $${i++}::time`); values.push(parseTime(start_time) || '00:00:00'); }
    if (end_time !== undefined) { updates.push(`end_time = $${i++}::time`); values.push(parseTime(end_time) || '00:00:00'); }
    if (date_assigned !== undefined) {
      const da = parseDate(date_assigned);
      if (!da) return res.status(400).json({ error: 'Invalid date_assigned' });
      updates.push(`date_assigned = $${i++}::date`);
      values.push(da);
    }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE assignments SET ${updates.join(', ')} WHERE id = $${i} RETURNING *`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Assignment not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[assignments PUT]', err);
    res.status(500).json({ error: 'Failed to update assignment' });
  }
});

// DELETE /api/assignments/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM assignments WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Assignment not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[assignments DELETE]', err);
    res.status(500).json({ error: 'Failed to delete assignment' });
  }
});

module.exports = router;
