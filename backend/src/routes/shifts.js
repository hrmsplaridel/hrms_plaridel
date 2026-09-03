const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  ensureShiftPunchModeColumn,
  normalizePunchMode,
} = require('../services/shiftAttendance');
const {
  ShiftLifecycleError,
  deleteUnusedShift,
  ensureShiftDeactivationAllowed,
  ensureShiftScheduleChangeAllowed,
  ensureSupportedShiftRange,
  lockShiftForUpdate,
  parseShiftTimeInput,
  shiftDeactivationBlockers,
  shiftDeactivationCountsFromRow,
  shiftDeactivationCountsSql,
  shiftDependencyBlockers,
  shiftDependencyCountsFromRow,
  shiftDependencyCountsSql,
} = require('../services/shiftLifecycle');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

const router = express.Router();
const protect = [authMiddleware];

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
    await ensureShiftPunchModeColumn(pool);
    const today = todayInHrmsTimezone();
    const status = req.query.status || 'Active';
    let where = '';
    if (status === 'Active') where = 'WHERE (is_active IS NULL OR is_active = true)';
    else if (status === 'Inactive') where = 'WHERE is_active = false';

    const result = await pool.query(
      `SELECT id, shift_number, name, start_time, end_time, break_end, punch_mode,
              grace_period_minutes, working_days, is_active,
              ${shiftDependencyCountsSql('shifts.id')},
              ${shiftDeactivationCountsSql('shifts.id', '$1')}
       FROM shifts ${where}
       ORDER BY name`,
      [today]
    );
    res.json(result.rows.map((r) => {
      const dependencyCounts = shiftDependencyCountsFromRow(r);
      const deleteBlockers = shiftDependencyBlockers(dependencyCounts);
      const deactivationCounts = shiftDeactivationCountsFromRow(r);
      const deactivationBlockers = shiftDeactivationBlockers(deactivationCounts);
      return {
        id: r.id,
        shift_number: r.shift_number,
        name: r.name,
        start_time: r.start_time,
        end_time: r.end_time,
        break_end: r.break_end,
        punch_mode: normalizePunchMode(r.punch_mode),
        grace_period_minutes: r.grace_period_minutes ?? 0,
        working_days: r.working_days && Array.isArray(r.working_days)
          ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
          : [1, 2, 3, 4, 5],
        is_active: r.is_active ?? true,
        assignment_history_count: dependencyCounts.assignments,
        schedule_edit_locked: deleteBlockers.length > 0,
        can_deactivate: deactivationBlockers.length === 0,
        deactivation_blockers: deactivationBlockers,
        deactivation_official_date: today,
        can_permanently_delete: deleteBlockers.length === 0,
        delete_blockers: deleteBlockers,
      };
    }));
  } catch (err) {
    console.error('[shifts GET]', err);
    res.status(500).json({ error: 'Failed to fetch shifts' });
  }
});

// POST /api/shifts - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    await ensureShiftPunchModeColumn(pool);
    const { name, start_time, end_time, break_end, punch_mode, grace_period_minutes, working_days, is_active = true } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    const st = parseShiftTimeInput(start_time, {
      field: 'start_time',
      label: 'Start Time',
    });
    const et = parseShiftTimeInput(end_time, {
      field: 'end_time',
      label: 'End Time',
    });
    ensureSupportedShiftRange(st, et);
    const be = parseShiftTimeInput(break_end, {
      field: 'break_end',
      label: 'PM Start',
      required: false,
    });
    const mode = normalizePunchMode(punch_mode);
    const grace = grace_period_minutes != null ? Math.max(0, parseInt(grace_period_minutes, 10) || 0) : 0;
    const wd = parseWorkingDays(working_days) || [1, 2, 3, 4, 5];

    const result = await pool.query(
      `INSERT INTO shifts (name, start_time, end_time, break_end, punch_mode, grace_period_minutes, working_days, is_active)
       VALUES ($1, $2::time, $3::time, $4::time, $5, $6, $7::int[], $8)
       RETURNING id, shift_number, name, start_time, end_time, break_end, punch_mode, grace_period_minutes, working_days, is_active`,
      [name.trim(), st, et, be, mode, grace, wd, !!is_active]
    );
    const r = result.rows[0];
    res.status(201).json({
      id: r.id,
      shift_number: r.shift_number,
      name: r.name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_end: r.break_end,
      punch_mode: normalizePunchMode(r.punch_mode),
      grace_period_minutes: r.grace_period_minutes ?? 0,
      working_days: r.working_days && Array.isArray(r.working_days)
        ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
        : [1, 2, 3, 4, 5],
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    if (err instanceof ShiftLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    console.error('[shifts POST]', err);
    res.status(500).json({ error: 'Failed to create shift' });
  }
});

// PUT /api/shifts/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    await ensureShiftPunchModeColumn(pool);
    const { id } = req.params;
    const { name, start_time, end_time, break_end, punch_mode, grace_period_minutes, working_days, is_active } = req.body;
    const parsedStartTime = start_time === undefined
      ? undefined
      : parseShiftTimeInput(start_time, {
        field: 'start_time',
        label: 'Start Time',
      });
    const parsedEndTime = end_time === undefined
      ? undefined
      : parseShiftTimeInput(end_time, {
        field: 'end_time',
        label: 'End Time',
      });
    const parsedBreakEnd = break_end === undefined
      ? undefined
      : parseShiftTimeInput(break_end, {
        field: 'break_end',
        label: 'PM Start',
        required: false,
      });

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (parsedStartTime !== undefined) { updates.push(`start_time = $${i++}::time`); values.push(parsedStartTime); }
    if (parsedEndTime !== undefined) { updates.push(`end_time = $${i++}::time`); values.push(parsedEndTime); }
    if (parsedBreakEnd !== undefined) { updates.push(`break_end = $${i++}::time`); values.push(parsedBreakEnd); }
    if (punch_mode !== undefined) { updates.push(`punch_mode = $${i++}`); values.push(normalizePunchMode(punch_mode)); }
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

    client = await pool.connect();
    await client.query('BEGIN');
    const lockedShift = await lockShiftForUpdate(client, id);
    if (!lockedShift) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Shift not found' });
    }
    if (start_time !== undefined || end_time !== undefined) {
      ensureSupportedShiftRange(
        start_time !== undefined
          ? parsedStartTime
          : lockedShift.start_time,
        end_time !== undefined
          ? parsedEndTime
          : lockedShift.end_time
      );
    }
    const scheduleChanges = {};
    if (parsedStartTime !== undefined) scheduleChanges.start_time = parsedStartTime;
    if (parsedEndTime !== undefined) scheduleChanges.end_time = parsedEndTime;
    if (break_end !== undefined) {
      scheduleChanges.break_end = parsedBreakEnd;
    }
    if (punch_mode !== undefined) scheduleChanges.punch_mode = normalizePunchMode(punch_mode);
    if (grace_period_minutes !== undefined) {
      scheduleChanges.grace_period_minutes = Math.max(0, parseInt(grace_period_minutes, 10) || 0);
    }
    if (working_days !== undefined) {
      scheduleChanges.working_days = parseWorkingDays(working_days) || [1, 2, 3, 4, 5];
    }
    await ensureShiftScheduleChangeAllowed(client, {
      shiftId: id,
      changes: scheduleChanges,
      lockedShift,
    });
    const nextIsActive = is_active === undefined
      ? lockedShift.is_active !== false
      : !!is_active;
    if (lockedShift.is_active !== false && nextIsActive === false) {
      await ensureShiftDeactivationAllowed(client, {
        shiftId: id,
        effectiveDate: todayInHrmsTimezone(),
        lockedShift,
      });
    }

    const result = await client.query(
      `UPDATE shifts SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, shift_number, name, start_time, end_time, break_end, punch_mode, grace_period_minutes, working_days, is_active`,
      values
    );
    await client.query('COMMIT');
    const r = result.rows[0];
    res.json({
      id: r.id,
      shift_number: r.shift_number,
      name: r.name,
      start_time: r.start_time,
      end_time: r.end_time,
      break_end: r.break_end,
      punch_mode: normalizePunchMode(r.punch_mode),
      grace_period_minutes: r.grace_period_minutes ?? 0,
      working_days: r.working_days && Array.isArray(r.working_days)
        ? r.working_days.map((d) => (typeof d === 'number' ? d : parseInt(d, 10)))
        : [1, 2, 3, 4, 5],
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[shifts PUT rollback]', rollbackError);
      }
    }
    if (err instanceof ShiftLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    console.error('[shifts PUT]', err);
    res.status(500).json({ error: 'Failed to update shift' });
  } finally {
    client?.release();
  }
});

// DELETE /api/shifts/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const deletedShift = await deleteUnusedShift(client, {
      shiftId: req.params.id,
    });
    await client.query('COMMIT');
    res.json({
      message: 'Unused shift permanently deleted',
      shift: {
        id: deletedShift.id,
        shift_number: deletedShift.shift_number,
        name: deletedShift.name,
      },
    });
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[shifts DELETE rollback]', rollbackError);
      }
    }
    if (err instanceof ShiftLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    console.error('[shifts DELETE]', err);
    res.status(500).json({ error: 'Failed to delete shift' });
  } finally {
    client?.release();
  }
});

module.exports = router;
