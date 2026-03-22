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

// GET /api/assignments?employee_id=uuid - list assignments for employee (Schema v2: effective_from/to, override times)
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
              a.override_start_time, a.override_end_time, a.effective_from, a.effective_to, a.is_active, a.remarks,
              d.name AS department_name, p.name AS position_name, s.name AS shift_name,
              s.start_time AS shift_start_time, s.end_time AS shift_end_time,
              s.working_days AS shift_working_days
       FROM assignments a
       LEFT JOIN departments d ON a.department_id = d.id
       LEFT JOIN positions p ON a.position_id = p.id
       LEFT JOIN shifts s ON a.shift_id = s.id
       WHERE a.employee_id = $1 ${statusWhere}
       ORDER BY a.effective_from DESC`,
      [employeeId]
    );

    res.json(result.rows.map((r) => {
      const wd = r.shift_working_days;
      const workingDays = Array.isArray(wd)
        ? wd.map((x) => (typeof x === 'number' ? x : parseInt(x, 10))).filter((x) => Number.isFinite(x))
        : (wd != null ? [1, 2, 3, 4, 5] : null);
      return {
        id: r.id,
        employee_id: r.employee_id,
        department_id: r.department_id,
        position_id: r.position_id,
        shift_id: r.shift_id,
        effective_from: r.effective_from,
        effective_to: r.effective_to,
        is_active: r.is_active ?? true,
        remarks: r.remarks,
        department_name: r.department_name,
        position_name: r.position_name,
        shift_name: r.shift_name,
        start_time: r.override_start_time || r.shift_start_time,
        end_time: r.override_end_time || r.shift_end_time,
        date_assigned: r.effective_from,
        working_days: workingDays?.length ? workingDays : [1, 2, 3, 4, 5],
      };
    }));
  } catch (err) {
    console.error('[assignments GET]', err);
    res.status(500).json({ error: 'Failed to fetch assignments' });
  }
});

// POST /api/assignments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { employee_id, department_id, position_id, shift_id, effective_from, effective_to, is_active = true, remarks } = req.body;
    if (!employee_id || !effective_from) {
      return res.status(400).json({ error: 'employee_id and effective_from are required' });
    }
    const ef = parseDate(effective_from);
    if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
    const et = effective_to != null && effective_to !== '' ? parseDate(effective_to) : null;
    if (effective_to != null && effective_to !== '' && !et) return res.status(400).json({ error: 'Invalid effective_to' });

    await pool.query('BEGIN');
    try {
      if (is_active) {
        await pool.query(
          `UPDATE assignments SET is_active = false, effective_to = $1::date, updated_at = now()
           WHERE employee_id = $2 AND is_active = true AND (effective_to IS NULL OR effective_to >= $1::date)`,
          [ef, employee_id]
        );
      }
      const result = await pool.query(
        `INSERT INTO assignments (employee_id, department_id, position_id, shift_id, effective_from, effective_to, is_active, remarks)
         VALUES ($1, $2, $3, $4, $5::date, $6::date, $7, $8)
         RETURNING id, employee_id, department_id, position_id, shift_id, effective_from, effective_to, is_active, remarks`,
        [employee_id, department_id || null, position_id || null, shift_id || null, ef, et, !!is_active, remarks?.trim() || null]
      );
      await pool.query('COMMIT');
      res.status(201).json(result.rows[0]);
    } catch (e) {
      await pool.query('ROLLBACK');
      throw e;
    }
  } catch (err) {
    console.error('[assignments POST]', err);
    res.status(500).json({ error: 'Failed to create assignment' });
  }
});

// PUT /api/assignments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { department_id, position_id, shift_id, effective_from, effective_to, is_active, remarks } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (department_id !== undefined) { updates.push(`department_id = $${i++}`); values.push(department_id || null); }
    if (position_id !== undefined) { updates.push(`position_id = $${i++}`); values.push(position_id || null); }
    if (shift_id !== undefined) { updates.push(`shift_id = $${i++}`); values.push(shift_id || null); }
    if (effective_from !== undefined) {
      const ef = parseDate(effective_from);
      if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
      updates.push(`effective_from = $${i++}::date`); values.push(ef);
    }
    if (effective_to !== undefined) {
      const et = effective_to === null || effective_to === '' ? null : parseDate(effective_to);
      if (effective_to !== null && effective_to !== '' && !et) return res.status(400).json({ error: 'Invalid effective_to' });
      updates.push(`effective_to = $${i++}::date`); values.push(et);
    }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }
    if (remarks !== undefined) { updates.push(`remarks = $${i++}`); values.push(remarks?.trim() || null); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE assignments SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, employee_id, department_id, position_id, shift_id, effective_from, effective_to, is_active, remarks`,
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
