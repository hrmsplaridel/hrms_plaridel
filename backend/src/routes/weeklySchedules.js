const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  defaultWorkingDay,
  isIsoDate,
  normalizedWorkingDays,
  weekDates,
} = require('../services/employeeScheduleOverrides');

const router = express.Router();
const protect = [authMiddleware];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function cleanUuid(value) {
  const raw = String(value || '').trim();
  return raw && UUID_PATTERN.test(raw) ? raw : null;
}

// GET /api/weekly-schedules?week_start=YYYY-MM-DD&department_id=<uuid>&q=<text>
router.get('/', protect, requireAdmin, async (req, res) => {
  try {
    const weekStart = String(req.query.week_start || '').trim();
    const dates = weekDates(weekStart);
    if (!dates) {
      return res.status(400).json({ error: 'week_start must be a Monday in YYYY-MM-DD format' });
    }
    const departmentRaw = String(req.query.department_id || '').trim();
    const departmentId = departmentRaw ? cleanUuid(departmentRaw) : null;
    if (departmentRaw && !departmentId) {
      return res.status(400).json({ error: 'department_id must be a valid UUID' });
    }
    const search = String(req.query.q || '').trim().slice(0, 120);
    const result = await pool.query(
      `WITH dates AS (
         SELECT gs::date AS schedule_date
         FROM generate_series($1::date, ($1::date + 6), '1 day') gs
       )
       SELECT u.id AS employee_id,
              u.employee_number,
              u.full_name,
              dates.schedule_date::text AS schedule_date,
              a.department_id,
              d.name AS department_name,
              a.shift_id,
              s.name AS shift_name,
              s.start_time::text AS start_time,
              s.end_time::text AS end_time,
              COALESCE(s.working_days, ARRAY[1,2,3,4,5]::int[]) AS working_days,
              eso.is_working_day AS override_is_working_day
       FROM users u
       CROSS JOIN dates
       JOIN LATERAL (
         SELECT current_assignment.*
         FROM assignments current_assignment
         WHERE current_assignment.employee_id = u.id
           AND current_assignment.is_active = true
           AND current_assignment.effective_from <= dates.schedule_date
           AND (current_assignment.effective_to IS NULL OR current_assignment.effective_to >= dates.schedule_date)
         ORDER BY current_assignment.effective_from DESC,
                  current_assignment.created_at DESC,
                  current_assignment.id DESC
         LIMIT 1
       ) a ON TRUE
       LEFT JOIN departments d ON d.id = a.department_id
       LEFT JOIN shifts s ON s.id = a.shift_id
       LEFT JOIN employee_schedule_overrides eso
         ON eso.employee_id = u.id
        AND eso.schedule_date = dates.schedule_date
       WHERE u.is_active = true
         AND ($2::uuid IS NULL OR a.department_id = $2::uuid)
         AND ($3::text = '' OR u.full_name ILIKE '%' || $3 || '%'
              OR COALESCE(u.employee_number::text, '') ILIKE '%' || $3 || '%')
       ORDER BY u.full_name, dates.schedule_date`,
      [weekStart, departmentId, search]
    );

    const employees = new Map();
    for (const row of result.rows) {
      const employeeId = String(row.employee_id);
      let employee = employees.get(employeeId);
      if (!employee) {
        employee = {
          employee_id: employeeId,
          employee_number: row.employee_number,
          employee_name: row.full_name,
          department_id: row.department_id,
          department_name: row.department_name,
          days: [],
        };
        employees.set(employeeId, employee);
      }
      const workingDays = normalizedWorkingDays(row.working_days);
      const defaultIsWorking = defaultWorkingDay(workingDays, row.schedule_date);
      const override = typeof row.override_is_working_day === 'boolean'
        ? row.override_is_working_day
        : null;
      employee.days.push({
        date: row.schedule_date,
        shift_id: row.shift_id,
        shift_name: row.shift_name,
        start_time: row.start_time,
        end_time: row.end_time,
        default_is_working_day: defaultIsWorking,
        override_is_working_day: override,
        is_working_day: override ?? defaultIsWorking,
      });
    }
    return res.json({
      week_start: weekStart,
      week_end: dates[6],
      employees: [...employees.values()],
    });
  } catch (error) {
    console.error('[weekly-schedules GET]', error);
    return res.status(500).json({ error: 'Failed to load the weekly schedule' });
  }
});

// PUT /api/weekly-schedules/:employeeId/:weekStart
router.put('/:employeeId/:weekStart', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const employeeId = cleanUuid(req.params.employeeId);
    const weekStart = String(req.params.weekStart || '').trim();
    const dates = weekDates(weekStart);
    if (!employeeId) return res.status(400).json({ error: 'A valid employee ID is required' });
    if (!dates) {
      return res.status(400).json({ error: 'weekStart must be a Monday in YYYY-MM-DD format' });
    }
    if (!Array.isArray(req.body?.days)) {
      return res.status(400).json({ error: 'days must be an array' });
    }
    const values = new Map();
    for (const item of req.body.days) {
      const date = String(item?.date || '').trim();
      if (!dates.includes(date) || (item?.is_working_day !== null && typeof item?.is_working_day !== 'boolean')) {
        return res.status(400).json({ error: 'Each day must belong to the selected week and use true, false, or null' });
      }
      values.set(date, item.is_working_day);
    }

    client = await pool.connect();
    await client.query('BEGIN');
    const employee = await client.query(
      'SELECT id, full_name FROM users WHERE id = $1::uuid AND is_active = true FOR UPDATE',
      [employeeId]
    );
    if (employee.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Active employee not found' });
    }

    const changed = [];
    for (const date of dates) {
      if (!values.has(date)) continue;
      const requested = values.get(date);
      const assignment = await client.query(
        `SELECT COALESCE(s.working_days, ARRAY[1,2,3,4,5]::int[]) AS working_days
         FROM assignments a
         LEFT JOIN shifts s ON s.id = a.shift_id
         WHERE a.employee_id = $1::uuid
           AND a.is_active = true
           AND a.effective_from <= $2::date
           AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
         ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
         LIMIT 1`,
        [employeeId, date]
      );
      if (assignment.rowCount === 0) {
        throw Object.assign(new Error(`No active assignment exists for ${date}`), { statusCode: 409 });
      }
      const defaultValue = defaultWorkingDay(assignment.rows[0].working_days, date);
      if (requested === null || requested === defaultValue) {
        await client.query(
          'DELETE FROM employee_schedule_overrides WHERE employee_id = $1::uuid AND schedule_date = $2::date',
          [employeeId, date]
        );
      } else {
        await client.query(
          `INSERT INTO employee_schedule_overrides
             (employee_id, schedule_date, is_working_day, created_by)
           VALUES ($1::uuid, $2::date, $3, $4::uuid)
           ON CONFLICT (employee_id, schedule_date)
           DO UPDATE SET is_working_day = EXCLUDED.is_working_day,
                         created_by = EXCLUDED.created_by,
                         updated_at = now()`,
          [employeeId, date, requested, req.user?.id || null]
        );
      }
      changed.push({ date, is_working_day: requested, default_is_working_day: defaultValue });
    }
    await client.query(
      `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
       VALUES ($1::uuid, 'weekly_schedule_updated', 'employee', $2::uuid, $3)`,
      [req.user?.id || null, employeeId, JSON.stringify({ week_start: weekStart, days: changed })]
    );
    await client.query('COMMIT');
    return res.json({ ok: true, employee_id: employeeId, week_start: weekStart });
  } catch (error) {
    if (client) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    console.error('[weekly-schedules PUT]', error);
    return res.status(error.statusCode || 500).json({
      error: error.statusCode ? error.message : 'Failed to save the weekly schedule',
    });
  } finally {
    client?.release();
  }
});

module.exports = router;
