const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/attendance-policies - list (?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const result = await pool.query(
      `SELECT id, name, description, grace_period_minutes, max_late_per_month_minutes,
              late_deduction_rule, absent_deduction_rule, undertime_rule, is_default, is_active, created_at
       FROM attendance_policies ${where}
       ORDER BY is_default DESC, name`
    );
    res.json(result.rows.map((r) => ({
      id: r.id,
      name: r.name,
      description: r.description,
      grace_period_minutes: r.grace_period_minutes ?? 0,
      max_late_per_month_minutes: r.max_late_per_month_minutes,
      late_deduction_rule: r.late_deduction_rule,
      absent_deduction_rule: r.absent_deduction_rule,
      undertime_rule: r.undertime_rule,
      is_default: r.is_default ?? false,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    })));
  } catch (err) {
    console.error('[attendance-policies GET]', err);
    res.status(500).json({ error: 'Failed to fetch attendance policies' });
  }
});

// POST /api/attendance-policies - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const {
      name,
      description,
      grace_period_minutes = 0,
      max_late_per_month_minutes,
      late_deduction_rule,
      absent_deduction_rule,
      undertime_rule,
      is_default = false,
      is_active = true,
    } = req.body;
    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });

    const result = await pool.query(
      `INSERT INTO attendance_policies (name, description, grace_period_minutes, max_late_per_month_minutes,
        late_deduction_rule, absent_deduction_rule, undertime_rule, is_default, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, name, description, grace_period_minutes, max_late_per_month_minutes,
         late_deduction_rule, absent_deduction_rule, undertime_rule, is_default, is_active, created_at`,
      [
        name.trim(),
        description?.trim() || null,
        parseInt(grace_period_minutes, 10) || 0,
        max_late_per_month_minutes != null ? parseInt(max_late_per_month_minutes, 10) : null,
        late_deduction_rule?.trim() || null,
        absent_deduction_rule?.trim() || null,
        undertime_rule?.trim() || null,
        !!is_default,
        !!is_active,
      ]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[attendance-policies POST]', err);
    res.status(500).json({ error: 'Failed to create attendance policy' });
  }
});

// PUT /api/attendance-policies/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const {
      name,
      description,
      grace_period_minutes,
      max_late_per_month_minutes,
      late_deduction_rule,
      absent_deduction_rule,
      undertime_rule,
      is_default,
      is_active,
    } = req.body;

    const updates = [];
    const values = [];
    let i = 1;
    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (grace_period_minutes !== undefined) { updates.push(`grace_period_minutes = $${i++}`); values.push(parseInt(grace_period_minutes, 10) || 0); }
    if (max_late_per_month_minutes !== undefined) { updates.push(`max_late_per_month_minutes = $${i++}`); values.push(max_late_per_month_minutes == null ? null : parseInt(max_late_per_month_minutes, 10)); }
    if (late_deduction_rule !== undefined) { updates.push(`late_deduction_rule = $${i++}`); values.push(late_deduction_rule?.trim() || null); }
    if (absent_deduction_rule !== undefined) { updates.push(`absent_deduction_rule = $${i++}`); values.push(absent_deduction_rule?.trim() || null); }
    if (undertime_rule !== undefined) { updates.push(`undertime_rule = $${i++}`); values.push(undertime_rule?.trim() || null); }
    if (is_default !== undefined) { updates.push(`is_default = $${i++}`); values.push(!!is_default); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE attendance_policies SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, name, description, grace_period_minutes, max_late_per_month_minutes,
         late_deduction_rule, absent_deduction_rule, undertime_rule, is_default, is_active, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Attendance policy not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('[attendance-policies PUT]', err);
    res.status(500).json({ error: 'Failed to update attendance policy' });
  }
});

// DELETE /api/attendance-policies/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM attendance_policies WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Attendance policy not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[attendance-policies DELETE]', err);
    res.status(500).json({ error: 'Failed to delete attendance policy' });
  }
});

module.exports = router;
