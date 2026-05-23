const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/offices - list (?status=Active|Inactive|All) — authenticated users (for pickers).
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let query =
      'SELECT id, office_number, name, description, is_active, created_at FROM offices';
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
      office_number: r.office_number,
      name: r.name,
      description: r.description,
      is_active: r.is_active ?? true,
    }));
    res.json(rows);
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Offices table not installed. Run backend/scripts/migrate-add-offices-v1.sql',
      });
    }
    console.error('[offices GET]', err);
    res.status(500).json({ error: 'Failed to fetch offices' });
  }
});

// POST /api/offices - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, description, is_active = true } = req.body;
    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }

    const result = await pool.query(
      `INSERT INTO offices (name, description, is_active, office_number)
       SELECT $1, $2, $3, COALESCE(
         (SELECT MIN(g.n) FROM generate_series(1, (SELECT COALESCE(MAX(office_number), 0) + 1 FROM offices)) AS g(n)
          WHERE NOT EXISTS (SELECT 1 FROM offices o2 WHERE o2.office_number = g.n)),
         1
       )
       RETURNING id, office_number, name, description, is_active`,
      [String(name).trim(), description?.trim() || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'An office with this name already exists.' });
    }
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Offices table not installed. Run backend/scripts/migrate-add-offices-v1.sql',
      });
    }
    console.error('[offices POST]', err);
    res.status(500).json({ error: 'Failed to create office' });
  }
});

// PUT /api/offices/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) {
      updates.push(`name = $${i++}`);
      values.push(String(name).trim());
    }
    if (description !== undefined) {
      updates.push(`description = $${i++}`);
      values.push(description?.trim() || null);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${i++}`);
      values.push(!!is_active);
    }

    if (!updates.length) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    values.push(id);
    const result = await pool.query(
      `UPDATE offices SET ${updates.join(', ')} WHERE id = $${i} RETURNING id, office_number, name, description, is_active`,
      values
    );
    if (!result.rowCount) {
      return res.status(404).json({ error: 'Office not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'An office with this name already exists.' });
    }
    console.error('[offices PUT]', err);
    res.status(500).json({ error: 'Failed to update office' });
  }
});

module.exports = router;
