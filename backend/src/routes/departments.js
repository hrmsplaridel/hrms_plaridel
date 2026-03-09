const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/departments - list all (optional: ?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let query =
      'SELECT id, name, description, is_active, created_at FROM departments';
    const params = [];

    if (status === 'Active') {
      query += ' WHERE (is_active IS NULL OR is_active = true)';
    } else if (status === 'Inactive') {
      query += ' WHERE is_active = false';
    }

    query += ' ORDER BY name';

    const result = await pool.query(query, params);
    const rows = result.rows.map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      is_active: r.is_active ?? true,
    }));
    res.json(rows);
  } catch (err) {
    console.error('[departments GET]', err);
    res.status(500).json({ error: 'Failed to fetch departments' });
  }
});

// POST /api/departments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, description, is_active = true } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }

    const result = await pool.query(
      `INSERT INTO departments (name, description, is_active)
       VALUES ($1, $2, $3)
       RETURNING id, name, description, is_active`,
      [name.trim(), description?.trim() || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[departments POST]', err);
    res.status(500).json({ error: 'Failed to create department' });
  }
});

// PUT /api/departments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) {
      updates.push(`name = $${i++}`);
      values.push(name.trim());
    }
    if (description !== undefined) {
      updates.push(`description = $${i++}`);
      values.push(description?.trim() || null);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${i++}`);
      values.push(!!is_active);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE departments SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, name, description, is_active`,
      values
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Department not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[departments PUT]', err);
    res.status(500).json({ error: 'Failed to update department' });
  }
});

// DELETE /api/departments/:id (admin only) - optional, can use PUT to deactivate
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM departments WHERE id = $1 RETURNING id', [id]);
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Department not found' });
    }
    res.status(204).send();
  } catch (err) {
    console.error('[departments DELETE]', err);
    res.status(500).json({ error: 'Failed to delete department' });
  }
});

module.exports = router;
