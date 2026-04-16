const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

function parseTime(val) {
  if (!val) return null;
  const s = String(val);
  if (s.match(/^\d{1,2}:\d{2}(:\d{2})?$/)) return s.length <= 5 ? s + ':00' : s.substring(0, 8);
  return null;
}

/** Parse working_days from body: array of 1-7 (Mon-Sun) or null for default Mon-Fri. */
function parseWorkingDays(val) {
  if (val == null || !Array.isArray(val)) return null;
  const arr = val
    .map((v) => parseInt(v, 10))
    .filter((n) => n >= 1 && n <= 7);
  const uniq = [...new Set(arr)].sort((a, b) => a - b);
  return uniq.length > 0 ? uniq : null;
}

// GET /api/shifts - list all (?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const result = await pool.query(
      `SELECT id, shift_number, name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active
       FROM shifts ${where}
       ORDER BY name`
    );
    res.json(result.rows.map((r) => ({
      id: r.id,
      shift_number: r.shift_number,
      name: r.name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_end: r.break_end,
      grace_period_minutes: r.grace_period_minutes ?? 0,
      working_days: r.working_days && Array.isArray(r.working_days)
        ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
        : [1, 2, 3, 4, 5],
      is_active: r.is_active ?? true,
    })));
  } catch (err) {
    console.error('[shifts GET]', err);
    res.status(500).json({ error: 'Failed to fetch shifts' });
  }
});

// POST /api/shifts - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active = true } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    const st = parseTime(start_time) || '09:00:00';
    const et = parseTime(end_time) || '17:00:00';
    const be = break_end != null && break_end !== '' ? parseTime(break_end) : null;
    const grace = grace_period_minutes != null ? Math.max(0, parseInt(grace_period_minutes, 10) || 0) : 0;
    const wd = parseWorkingDays(working_days) || [1, 2, 3, 4, 5];

    const result = await pool.query(
      `INSERT INTO shifts (name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active)
       VALUES ($1, $2::time, $3::time, $4::time, $5, $6::int[], $7)
       RETURNING id, shift_number, name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active`,
      [name.trim(), st, et, be, grace, wd, !!is_active]
    );
    const r = result.rows[0];
    res.status(201).json({
      id: r.id,
      shift_number: r.shift_number,
      name: r.name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_end: r.break_end,
      grace_period_minutes: r.grace_period_minutes ?? 0,
      working_days: r.working_days && Array.isArray(r.working_days)
        ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
        : [1, 2, 3, 4, 5],
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    console.error('[shifts POST]', err);
    res.status(500).json({ error: 'Failed to create shift' });
  }
});

// PUT /api/shifts/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (start_time !== undefined) { updates.push(`start_time = $${i++}::time`); values.push(parseTime(start_time) || '09:00:00'); }
    if (end_time !== undefined) { updates.push(`end_time = $${i++}::time`); values.push(parseTime(end_time) || '17:00:00'); }
    if (break_end !== undefined) { updates.push(`break_end = $${i++}::time`); values.push(break_end != null && break_end !== '' ? parseTime(break_end) : null); }
    if (grace_period_minutes !== undefined) { updates.push(`grace_period_minutes = $${i++}`); values.push(Math.max(0, parseInt(grace_period_minutes, 10) || 0)); }
    if (working_days !== undefined) {
      const wd = parseWorkingDays(working_days) || [1, 2, 3, 4, 5];
      updates.push(`working_days = $${i++}::int[]`);
      values.push(wd);
    }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE shifts SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, shift_number, name, start_time, end_time, break_end, grace_period_minutes, working_days, is_active`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Shift not found' });
    const r = result.rows[0];
    res.json({
      id: r.id,
      shift_number: r.shift_number,
      name: r.name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_end: r.break_end,
      grace_period_minutes: r.grace_period_minutes ?? 0,
      working_days: r.working_days && Array.isArray(r.working_days)
        ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
        : [1, 2, 3, 4, 5],
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    console.error('[shifts PUT]', err);
    res.status(500).json({ error: 'Failed to update shift' });
  }
});

// DELETE /api/shifts/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM shifts WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Shift not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[shifts DELETE]', err);
    res.status(500).json({ error: 'Failed to delete shift' });
  }
});

module.exports = router;
