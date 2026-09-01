const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  PositionLifecycleError,
  deleteMistakenPosition,
  ensureActivePositionDepartmentAllowed,
  ensurePositionDeactivationAllowed,
  ensurePositionDepartmentChangeAllowed,
  lockPositionForUpdate,
  positionDependencyBlockers,
  positionDependencyCountsFromRow,
  positionDependencyCountsSql,
  positionDeactivationBlockers,
  positionDeactivationCountsFromRow,
  positionDeactivationCountsSql,
  positionAuditAction,
  positionAuditSnapshot,
  writePositionAudit,
} = require('../services/positionLifecycle');
const {
  endDepartmentHeadPeriod,
  getManagedDepartmentHeadPeriod,
  saveDepartmentHeadPeriod,
} = require('../services/positionDepartmentHeadPeriods');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/positions - list all (?status=Active|Inactive|All, ?department_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const { status = 'Active', department_id } = req.query;
    const today = todayInHrmsTimezone();
    const params = [today];
    const conditions = [];
    let i = 2;

    if (status === 'Active') {
      conditions.push('(p.is_active IS NULL OR p.is_active = true)');
    } else if (status === 'Inactive') {
      conditions.push('p.is_active = false');
    }
    if (department_id) {
      conditions.push(`p.department_id = $${i++}`);
      params.push(department_id);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT p.id, p.position_number, p.name, p.description, p.department_id,
              (managed_period.id IS NOT NULL) AS is_department_head, p.is_active,
              managed_period.id AS department_head_period_id,
              managed_period.effective_from::text AS department_head_effective_from,
              managed_period.effective_to::text AS department_head_effective_to,
              COALESCE(period_history.periods, '[]'::jsonb) AS department_head_periods,
              d.name AS department_name,
              ${positionDependencyCountsSql('p')},
              ${positionDeactivationCountsSql('p.id', '$1')}
       FROM positions p
       LEFT JOIN departments d ON p.department_id = d.id
       LEFT JOIN LATERAL (
         SELECT period.id, period.effective_from, period.effective_to
         FROM position_department_head_periods period
         WHERE period.position_id = p.id
           AND period.is_active = true
           AND (period.effective_to IS NULL OR period.effective_to >= $1::date)
         ORDER BY (period.effective_from <= $1::date) DESC,
                  period.effective_from
         LIMIT 1
       ) managed_period ON true
       LEFT JOIN LATERAL (
         SELECT jsonb_agg(
                  jsonb_build_object(
                    'id', period.id,
                    'effective_from', period.effective_from::text,
                    'effective_to', period.effective_to::text,
                    'is_active', period.is_active
                  ) ORDER BY period.effective_from DESC, period.created_at DESC
                ) AS periods
         FROM position_department_head_periods period
         WHERE period.position_id = p.id
       ) period_history ON true
       ${where}
       ORDER BY p.name`,
      params
    );

    const rows = result.rows.map((r) => {
      const dependencyCounts = positionDependencyCountsFromRow(r);
      const blockers = positionDependencyBlockers(dependencyCounts);
      const deactivationCounts = positionDeactivationCountsFromRow(r);
      const deactivationBlockers = positionDeactivationBlockers(
        deactivationCounts
      );
      return {
        id: r.id,
        position_number: r.position_number,
        name: r.name,
        description: r.description,
        department_id: r.department_id,
        department_name: r.department_name,
        is_department_head: r.is_department_head === true,
        department_head_period_id: r.department_head_period_id || null,
        department_head_effective_from: r.department_head_effective_from || null,
        department_head_effective_to: r.department_head_effective_to || null,
        department_head_periods: Array.isArray(r.department_head_periods)
          ? r.department_head_periods
          : [],
        is_active: r.is_active ?? true,
        can_permanently_delete: blockers.length === 0,
        delete_blockers: blockers,
        can_deactivate: deactivationBlockers.length === 0,
        deactivation_blockers: deactivationBlockers,
        departments: r.department_name ? { name: r.department_name } : null,
      };
    });
    res.json(rows);
  } catch (err) {
    console.error('[positions GET]', err);
    res.status(500).json({ error: 'Failed to fetch positions' });
  }
});

// POST /api/positions - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const {
      name,
      description,
      department_id,
      is_department_head = false,
      department_head_effective_from,
      department_head_effective_to,
      is_active = true,
    } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    if (is_department_head === true && !department_id) {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }

    client = await pool.connect();
    await client.query('BEGIN');
    await ensureActivePositionDepartmentAllowed(client, {
      departmentId: department_id,
      positionIsActive: !!is_active,
    });
    const result = await client.query(
      `INSERT INTO positions (
         name, description, department_id, is_department_head, is_active
       ) VALUES ($1, $2, $3, false, $4)
       RETURNING id, position_number, name, description, department_id,
                 is_department_head, is_active`,
      [
        name.trim(),
        description?.trim() || null,
        department_id || null,
        !!is_active,
      ]
    );
    const r = result.rows[0];
    const period = is_department_head === true
      ? await saveDepartmentHeadPeriod(client, {
          actorId: req.user?.id,
          positionId: r.id,
          departmentId: department_id,
          effectiveFrom: department_head_effective_from,
          effectiveTo: department_head_effective_to,
        })
      : null;
    const after = positionAuditSnapshot(r, period);
    await writePositionAudit(client, {
      actorId: req.user?.id,
      action: 'position_created',
      positionId: r.id,
      after,
    });
    await client.query('COMMIT');
    res.status(201).json({
      id: r.id,
      position_number: r.position_number,
      name: r.name,
      description: r.description,
      department_id: r.department_id,
      is_department_head: period !== null,
      department_head_period_id: period?.id || null,
      department_head_effective_from: period?.effective_from || null,
      department_head_effective_to: period?.effective_to || null,
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[positions POST rollback]', rollbackError);
      }
    }
    console.error('[positions POST]', err);
    if (err instanceof PositionLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    if (err.code === '23P01' && err.constraint === 'position_department_head_period_no_overlap') {
      return res.status(409).json({
        error: 'This department already has an official Department Head during the selected effective period',
      });
    }
    if (err.code === '23505' && err.constraint === 'uq_positions_name_department') {
      return res.status(409).json({
        error: 'A position with this name already exists in the selected department',
      });
    }
    if (err.code === '23514') {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }
    res.status(500).json({ error: 'Failed to create position' });
  } finally {
    client?.release();
  }
});

// PUT /api/positions/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const { id } = req.params;
    const {
      name,
      description,
      department_id,
      is_department_head,
      is_active,
      department_head_period_id,
      department_head_effective_from,
      department_head_effective_to,
    } = req.body;

    if (is_department_head === true && department_id === null) {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (department_id !== undefined) { updates.push(`department_id = $${i++}`); values.push(department_id || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0 && is_department_head === undefined) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    client = await pool.connect();
    await client.query('BEGIN');

    let existing;
    if (department_id !== undefined) {
      existing = await ensurePositionDepartmentChangeAllowed(client, {
        positionId: id,
        nextDepartmentId: department_id,
      });
    } else {
      existing = await lockPositionForUpdate(client, id);
      if (!existing) {
        throw new PositionLifecycleError('Position not found', 404);
      }
    }

    if (is_active === false && existing.is_active !== false) {
      await ensurePositionDeactivationAllowed(client, {
        positionId: id,
        effectiveDate: todayInHrmsTimezone(),
        lockedPosition: existing,
      });
    }

    await ensureActivePositionDepartmentAllowed(client, {
      departmentId:
        department_id === undefined ? existing.department_id : department_id,
      positionIsActive:
        is_active === undefined ? existing.is_active !== false : !!is_active,
    });
    const beforePeriod = await getManagedDepartmentHeadPeriod(client, id);
    const before = positionAuditSnapshot(existing, beforePeriod);

    let result = { rows: [existing] };
    if (updates.length > 0) {
      updates.push('updated_at = now()');
      values.push(id);
      result = await client.query(
        `UPDATE positions SET ${updates.join(', ')} WHERE id = $${i}
         RETURNING id, position_number, name, description, department_id,
                   is_department_head, is_active`,
        values
      );
    }
    const r = result.rows[0];
    let period = null;
    if (is_department_head === true) {
      period = await saveDepartmentHeadPeriod(client, {
        actorId: req.user?.id,
        positionId: id,
        departmentId: r.department_id,
        periodId: department_head_period_id,
        effectiveFrom: department_head_effective_from,
        effectiveTo: department_head_effective_to,
      });
    } else if (is_department_head === false) {
      await endDepartmentHeadPeriod(client, {
        positionId: id,
        periodId: department_head_period_id,
      });
    }
    period = await getManagedDepartmentHeadPeriod(client, id);
    const after = positionAuditSnapshot(r, period);
    await writePositionAudit(client, {
      actorId: req.user?.id,
      action: positionAuditAction(before, after),
      positionId: id,
      before,
      after,
    });
    await client.query('COMMIT');
    res.json({
      id: r.id,
      position_number: r.position_number,
      name: r.name,
      description: r.description,
      department_id: r.department_id,
      is_department_head: period !== null,
      department_head_period_id: period?.id || null,
      department_head_effective_from: period?.effective_from || null,
      department_head_effective_to: period?.effective_to || null,
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[positions PUT rollback]', rollbackError);
      }
    }
    console.error('[positions PUT]', err);
    if (err instanceof PositionLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    if (err.code === '23P01' && err.constraint === 'position_department_head_period_no_overlap') {
      return res.status(409).json({
        error: 'This department already has an official Department Head during the selected effective period',
      });
    }
    if (err.code === '23505' && err.constraint === 'uq_positions_name_department') {
      return res.status(409).json({
        error: 'A position with this name already exists in the selected department',
      });
    }
    if (err.code === '23514') {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }
    res.status(500).json({ error: 'Failed to update position' });
  } finally {
    client?.release();
  }
});

// DELETE /api/positions/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const result = await deleteMistakenPosition(client, {
      actorId: req.user?.id,
      positionId: req.params.id,
      reason: req.body?.reason,
    });
    await client.query('COMMIT');
    return res.json({
      message: 'Unused position permanently deleted',
      position: result.position,
    });
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[positions DELETE rollback]', rollbackError);
      }
    }
    if (err instanceof PositionLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.details || {}),
      });
    }
    console.error('[positions DELETE]', err);
    res.status(500).json({ error: 'Failed to delete position' });
  } finally {
    client?.release();
  }
});

module.exports = router;
