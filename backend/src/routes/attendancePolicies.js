const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

function toBool(v, fallback = false) {
  if (v === undefined) return fallback;
  if (v === null) return false;
  if (typeof v === 'boolean') return v;
  const s = String(v).trim().toLowerCase();
  if (s === 'true' || s === '1' || s === 'yes') return true;
  if (s === 'false' || s === '0' || s === 'no') return false;
  return fallback;
}

function toIntOrNull(v) {
  if (v === undefined) return undefined;
  if (v === null || String(v).trim() === '') return null;
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : null;
}

function toIntOrDefault(v, def) {
  if (v === undefined) return undefined;
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : def;
}

function toNumberOrDefault(v, def) {
  if (v === undefined) return undefined;
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : def;
}

function validatePolicyPayload(p) {
  const workHoursPerDay = p.work_hours_per_day;
  if (workHoursPerDay != null && !(parseFloat(workHoursPerDay) > 0)) {
    return 'Work hours per day must be greater than 0.';
  }
  const maxLate = p.max_late_minutes_per_month;
  if (maxLate != null && !(parseInt(maxLate, 10) >= 0)) {
    return 'Max late minutes per month must be null or >= 0.';
  }
  const mult = p.deduction_multiplier;
  if (mult != null && !(parseFloat(mult) > 0)) {
    return 'Deduction multiplier must be greater than 0.';
  }
  return null;
}

// GET /api/attendance-policies - list (?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const result = await pool.query(
      `SELECT id, name, description,
              work_hours_per_day, use_equivalent_day_conversion,
              deduct_late, max_late_minutes_per_month, convert_late_to_equivalent_day,
              deduct_undertime, convert_undertime_to_equivalent_day,
              absent_equals_full_day_deduction,
              combine_late_and_undertime, deduction_multiplier,
              is_default, is_active, created_at
       FROM attendance_policies ${where}
       ORDER BY is_default DESC, name`
    );
    res.json(result.rows.map((r) => ({
      id: r.id,
      // New structured payload (preferred)
      policy_name: r.name,
      // Backward compat for older clients
      name: r.name,
      description: r.description,
      work_hours_per_day: r.work_hours_per_day != null ? parseFloat(r.work_hours_per_day) : 8,
      use_equivalent_day_conversion: r.use_equivalent_day_conversion ?? true,
      deduct_late: r.deduct_late ?? false,
      max_late_minutes_per_month: r.max_late_minutes_per_month,
      convert_late_to_equivalent_day: r.convert_late_to_equivalent_day ?? true,
      deduct_undertime: r.deduct_undertime ?? true,
      convert_undertime_to_equivalent_day: r.convert_undertime_to_equivalent_day ?? true,
      absent_equals_full_day_deduction: r.absent_equals_full_day_deduction ?? true,
      combine_late_and_undertime: r.combine_late_and_undertime ?? false,
      deduction_multiplier: r.deduction_multiplier != null ? parseFloat(r.deduction_multiplier) : 1.0,
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
    const body = req.body || {};
    const policyName = (body.policy_name ?? body.name ?? '').toString().trim();
    if (!policyName) return res.status(400).json({ error: 'Policy name is required' });

    const payload = {
      policy_name: policyName,
      description: body.description?.toString().trim() || null,
      is_default: toBool(body.is_default, false),
      is_active: toBool(body.is_active, true),
      work_hours_per_day: toNumberOrDefault(body.work_hours_per_day, 8),
      use_equivalent_day_conversion: toBool(body.use_equivalent_day_conversion, true),
      deduct_late: toBool(body.deduct_late, false),
      max_late_minutes_per_month: toIntOrNull(body.max_late_minutes_per_month),
      convert_late_to_equivalent_day: toBool(body.convert_late_to_equivalent_day, true),
      deduct_undertime: toBool(body.deduct_undertime, true),
      convert_undertime_to_equivalent_day: toBool(body.convert_undertime_to_equivalent_day, true),
      absent_equals_full_day_deduction: toBool(body.absent_equals_full_day_deduction, true),
      combine_late_and_undertime: toBool(body.combine_late_and_undertime, false),
      deduction_multiplier: toNumberOrDefault(body.deduction_multiplier, 1.0),
    };
    const errMsg = validatePolicyPayload(payload);
    if (errMsg) return res.status(400).json({ error: errMsg });

    const result = await pool.query(
      `INSERT INTO attendance_policies (name, description,
        work_hours_per_day, use_equivalent_day_conversion,
        deduct_late, max_late_minutes_per_month, convert_late_to_equivalent_day,
        deduct_undertime, convert_undertime_to_equivalent_day,
        absent_equals_full_day_deduction,
        combine_late_and_undertime, deduction_multiplier,
        is_default, is_active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
       RETURNING id, name, description,
        work_hours_per_day, use_equivalent_day_conversion,
        deduct_late, max_late_minutes_per_month, convert_late_to_equivalent_day,
        deduct_undertime, convert_undertime_to_equivalent_day,
        absent_equals_full_day_deduction,
        combine_late_and_undertime, deduction_multiplier,
        is_default, is_active, created_at`,
      [
        payload.policy_name,
        payload.description,
        payload.work_hours_per_day,
        payload.use_equivalent_day_conversion,
        payload.deduct_late,
        payload.max_late_minutes_per_month,
        payload.convert_late_to_equivalent_day,
        payload.deduct_undertime,
        payload.convert_undertime_to_equivalent_day,
        payload.absent_equals_full_day_deduction,
        payload.combine_late_and_undertime,
        payload.deduction_multiplier,
        payload.is_default,
        payload.is_active,
      ]
    );
    const r = result.rows[0];
    res.status(201).json({
      id: r.id,
      policy_name: r.name,
      name: r.name,
      description: r.description,
      work_hours_per_day: r.work_hours_per_day != null ? parseFloat(r.work_hours_per_day) : 8,
      use_equivalent_day_conversion: r.use_equivalent_day_conversion ?? true,
      deduct_late: r.deduct_late ?? false,
      max_late_minutes_per_month: r.max_late_minutes_per_month,
      convert_late_to_equivalent_day: r.convert_late_to_equivalent_day ?? true,
      deduct_undertime: r.deduct_undertime ?? true,
      convert_undertime_to_equivalent_day: r.convert_undertime_to_equivalent_day ?? true,
      absent_equals_full_day_deduction: r.absent_equals_full_day_deduction ?? true,
      combine_late_and_undertime: r.combine_late_and_undertime ?? false,
      deduction_multiplier: r.deduction_multiplier != null ? parseFloat(r.deduction_multiplier) : 1.0,
      is_default: r.is_default ?? false,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    });
  } catch (err) {
    console.error('[attendance-policies POST]', err);
    res.status(500).json({ error: 'Failed to create attendance policy' });
  }
});

// PUT /api/attendance-policies/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const body = req.body || {};

    const updates = [];
    const values = [];
    let i = 1;
    if (body.policy_name !== undefined || body.name !== undefined) {
      const policyName = (body.policy_name ?? body.name ?? '').toString().trim();
      if (!policyName) return res.status(400).json({ error: 'Policy name is required' });
      updates.push(`name = $${i++}`); values.push(policyName);
    }
    if (body.description !== undefined) { updates.push(`description = $${i++}`); values.push(body.description?.toString().trim() || null); }

    if (body.work_hours_per_day !== undefined) { updates.push(`work_hours_per_day = $${i++}`); values.push(toNumberOrDefault(body.work_hours_per_day, 8)); }
    if (body.use_equivalent_day_conversion !== undefined) { updates.push(`use_equivalent_day_conversion = $${i++}`); values.push(toBool(body.use_equivalent_day_conversion, true)); }

    if (body.deduct_late !== undefined) { updates.push(`deduct_late = $${i++}`); values.push(toBool(body.deduct_late, false)); }
    if (body.max_late_minutes_per_month !== undefined) { updates.push(`max_late_minutes_per_month = $${i++}`); values.push(toIntOrNull(body.max_late_minutes_per_month)); }
    if (body.convert_late_to_equivalent_day !== undefined) { updates.push(`convert_late_to_equivalent_day = $${i++}`); values.push(toBool(body.convert_late_to_equivalent_day, true)); }

    if (body.deduct_undertime !== undefined) { updates.push(`deduct_undertime = $${i++}`); values.push(toBool(body.deduct_undertime, true)); }
    if (body.convert_undertime_to_equivalent_day !== undefined) { updates.push(`convert_undertime_to_equivalent_day = $${i++}`); values.push(toBool(body.convert_undertime_to_equivalent_day, true)); }

    if (body.absent_equals_full_day_deduction !== undefined) { updates.push(`absent_equals_full_day_deduction = $${i++}`); values.push(toBool(body.absent_equals_full_day_deduction, true)); }
    if (body.combine_late_and_undertime !== undefined) { updates.push(`combine_late_and_undertime = $${i++}`); values.push(toBool(body.combine_late_and_undertime, false)); }
    if (body.deduction_multiplier !== undefined) { updates.push(`deduction_multiplier = $${i++}`); values.push(toNumberOrDefault(body.deduction_multiplier, 1.0)); }

    if (body.is_default !== undefined) { updates.push(`is_default = $${i++}`); values.push(toBool(body.is_default, false)); }
    if (body.is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(toBool(body.is_active, true)); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });

    const validateErr = validatePolicyPayload({
      work_hours_per_day: body.work_hours_per_day,
      max_late_minutes_per_month: body.max_late_minutes_per_month,
      deduction_multiplier: body.deduction_multiplier,
    });
    if (validateErr) return res.status(400).json({ error: validateErr });

    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE attendance_policies SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, name, description,
        work_hours_per_day, use_equivalent_day_conversion,
        deduct_late, max_late_minutes_per_month, convert_late_to_equivalent_day,
        deduct_undertime, convert_undertime_to_equivalent_day,
        absent_equals_full_day_deduction,
        combine_late_and_undertime, deduction_multiplier,
        is_default, is_active, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Attendance policy not found' });
    const r = result.rows[0];
    res.json({
      id: r.id,
      policy_name: r.name,
      name: r.name,
      description: r.description,
      work_hours_per_day: r.work_hours_per_day != null ? parseFloat(r.work_hours_per_day) : 8,
      use_equivalent_day_conversion: r.use_equivalent_day_conversion ?? true,
      deduct_late: r.deduct_late ?? false,
      max_late_minutes_per_month: r.max_late_minutes_per_month,
      convert_late_to_equivalent_day: r.convert_late_to_equivalent_day ?? true,
      deduct_undertime: r.deduct_undertime ?? true,
      convert_undertime_to_equivalent_day: r.convert_undertime_to_equivalent_day ?? true,
      absent_equals_full_day_deduction: r.absent_equals_full_day_deduction ?? true,
      combine_late_and_undertime: r.combine_late_and_undertime ?? false,
      deduction_multiplier: r.deduction_multiplier != null ? parseFloat(r.deduction_multiplier) : 1.0,
      is_default: r.is_default ?? false,
      is_active: r.is_active ?? true,
      created_at: r.created_at,
    });
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
