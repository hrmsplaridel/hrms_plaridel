const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  DepartmentLifecycleError,
  deleteMistakenDepartment,
  departmentDependencyCountsSql,
  dependencyBlockers,
  dependencyCountsFromRow,
  ensureDepartmentCanDeactivate,
  previewDepartmentDeactivation,
} = require('../services/departmentLifecycle');
const { dateInTimeZone } = require('../services/assignmentReconciliation');

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

// POST /api/departments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, description, is_active = true } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }

    // Assign next available number (fills gaps: 1,2,3... no skips)
    const result = await pool.query(
      `INSERT INTO departments (name, description, is_active, department_number)
       SELECT $1, $2, $3, COALESCE(
         (SELECT MIN(g.n) FROM generate_series(1, (SELECT COALESCE(MAX(department_number), 0) + 1 FROM departments)) AS g(n)
          WHERE NOT EXISTS (SELECT 1 FROM departments d2 WHERE d2.department_number = g.n)),
         1
       )
       RETURNING id, department_number, name, description, is_active`,
      [name.trim(), description?.trim() || null, !!is_active]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'A department with this name already exists.' });
    }
    console.error('[departments POST]', err);
    res.status(500).json({ error: 'Failed to create department' });
  }
});

// PUT /api/departments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const { id } = req.params;
    const { name, description, is_active } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (name !== undefined) {
      updates.push(`name = $${i++}`);
      values.push(name.trim());
    }
    if (description !== undefined) {
      updates.push(`description = $${i++}`);
      values.push(description?.trim() || null);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${i++}`);
      values.push(!!is_active);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    updates.push('updated_at = now()');
    values.push(id);

    client = await pool.connect();
    await client.query('BEGIN');
    if (is_active === false) {
      await ensureDepartmentCanDeactivate(client, {
        departmentId: id,
        officialDate: dateInTimeZone(),
      });
    }

    const result = await client.query(
      `UPDATE departments SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, department_number, name, description, is_active`,
      values
    );

    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Department not found' });
    }
    await client.query('COMMIT');
    res.json(result.rows[0]);
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
