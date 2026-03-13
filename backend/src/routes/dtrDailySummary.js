const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

/** Get active holiday for a date, if any. Exact date match first, then recurring (same month/day). Returns { id, name, holiday_type } or null. */
async function getHolidayByDate(dateStr) {
  const exact = await pool.query(
    `SELECT id, name, holiday_type FROM holidays WHERE holiday_date = $1::date AND (is_active IS NULL OR is_active = true) LIMIT 1`,
    [dateStr]
  );
  if (exact.rows[0]) return exact.rows[0];
  const recurring = await pool.query(
    `SELECT id, name, holiday_type FROM holidays
     WHERE recurring = true AND (is_active IS NULL OR is_active = true)
       AND EXTRACT(MONTH FROM holiday_date) = EXTRACT(MONTH FROM $1::date)
       AND EXTRACT(DAY FROM holiday_date) = EXTRACT(DAY FROM $1::date)
     LIMIT 1`,
    [dateStr]
  );
  return recurring.rows[0] || null;
}

// GET /api/dtr-daily-summary - list for admin (filters: start_date, end_date, employee_id, limit)
router.get('/', protect, async (req, res) => {
  try {
    const { start_date, end_date, employee_id, limit = 500 } = req.query;
    const params = [];
    const conditions = [];
    let i = 1;
    if (start_date) {
      conditions.push(`d.attendance_date >= $${i++}`);
      params.push(start_date);
    }
    if (end_date) {
      conditions.push(`d.attendance_date <= $${i++}`);
      params.push(end_date);
    }
    if (employee_id) {
      conditions.push(`d.employee_id = $${i++}`);
      params.push(employee_id);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const limitNum = Math.min(parseInt(limit, 10) || 500, 1000);
    params.push(limitNum);

    const result = await pool.query(
      `SELECT d.id, d.employee_id, d.attendance_date, d.time_in, d.time_out, d.total_hours, d.status, d.remarks, d.holiday_id, d.created_at, d.updated_at,
              u.full_name AS employee_name,
              h.name AS holiday_name, h.holiday_type AS holiday_type
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       ${where}
       ORDER BY d.attendance_date DESC, d.time_in DESC NULLS LAST
       LIMIT $${i}`,
      params
    );

    res.json(result.rows.map((r) => ({
      id: r.id,
      user_id: r.employee_id,
      record_date: r.attendance_date,
      time_in: r.time_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      status: r.status,
      remarks: r.remarks,
      holiday_id: r.holiday_id,
      holiday_name: r.holiday_name,
      holiday_type: r.holiday_type,
      created_at: r.created_at,
      updated_at: r.updated_at,
      employee_name: r.employee_name,
    })));
  } catch (err) {
    console.error('[dtr-daily-summary GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR summary' });
  }
});

// GET /api/dtr-daily-summary/summary - counts for dashboard (present today, late today)
router.get('/summary', protect, async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const present = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL`,
      [today]
    );
    const late = await pool.query(
      `SELECT COUNT(*) AS c FROM dtr_daily_summary WHERE attendance_date = $1::date AND time_in IS NOT NULL AND status = 'late'`,
      [today]
    );
    res.json({
      present_today: parseInt(present.rows[0]?.c ?? 0, 10),
      late_today: parseInt(late.rows[0]?.c ?? 0, 10),
    });
  } catch (err) {
    console.error('[dtr-daily-summary/summary GET]', err);
    res.status(500).json({ error: 'Failed to fetch DTR summary counts' });
  }
});

// GET /api/dtr-daily-summary/today - get today's record for current user (for clock in/out UI)
router.get('/today', protect, async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const today = new Date().toISOString().slice(0, 10);
    const result = await pool.query(
      `SELECT d.id, d.employee_id, d.attendance_date, d.time_in, d.time_out, d.total_hours, d.status, d.remarks, d.holiday_id, d.created_at, d.updated_at,
              u.full_name AS employee_name,
              h.name AS holiday_name, h.holiday_type AS holiday_type
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.employee_id = $1 AND d.attendance_date = $2::date`,
      [userId, today]
    );
    const r = result.rows[0];
    if (!r) return res.json(null);
    res.json({
      id: r.id,
      user_id: r.employee_id,
      record_date: r.attendance_date,
      time_in: r.time_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      status: r.status,
      remarks: r.remarks,
      holiday_id: r.holiday_id,
      holiday_name: r.holiday_name,
      holiday_type: r.holiday_type,
      created_at: r.created_at,
      updated_at: r.updated_at,
      employee_name: r.employee_name,
    });
  } catch (err) {
    console.error('[dtr-daily-summary/today GET]', err);
    res.status(500).json({ error: 'Failed to fetch today record' });
  }
});

// POST /api/dtr-daily-summary - clock in or create manual record (employee or admin)
router.post('/', protect, async (req, res) => {
  try {
    const { employee_id, attendance_date, time_in, time_out, total_hours, reason } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr' || req.user?.role === 'supervisor';
    const targetId = isAdmin && employee_id ? employee_id : userId;
    if (!targetId) return res.status(401).json({ error: 'Not authenticated' });
    if (!isAdmin && targetId !== userId) return res.status(403).json({ error: 'Can only create your own record' });

    const date = attendance_date || new Date().toISOString().slice(0, 10);
    const timeIn = time_in || new Date().toISOString();
    const holiday = await getHolidayByDate(date);
    const status = holiday ? 'holiday' : 'present';
    const holidayId = holiday ? holiday.id : null;

    const result = await pool.query(
      `INSERT INTO dtr_daily_summary (employee_id, attendance_date, time_in, time_out, total_hours, status, source, holiday_id)
       VALUES ($1, $2::date, $3::timestamptz, $4::timestamptz, $5::numeric, $6, 'manual', $7)
       RETURNING id, employee_id, attendance_date, time_in, time_out, total_hours, status, created_at`,
      [targetId, date, timeIn, time_out || null, total_hours != null ? parseFloat(total_hours) : 0, status, holidayId]
    );
    const r = result.rows[0];
    res.status(201).json({
      id: r.id,
      user_id: r.employee_id,
      record_date: r.attendance_date,
      time_in: r.time_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      status: r.status,
      created_at: r.created_at,
    });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Record already exists for this employee and date' });
    console.error('[dtr-daily-summary POST]', err);
    res.status(500).json({ error: 'Failed to create DTR record' });
  }
});

// PUT /api/dtr-daily-summary/:id - update (clock out or admin edit)
router.put('/:id', protect, async (req, res) => {
  try {
    const { id } = req.params;
    const { time_in, time_out, total_hours, status, remarks } = req.body;
    const userId = req.user?.id;
    const isAdmin = req.user?.role === 'admin' || req.user?.role === 'hr' || req.user?.role === 'supervisor';

    const check = await pool.query('SELECT employee_id FROM dtr_daily_summary WHERE id = $1', [id]);
    if (check.rows.length === 0) return res.status(404).json({ error: 'Record not found' });
    if (!isAdmin && check.rows[0].employee_id !== userId) return res.status(403).json({ error: 'Not allowed to update this record' });

    const updates = [];
    const values = [];
    let i = 1;
    if (time_in !== undefined) { updates.push(`time_in = $${i++}`); values.push(time_in); }
    if (time_out !== undefined) { updates.push(`time_out = $${i++}`); values.push(time_out); }
    if (total_hours !== undefined) { updates.push(`total_hours = $${i++}::numeric`); values.push(parseFloat(total_hours)); }
    if (status !== undefined) { updates.push(`status = $${i++}`); values.push(status); }
    if (remarks !== undefined) { updates.push(`remarks = $${i++}`); values.push(remarks); }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const result = await pool.query(
      `UPDATE dtr_daily_summary SET ${updates.join(', ')} WHERE id = $${i} RETURNING id, employee_id, attendance_date, time_in, time_out, total_hours, status, updated_at`,
      values
    );
    const r = result.rows[0];
    res.json({
      id: r.id,
      user_id: r.employee_id,
      record_date: r.attendance_date,
      time_in: r.time_in,
      time_out: r.time_out,
      total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
      status: r.status,
      updated_at: r.updated_at,
    });
  } catch (err) {
    console.error('[dtr-daily-summary PUT]', err);
    res.status(500).json({ error: 'Failed to update DTR record' });
  }
});

// DELETE /api/dtr-daily-summary/:id - admin only
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM dtr_daily_summary WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Record not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[dtr-daily-summary DELETE]', err);
    res.status(500).json({ error: 'Failed to delete DTR record' });
  }
});

// POST /api/dtr-daily-summary/sync-holidays - admin only; set holiday_id and status='holiday' for existing rows whose attendance_date is a holiday (exact or recurring)
router.post('/sync-holidays', protect, requireAdmin, async (req, res) => {
  try {
    const { start_date, end_date } = req.body;
    const start = start_date || new Date().toISOString().slice(0, 10);
    const end = end_date || start;
    const exact = await pool.query(
      `UPDATE dtr_daily_summary d
       SET holiday_id = h.id, status = 'holiday', updated_at = now()
       FROM holidays h
       WHERE d.attendance_date = h.holiday_date
         AND (h.is_active IS NULL OR h.is_active = true)
         AND d.attendance_date >= $1::date AND d.attendance_date <= $2::date
       RETURNING d.id`,
      [start, end]
    );
    const recurring = await pool.query(
      `UPDATE dtr_daily_summary d
       SET holiday_id = h.id, status = 'holiday', updated_at = now()
       FROM holidays h
       WHERE h.recurring = true AND (h.is_active IS NULL OR h.is_active = true)
         AND EXTRACT(MONTH FROM d.attendance_date) = EXTRACT(MONTH FROM h.holiday_date)
         AND EXTRACT(DAY FROM d.attendance_date) = EXTRACT(DAY FROM h.holiday_date)
         AND d.attendance_date >= $1::date AND d.attendance_date <= $2::date
         AND d.holiday_id IS NULL
       RETURNING d.id`,
      [start, end]
    );
    res.json({ updated: exact.rowCount + recurring.rowCount });
  } catch (err) {
    console.error('[dtr-daily-summary sync-holidays POST]', err);
    res.status(500).json({ error: 'Failed to sync holidays to DTR summary' });
  }
});

module.exports = router;
