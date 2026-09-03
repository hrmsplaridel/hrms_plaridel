const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  DepartmentLifecycleError,
  deleteMistakenDepartment,
  departmentAuditAction,
  departmentDependencyCountsSql,
  dependencyBlockers,
  dependencyCountsFromRow,
  ensureDepartmentCanDeactivate,
  loadDepartmentDependencyCounts,
  previewDepartmentDeactivation,
  writeDepartmentAudit,
} = require('../services/departmentLifecycle');
const { dateInTimeZone } = require('../services/assignmentReconciliation');
const { addDays } = require('../utils/dateRangeParser');
const {
  resolveDepartmentReviewers,
} = require('../services/departmentReviewerService');
const {
  DepartmentValidationError,
  normalizeDepartmentWrite,
} = require('../services/departmentValidation');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/departments - list all (optional: ?status=Active|Inactive|All)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    let query = `SELECT d.id, d.department_number, d.name, d.description,
                        d.is_active, d.created_at,
                        ${departmentDependencyCountsSql('d')}
                   FROM departments d`;
    const params = [];

    if (status === 'Active') {
      query += ' WHERE (d.is_active IS NULL OR d.is_active = true)';
    } else if (status === 'Inactive') {
      query += ' WHERE d.is_active = false';
    }

    query += ' ORDER BY d.name';

    const result = await pool.query(query, params);
    const rows = result.rows.map((r) => {
      const dependencyCounts = dependencyCountsFromRow(r);
      const blockers = dependencyBlockers(dependencyCounts);
      return {
        id: r.id,
        department_number: r.department_number,
        name: r.name,
        description: r.description,
        is_active: r.is_active ?? true,
        can_permanently_delete: blockers.length === 0,
        delete_blockers: blockers,
      };
    });
    res.json(rows);
  } catch (err) {
    console.error('[departments GET]', err);
    res.status(500).json({ error: 'Failed to fetch departments' });
  }
});

// GET /api/departments/:id/deactivation-preview - show active blockers
router.get('/:id/deactivation-preview', protect, requireAdmin, async (req, res) => {
  try {
    const officialDate = dateInTimeZone();
    const preview = await previewDepartmentDeactivation(pool, {
      departmentId: req.params.id,
      officialDate,
    });
    return res.json({
      department: preview.department,
      official_date: officialDate,
      can_deactivate: preview.canDeactivate,
      blockers: preview.blockers,
    });
  } catch (err) {
    if (err instanceof DepartmentLifecycleError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[departments GET deactivation-preview]', err);
    return res.status(500).json({
      error: 'Failed to check whether the department can be deactivated',
    });
  }
});

// GET /api/departments/:id/reviewer-config - current Head, backups, and roster
router.get('/:id/reviewer-config', protect, requireAdmin, async (req, res) => {
  try {
    const effectiveDate = String(req.query.effective_date || dateInTimeZone());
    if (!/^\d{4}-\d{2}-\d{2}$/.test(effectiveDate)) {
      return res.status(400).json({ error: 'effective_date must use YYYY-MM-DD' });
    }
    const department = await pool.query(
      `SELECT id, name FROM departments WHERE id = $1::uuid`,
      [req.params.id]
    );
    if (department.rowCount === 0) {
      return res.status(404).json({ error: 'Department not found' });
    }
    const reviewers = await resolveDepartmentReviewers(pool, {
      departmentId: req.params.id,
      effectiveDate,
    });
    const roster = await pool.query(
      `SELECT DISTINCT ON (u.id)
              u.id, COALESCE(NULLIF(btrim(u.full_name), ''), u.email) AS name
       FROM assignments a
       JOIN users u ON u.id = a.employee_id
       WHERE a.department_id = $1::uuid
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
         AND (u.is_active IS NULL OR u.is_active = true)
       ORDER BY u.id, a.effective_from DESC, a.created_at DESC`,
      [req.params.id, effectiveDate]
    );
    return res.json({
      department: department.rows[0],
      effective_date: effectiveDate,
      primary: reviewers.primary,
      backups: reviewers.backups,
      eligible_employees: roster.rows,
    });
  } catch (err) {
    console.error('[departments GET reviewer-config]', err);
    return res.status(500).json({ error: 'Failed to load department reviewers' });
  }
});

// PUT /api/departments/:id/reviewer-backups - replace backups from a date onward
router.put('/:id/reviewer-backups', protect, requireAdmin, async (req, res) => {
  const effectiveFrom = String(req.body?.effective_from || dateInTimeZone());
  const employeeIds = Array.isArray(req.body?.employee_ids)
    ? [...new Set(req.body.employee_ids.map(String).map((id) => id.trim()).filter(Boolean))]
    : [];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(effectiveFrom)) {
    return res.status(400).json({ error: 'effective_from must use YYYY-MM-DD' });
  }
  if (employeeIds.length > 5) {
    return res.status(400).json({ error: 'A department can have at most five backup reviewers' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const department = await client.query(
      `SELECT id FROM departments WHERE id = $1::uuid FOR UPDATE`,
      [req.params.id]
    );
    if (department.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Department not found' });
    }

    const resolved = await resolveDepartmentReviewers(client, {
      departmentId: req.params.id,
      effectiveDate: effectiveFrom,
    });
    if (resolved.primary && employeeIds.includes(String(resolved.primary.reviewerId))) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'The official Department Head cannot also be a backup reviewer' });
    }

    if (employeeIds.length > 0) {
      const eligible = await client.query(
        `SELECT DISTINCT u.id::text AS id
         FROM assignments a
         JOIN users u ON u.id = a.employee_id
         WHERE a.department_id = $1::uuid
           AND u.id = ANY($2::uuid[])
           AND a.effective_from <= $3::date
           AND (a.effective_to IS NULL OR a.effective_to >= $3::date)
           AND (u.is_active IS NULL OR u.is_active = true)`,
        [req.params.id, employeeIds, effectiveFrom]
      );
      const eligibleIds = new Set(eligible.rows.map((row) => row.id));
      const invalidIds = employeeIds.filter((id) => !eligibleIds.has(id));
      if (invalidIds.length > 0) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          error: 'Every backup reviewer must be assigned to this department on the effective date',
          invalid_employee_ids: invalidIds,
        });
      }
    }

    const previousDay = addDays(effectiveFrom, -1);
    await client.query(
      `UPDATE department_reviewer_backups
       SET effective_to = $2::date, updated_at = now()
       WHERE department_id = $1::uuid
         AND is_active = true
         AND effective_from < $3::date
         AND (effective_to IS NULL OR effective_to >= $3::date)`,
      [req.params.id, previousDay, effectiveFrom]
    );
    await client.query(
      `UPDATE department_reviewer_backups
       SET is_active = false, updated_at = now()
       WHERE department_id = $1::uuid
         AND is_active = true
         AND effective_from >= $2::date`,
      [req.params.id, effectiveFrom]
    );
    for (let index = 0; index < employeeIds.length; index += 1) {
      await client.query(
        `INSERT INTO department_reviewer_backups (
           department_id, employee_id, backup_rank, effective_from, created_by
         ) VALUES ($1::uuid, $2::uuid, $3, $4::date, $5::uuid)`,
        [req.params.id, employeeIds[index], index + 1, effectiveFrom, req.user?.id || null]
      );
    }
    await client.query('COMMIT');
    const updated = await resolveDepartmentReviewers(pool, {
      departmentId: req.params.id,
      effectiveDate: effectiveFrom,
    });
    return res.json({
      effective_date: effectiveFrom,
      primary: updated.primary,
      backups: updated.backups,
    });
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { }
    if (err.code === '23P01') {
      return res.status(409).json({ error: 'Backup reviewer periods overlap an existing configuration' });
    }
    if (err.code === '22P02') {
      return res.status(400).json({ error: 'Invalid employee selection' });
    }
    console.error('[departments PUT reviewer-backups]', err);
    return res.status(500).json({ error: 'Failed to save department reviewers' });
  } finally {
    client.release();
  }
});

// POST /api/departments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const { name, description, is_active } = normalizeDepartmentWrite(
      req.body,
      { creating: true }
    );

    client = await pool.connect();
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO departments (name, description, is_active)
       VALUES ($1, $2, $3)
       RETURNING id, department_number, name, description, is_active,
                 created_at, updated_at`,
      [name, description, is_active]
    );
    const department = result.rows[0];
    await writeDepartmentAudit(client, {
      actorId: req.user?.id,
      action: 'department_created',
      departmentId: department.id,
      after: department,
    });
    await client.query('COMMIT');
    res.status(201).json(department);
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[departments POST rollback]', rollbackError);
      }
    }
    if (err instanceof DepartmentValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (
      err.code === '23505' &&
      ['departments_name_key', 'uq_departments_name_ci'].includes(err.constraint)
    ) {
      return res.status(409).json({ error: 'A department with this name already exists.' });
    }
    if (
      err.code === '23505' &&
      err.constraint === 'departments_department_number_key'
    ) {
      return res.status(409).json({
        error: 'Department number conflict. Please retry the operation.',
      });
    }
    console.error('[departments POST]', err);
    res.status(500).json({ error: 'Failed to create department' });
  } finally {
    client?.release();
  }
});

// PUT /api/departments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const { id } = req.params;
    const normalized = normalizeDepartmentWrite(req.body);
    const {
      name,
      description,
      is_active,
      confirm_historical_label_change: renameConfirmed,
    } = normalized;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) {
      updates.push(`name = $${i++}`);
      values.push(name);
    }
    if (description !== undefined) {
      updates.push(`description = $${i++}`);
      values.push(description);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${i++}`);
      values.push(is_active);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    updates.push('updated_at = now()');
    values.push(id);

    client = await pool.connect();
    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT id, department_number, name, description, is_active,
              created_at, updated_at
         FROM departments
        WHERE id = $1::uuid
        FOR UPDATE`,
      [id]
    );
    if (existing.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Department not found' });
    }
    const before = existing.rows[0];

    if (
      name !== undefined &&
      name !== before.name &&
      renameConfirmed !== true
    ) {
      const dependencyCounts = await loadDepartmentDependencyCounts(client, id);
      const renameBlockers = dependencyBlockers(dependencyCounts);
      if (renameBlockers.length > 0) {
        throw new DepartmentLifecycleError(
          'Renaming this department will update its label across historical records. Confirm the historical label change, or deactivate this department and create a new one for an organizational restructuring.',
          409,
          renameBlockers
        );
      }
    }

    if (is_active === false && before.is_active !== false) {
      await ensureDepartmentCanDeactivate(client, {
        departmentId: id,
        officialDate: dateInTimeZone(),
      });
    }

    const result = await client.query(
      `UPDATE departments SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, department_number, name, description, is_active,
                 created_at, updated_at`,
      values
    );

    const after = result.rows[0];
    await writeDepartmentAudit(client, {
      actorId: req.user?.id,
      action: departmentAuditAction(before, after),
      departmentId: id,
      before,
      after,
    });
    await client.query('COMMIT');
    res.json(after);
  } catch (err) {
    if (client) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('[departments PUT rollback]', rollbackError);
      }
    }
    if (err instanceof DepartmentLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.blockers ? { blockers: err.blockers } : {}),
      });
    }
    if (err instanceof DepartmentValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (
      err.code === '23505' &&
      ['departments_name_key', 'uq_departments_name_ci'].includes(err.constraint)
    ) {
      return res.status(409).json({
        error: 'A department with this name already exists.',
      });
    }
    console.error('[departments PUT]', err);
    res.status(500).json({ error: 'Failed to update department' });
  } finally {
    client?.release();
  }
});

// DELETE /api/departments/:id (admin only) - optional, can use PUT to deactivate
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    try {
      const result = await deleteMistakenDepartment(client, {
        actorId: req.user?.id,
        departmentId: req.params.id,
        reason: req.body?.reason,
      });
      await client.query('COMMIT');
      return res.json({
        message: 'Mistaken department permanently deleted',
        department: result.department,
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } catch (err) {
    if (err instanceof DepartmentLifecycleError) {
      return res.status(err.statusCode).json({
        error: err.message,
        ...(err.blockers ? { blockers: err.blockers } : {}),
      });
    }
    console.error('[departments DELETE]', err);
    res.status(500).json({ error: 'Failed to delete department' });
  } finally {
    client?.release();
  }
});

module.exports = router;
