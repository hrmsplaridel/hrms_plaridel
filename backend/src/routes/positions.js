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
  cleanDate,
  saveDepartmentHeadPeriod,
} = require('../services/positionDepartmentHeadPeriods');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { resolveFinalLeaveReviewers } = require('../services/leaveFinalReviewerService');
const {
  PositionValidationError,
  normalizePositionWrite,
} = require('../services/positionValidation');
const {
  parsePositionListFilters,
} = require('../services/positionListFilters');

const router = express.Router();
const protect = [authMiddleware];

router.get('/department-head-conflict', protect, async (req, res) => {
  try {
    const { department_id: departmentId, exclude_position_id: excludeId } = req.query;
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuid.test(departmentId || '') || (excludeId && !uuid.test(excludeId))) {
      return res.status(400).json({ error: 'A valid department and position ID are required' });
    }
    const from = cleanDate(req.query.effective_from || todayInHrmsTimezone(), 'Effective from');
    const to = cleanDate(req.query.effective_to, 'Effective to');
    if (to && to < from) {
      return res.status(400).json({ error: 'Effective to cannot precede effective from' });
    }
    const result = await pool.query(
      `SELECT period.position_id, p.name AS position_name
         FROM position_department_head_periods period
         JOIN positions p ON p.id = period.position_id
        WHERE period.department_id = $1::uuid
          AND period.position_id <> COALESCE($2::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
          AND period.is_active = true
          AND daterange(period.effective_from, period.effective_to, '[]')
              && daterange($3::date, $4::date, '[]')
        ORDER BY period.effective_from DESC
        LIMIT 1`,
      [departmentId, excludeId || null, from, to]
    );
    return res.json(result.rows[0] || { position_id: null, position_name: null });
  } catch (err) {
    if (err instanceof PositionLifecycleError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[positions GET department-head-conflict]', err);
    return res.status(500).json({ error: 'Failed to check Department Head designation' });
  }
});

// GET /api/positions - bounded legacy list or paginated management response
router.get('/', protect, async (req, res) => {
  try {
    const filters = parsePositionListFilters(req.query);
    if (!filters.ok) {
      return res.status(400).json({ error: filters.error });
    }
    const today = todayInHrmsTimezone();
    const filterParams = [];
    const conditions = [];
    let i = 1;

    if (filters.status === 'Active') {
      conditions.push('(p.is_active IS NULL OR p.is_active = true)');
    } else if (filters.status === 'Inactive') {
      conditions.push('p.is_active = false');
    }
    if (filters.departmentId) {
      conditions.push(`p.department_id = $${i++}::uuid`);
      filterParams.push(filters.departmentId);
    }
    if (filters.search) {
      conditions.push(`(
        p.name ILIKE $${i}
        OR COALESCE(p.description, '') ILIKE $${i}
        OR COALESCE(d.name, '') ILIKE $${i}
        OR COALESCE(p.position_number::text, '') ILIKE $${i}
      )`);
      filterParams.push(`%${filters.search}%`);
      i += 1;
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    let total = null;
    let effectivePage = 1;
    let pageCount = 1;
    if (filters.paginated) {
      const countResult = await pool.query(
        `SELECT COUNT(*)::int AS total
           FROM positions p
           LEFT JOIN departments d ON d.id = p.department_id
           ${where}`,
        filterParams
      );
      total = Number(countResult.rows[0]?.total || 0);
      pageCount = Math.max(1, Math.ceil(total / filters.limit));
      effectivePage = Math.min(filters.page, pageCount);
    }

    const limit = filters.responseLimit;
    const offset = filters.paginated ? (effectivePage - 1) * limit : 0;
    const todayPlaceholder = `$${i++}`;
    const limitPlaceholder = `$${i++}`;
    const offsetPlaceholder = `$${i++}`;
    const params = [...filterParams, today, limit, offset];

    const result = await pool.query(
      `WITH selected_positions AS (
         SELECT p.id, p.position_number, p.name, p.description,
                p.department_id, p.is_active, p.is_leave_final_reviewer
           FROM positions p
           LEFT JOIN departments d ON d.id = p.department_id
           ${where}
          ORDER BY LOWER(BTRIM(p.name)), p.position_number NULLS LAST, p.id
          LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}
       )
       SELECT p.id, p.position_number, p.name, p.description, p.department_id,
              p.is_leave_final_reviewer,
               (managed_period.id IS NOT NULL) AS is_department_head, p.is_active,
              managed_period.id AS department_head_period_id,
              managed_period.effective_from::text AS department_head_effective_from,
              managed_period.effective_to::text AS department_head_effective_to,
               COALESCE(period_history.periods, '[]'::jsonb) AS department_head_periods,
               d.name AS department_name,
               ${positionDependencyCountsSql('p')},
               ${positionDeactivationCountsSql('p.id', todayPlaceholder)}
       FROM selected_positions p
       LEFT JOIN departments d ON p.department_id = d.id
       LEFT JOIN LATERAL (
         SELECT period.id, period.effective_from, period.effective_to
         FROM position_department_head_periods period
         WHERE period.position_id = p.id
           AND period.is_active = true
           AND (period.effective_to IS NULL OR period.effective_to >= ${todayPlaceholder}::date)
         ORDER BY (period.effective_from <= ${todayPlaceholder}::date) DESC,
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
       ORDER BY LOWER(BTRIM(p.name)), p.position_number NULLS LAST, p.id`,
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
        is_leave_final_reviewer: r.is_leave_final_reviewer === true,
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
    if (!filters.paginated) {
      return res.json(rows);
    }
    return res.json({
      items: rows,
      pagination: {
        page: effectivePage,
        limit: filters.limit,
        page_size: filters.limit,
        total,
        page_count: pageCount,
      },
    });
  } catch (err) {
    console.error('[positions GET]', err);
    res.status(500).json({ error: 'Failed to fetch positions' });
  }
});

// Final leave reviewers are a separate office-wide assignment, not department backups.
router.get('/leave-final-reviewers', protect, requireAdmin, async (req, res) => {
  try {
    const date = String(req.query?.effective_date || todayInHrmsTimezone());
    const parsedDate = new Date(`${date}T00:00:00Z`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        !Number.isFinite(parsedDate.getTime()) ||
        parsedDate.toISOString().slice(0, 10) !== date) {
      return res.status(400).json({ error: 'effective_date must be a valid YYYY-MM-DD date' });
    }
    const [reviewers, roster, primary] = await Promise.all([
      resolveFinalLeaveReviewers(pool, date),
      pool.query(`SELECT id, full_name AS name FROM users
                  WHERE is_active = true AND role IN ('admin', 'hr')
                  ORDER BY full_name, id`),
      pool.query(`SELECT u.id, u.full_name AS name
                  FROM positions p
                  JOIN assignments a ON a.position_id = p.id
                  JOIN users u ON u.id = a.employee_id
                  WHERE p.is_leave_final_reviewer = true AND p.is_active = true
                    AND a.is_active = true AND u.is_active = true
                    AND u.role IN ('admin', 'hr')
                    AND a.effective_from <= $1::date
                    AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
                  ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
                  LIMIT 1`, [date]),
    ]);
    return res.json({
      effective_date: date,
      primary: primary.rows[0] || null,
      backups: reviewers.filter((row) => row.id !== primary.rows[0]?.id),
      eligible_employees: roster.rows,
    });
  } catch (err) {
    console.error('[positions GET leave-final-reviewers]', err);
    return res.status(500).json({ error: 'Failed to load final leave reviewers' });
  }
});

router.put('/leave-final-reviewers', protect, requireAdmin, async (req, res) => {
  const date = String(req.body?.effective_from || todayInHrmsTimezone());
  const ids = req.body?.employee_ids;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const parsedDate = new Date(`${date}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
      !Number.isFinite(parsedDate.getTime()) ||
      parsedDate.toISOString().slice(0, 10) !== date) {
    return res.status(400).json({ error: 'effective_from must be a valid YYYY-MM-DD date' });
  }
  if (!Array.isArray(ids) || ids.length > 5 || ids.some((id) => typeof id !== 'string' || !uuid.test(id)) || new Set(ids).size !== ids.length) {
    return res.status(400).json({ error: 'Provide up to five distinct backup employee IDs' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const primary = await client.query(
      `SELECT a.employee_id AS id FROM positions p
       JOIN assignments a ON a.position_id = p.id
       WHERE p.is_leave_final_reviewer = true AND p.is_active = true
         AND a.is_active = true AND a.effective_from <= $1::date
         AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
       LIMIT 1`, [date]
    );
    if (ids.includes(String(primary.rows[0]?.id))) {
      throw Object.assign(new Error('The official final reviewer cannot also be a backup'), { statusCode: 409 });
    }
    if (ids.length) {
      const eligible = await client.query(
        `SELECT id::text AS id FROM users
         WHERE id = ANY($1::uuid[]) AND is_active = true AND role IN ('admin', 'hr')`,
        [ids]
      );
      if (eligible.rows.length !== ids.length) {
        throw Object.assign(new Error('Backups must be active HR or admin accounts'), { statusCode: 409 });
      }
    }
    const previousDate = new Date(`${date}T00:00:00Z`);
    previousDate.setUTCDate(previousDate.getUTCDate() - 1);
    const previousDay = previousDate.toISOString().slice(0, 10);
    await client.query(
      `UPDATE leave_final_reviewer_backups
       SET effective_to = $1::date, updated_at = now()
       WHERE is_active = true AND effective_from < $2::date
         AND (effective_to IS NULL OR effective_to >= $2::date)`,
      [previousDay, date]
    );
    await client.query(
      `UPDATE leave_final_reviewer_backups SET is_active = false, updated_at = now()
       WHERE is_active = true AND effective_from >= $1::date`, [date]
    );
    for (let index = 0; index < ids.length; index += 1) {
      await client.query(
        `INSERT INTO leave_final_reviewer_backups
           (employee_id, backup_rank, effective_from, created_by)
         VALUES ($1::uuid, $2, $3::date, $4::uuid)`,
        [ids[index], index + 1, date, req.user.id]
      );
    }
    await client.query('COMMIT');
    return res.json({ effective_date: date, backup_employee_ids: ids });
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    console.error('[positions PUT leave-final-reviewers]', err);
    return res.status(500).json({ error: 'Failed to save final leave reviewers' });
  } finally {
    client.release();
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
      is_leave_final_reviewer = false,
      department_head_effective_from,
      department_head_effective_to,
      is_active,
    } = normalizePositionWrite(req.body, { creating: true });
    if (is_department_head === true && !department_id) {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }

    client = await pool.connect();
    await client.query('BEGIN');
    await ensureActivePositionDepartmentAllowed(client, {
      departmentId: department_id,
      positionIsActive: is_active,
    });
    const result = await client.query(
      `INSERT INTO positions (
         name, description, department_id, is_department_head, is_leave_final_reviewer, is_active
       ) VALUES ($1, $2, $3, false, $4, $5)
       RETURNING id, position_number, name, description, department_id,
                 is_department_head, is_leave_final_reviewer, is_active`,
      [
        name,
        description,
        department_id,
        is_leave_final_reviewer,
        is_active,
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
      is_leave_final_reviewer: r.is_leave_final_reviewer === true,
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
    if (err instanceof PositionValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
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
    if (err.code === '23505' && err.constraint === 'uq_active_leave_final_reviewer_position') {
      return res.status(409).json({ error: 'Another active position is already the official final leave reviewer' });
    }
    if (
      err.code === '23505' &&
      ['uq_positions_name_department', 'uq_positions_name_department_ci']
        .includes(err.constraint)
    ) {
      return res.status(409).json({
        error: 'A position with this name already exists in the selected department',
      });
    }
    if (err.code === '23514') {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }
    console.error('[positions POST]', err);
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
      is_leave_final_reviewer,
      is_active,
      department_head_period_id,
      department_head_effective_from,
      department_head_effective_to,
    } = normalizePositionWrite(req.body);

    if (is_department_head === true && department_id === null) {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name); }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description); }
    if (department_id !== undefined) { updates.push(`department_id = $${i++}`); values.push(department_id); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(is_active); }

    if (is_leave_final_reviewer !== undefined) {
      updates.push(`is_leave_final_reviewer = $${i++}`);
      values.push(is_leave_final_reviewer);
    }

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
        is_active === undefined ? existing.is_active !== false : is_active,
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
                   is_department_head, is_leave_final_reviewer, is_active`,
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
      is_leave_final_reviewer: r.is_leave_final_reviewer === true,
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
    if (err instanceof PositionValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
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
    if (err.code === '23505' && err.constraint === 'uq_active_leave_final_reviewer_position') {
      return res.status(409).json({ error: 'Another active position is already the official final leave reviewer' });
    }
    if (
      err.code === '23505' &&
      ['uq_positions_name_department', 'uq_positions_name_department_ci']
        .includes(err.constraint)
    ) {
      return res.status(409).json({
        error: 'A position with this name already exists in the selected department',
      });
    }
    if (err.code === '23514') {
      return res.status(400).json({
        error: 'An official Department Head position must belong to a department',
      });
    }
    console.error('[positions PUT]', err);
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
