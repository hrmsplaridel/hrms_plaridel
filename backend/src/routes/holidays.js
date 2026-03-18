const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

/** Return date as YYYY-MM-DD to avoid timezone shift when pg returns Date (serializes to ISO UTC). */
function toDateString(v) {
  if (v == null) return null;
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.split('T')[0];
  if (v instanceof Date) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, '0');
    const d = String(v.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(v).split('T')[0];
}

// GET /api/holidays - list (?year=YYYY optional, ?is_active=true). Tolerates missing coverage column (pre-migration).
router.get('/', protect, async (req, res) => {
  try {
    const year = req.query.year;
    const isActive = req.query.is_active;
    const params = [];
    const conditions = [];
    if (year) {
      conditions.push(`(EXTRACT(YEAR FROM holiday_date) = $${params.length + 1} OR recurring = true)`);
      params.push(year);
    }
    if (isActive === 'true' || isActive === true) { conditions.push(`(is_active IS NULL OR is_active = true)`); }
    else if (isActive === 'false' || isActive === false) { conditions.push(`is_active = false`); }
    const where = conditions.length ? ' WHERE ' + conditions.join(' AND ') : '';
    const order = ' ORDER BY EXTRACT(MONTH FROM holiday_date), EXTRACT(DAY FROM holiday_date)';

    let result;
    try {
      result = await pool.query(
        `SELECT id, holiday_date, name, holiday_type, description, is_active, recurring, coverage, created_at FROM holidays${where}${order}`,
        params
      );
    } catch (err) {
      if (err.message && /coverage|column.*does not exist/i.test(err.message)) {
        result = await pool.query(
          `SELECT id, holiday_date, name, holiday_type, description, is_active, recurring, created_at FROM holidays${where}${order}`,
          params
        );
        for (const r of result.rows) r.coverage = 'whole_day';
      } else throw err;
    }
    res.json(result.rows.map((r) => ({
      id: r.id,
      holiday_date: toDateString(r.holiday_date),
      name: r.name,
      holiday_type: r.holiday_type || 'regular',
      description: r.description,
      is_active: r.is_active ?? true,
      recurring: r.recurring ?? false,
      coverage: r.coverage || 'whole_day',
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
    const { holiday_date, name, holiday_type = 'regular', description, is_active = true, recurring = false, coverage: bodyCoverage } = req.body;
    if (!holiday_date || !name || !name.trim()) {
      return res.status(400).json({ error: 'Holiday date and name are required' });
    }
    const type = ['regular', 'special', 'local', 'work_suspension'].includes(holiday_type) ? holiday_type : 'regular';
    const coverageAllowed = ['whole_day', 'am_only', 'pm_only'];
    let coverage = coverageAllowed.includes(bodyCoverage) ? bodyCoverage : 'whole_day';
    if (type !== 'work_suspension') coverage = 'whole_day';

    const result = await pool.query(
      `INSERT INTO holidays (holiday_date, name, holiday_type, description, is_active, recurring, coverage)
       VALUES ($1::date, $2, $3, $4, $5, $6, $7)
       RETURNING id, holiday_date, name, holiday_type, description, is_active, recurring, coverage, created_at`,
      [holiday_date, name.trim(), type, description?.trim() || null, !!is_active, !!recurring, coverage]
    );
    const row = result.rows[0];
    res.status(201).json({ ...row, holiday_date: toDateString(row.holiday_date), coverage: row.coverage || 'whole_day' });
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
    const { holiday_date, name, holiday_type, description, is_active, recurring, coverage: bodyCoverage } = req.body;

    const updates = [];
    const values = [];
    let i = 1;
    if (holiday_date !== undefined) { updates.push(`holiday_date = $${i++}::date`); values.push(holiday_date); }
    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (holiday_type !== undefined) {
      const type = ['regular', 'special', 'local', 'work_suspension'].includes(holiday_type) ? holiday_type : 'regular';
      updates.push(`holiday_type = $${i++}`);
      values.push(type);
    }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }
    if (recurring !== undefined) { updates.push(`recurring = $${i++}`); values.push(!!recurring); }
    if (bodyCoverage !== undefined) {
      const coverageAllowed = ['whole_day', 'am_only', 'pm_only'];
      const coverage = coverageAllowed.includes(bodyCoverage) ? bodyCoverage : 'whole_day';
      updates.push(`coverage = $${i++}`); values.push(coverage);
    }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    values.push(id);

    const result = await pool.query(
      `UPDATE holidays SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, holiday_date, name, holiday_type, description, is_active, recurring, coverage, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Holiday not found' });
    const row = result.rows[0];
    res.json({ ...row, holiday_date: toDateString(row.holiday_date), coverage: row.coverage || 'whole_day' });
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
