const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/positions - list all (?status=Active|Inactive|All, ?department_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const { status = 'Active', department_id } = req.query;
    const params = [];
    const conditions = [];
    let i = 1;

    if (status === 'Active') {
      conditions.push('(p.is_active IS NULL OR p.is_active = true)');
    } else if (status === 'Inactive') {
      conditions.push('p.is_active = false');
    }
    if (department_id) {
      conditions.push(`p.department_id = $${i++}`);
      params.push(department_id);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT p.id, p.name, p.description, p.department_id, p.is_active,
              d.name AS department_name
       FROM positions p
       LEFT JOIN departments d ON p.department_id = d.id
       ${where}
       ORDER BY p.name`,
      params
    );

    const rows = result.rows.map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      department_id: r.department_id,
      department_name: r.department_name,
      is_active: r.is_active ?? true,
      departments: r.department_name ? { name: r.department_name } : null,
    }));
    res.json(rows);
  } catch (err) {
    console.error('[positions GET]', err);
    res.status(500).json({ error: 'Failed to fetch positions' });
  }
});

// POST /api/positions - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, description, department_id, is_active = true } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }

    const result = await pool.query(
      `INSERT INTO positions (name, description, department_id, is_active)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, description, department_id, is_active`,
      [name.trim(), description?.trim() || null, department_id || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[positions POST]', err);
    res.status(500).json({ error: 'Failed to create position' });
  }
});

// PUT /api/positions/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, department_id, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (department_id !== undefined) { updates.push(`department_id = $${i++}`); values.push(department_id || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE positions SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, name, description, department_id, is_active`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Position not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[positions PUT]', err);
    res.status(500).json({ error: 'Failed to update position' });
  }
});

// DELETE /api/positions/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM positions WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Position not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[positions DELETE]', err);
    res.status(500).json({ error: 'Failed to delete position' });
  }
});

module.exports = router;
