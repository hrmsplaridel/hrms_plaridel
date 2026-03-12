const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/holidays - list (?year=YYYY optional, ?is_active=true)
router.get('/', protect, async (req, res) => {
  try {
    const year = req.query.year;
    const isActive = req.query.is_active;
    let query = 'SELECT id, holiday_date, name, holiday_type, description, is_active, created_at FROM holidays';
    const params = [];
    const conditions = [];
    if (year) { conditions.push(`EXTRACT(YEAR FROM holiday_date) = $${params.length + 1}`); params.push(year); }
    if (isActive === 'true' || isActive === true) { conditions.push(`(is_active IS NULL OR is_active = true)`); }
    else if (isActive === 'false' || isActive === false) { conditions.push(`is_active = false`); }
    if (conditions.length) query += ' WHERE ' + conditions.join(' AND ');
    query += ' ORDER BY holiday_date';

    const result = await pool.query(query, params);
    res.json(result.rows.map((r) => ({
      id: r.id,
      holiday_date: r.holiday_date,
      name: r.name,
      holiday_type: r.holiday_type || 'regular',
      description: r.description,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('[holidays GET]', err);
    res.status(500).json({ error: 'Failed to fetch holidays' });
  }
});

// POST /api/holidays - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { holiday_date, name, holiday_type = 'regular', description, is_active = true } = req.body;
    if (!holiday_date || !name || !name.trim()) {
      return res.status(400).json({ error: 'Holiday date and name are required' });
    }
    const type = ['regular', 'special', 'local'].includes(holiday_type) ? holiday_type : 'regular';

    const result = await pool.query(
      `INSERT INTO holidays (holiday_date, name, holiday_type, description, is_active)
       VALUES ($1::date, $2, $3, $4, $5)
       RETURNING id, holiday_date, name, holiday_type, description, is_active, created_at`,
      [holiday_date, name.trim(), type, description?.trim() || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A holiday with this date and name already exists.' });
    console.error('[holidays POST]', err);
    res.status(500).json({ error: 'Failed to create holiday' });
  }
});

// PUT /api/holidays/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { holiday_date, name, holiday_type, description, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;
    if (holiday_date !== undefined) { updates.push(`holiday_date = $${i++}::date`); values.push(holiday_date); }
    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (holiday_type !== undefined) {
      const type = ['regular', 'special', 'local'].includes(holiday_type) ? holiday_type : 'regular';
      updates.push(`holiday_type = $${i++}`);
      values.push(type);
    }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    values.push(id);

    const result = await pool.query(
      `UPDATE holidays SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, holiday_date, name, holiday_type, description, is_active, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Holiday not found' });
    res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A holiday with this date and name already exists.' });
    console.error('[holidays PUT]', err);
    res.status(500).json({ error: 'Failed to update holiday' });
  }
});

// DELETE /api/holidays/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM holidays WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Holiday not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[holidays DELETE]', err);
    res.status(500).json({ error: 'Failed to delete holiday' });
  }
});

module.exports = router;
