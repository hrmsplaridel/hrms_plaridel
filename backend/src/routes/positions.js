const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  PositionLifecycleError,
  deleteMistakenPosition,
  ensurePositionDepartmentChangeAllowed,
  positionDependencyBlockers,
  positionDependencyCountsFromRow,
  positionDependencyCountsSql,
} = require('../services/positionLifecycle');

const router = express.Router();
const protect = [authMiddleware];

// GET /api/positions - list all (?status=Active|Inactive|All, ?department_id=uuid)
router.get('/', protect, async (req, res) => {
  try {
    const { status = 'Active', department_id } = req.query;
    const params = [];
    const conditions = [];
    let i = 1;

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
              p.is_department_head, p.is_active,
              d.name AS department_name,
              ${positionDependencyCountsSql('p')}
       FROM positions p
       LEFT JOIN departments d ON p.department_id = d.id
       ${where}
       ORDER BY p.name`,
      params
    );

    const rows = result.rows.map((r) => {
      const dependencyCounts = positionDependencyCountsFromRow(r);
      const blockers = positionDependencyBlockers(dependencyCounts);
      return {
        id: r.id,
        position_number: r.position_number,
        name: r.name,
        description: r.description,
        department_id: r.department_id,
        department_name: r.department_name,
        is_department_head: r.is_department_head === true,
        is_active: r.is_active ?? true,
        can_permanently_delete: blockers.length === 0,
        delete_blockers: blockers,
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
  try {
    const {
      name,
      description,
      department_id,
      is_department_head = false,
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

    const result = await pool.query(
      `INSERT INTO positions (
         name, description, department_id, is_department_head, is_active
       ) VALUES ($1, $2, $3, $4, $5)
       RETURNING id, position_number, name, description, department_id,
                 is_department_head, is_active`,
      [
        name.trim(),
        description?.trim() || null,
        department_id || null,
        is_department_head === true,
        !!is_active,
      ]
    );
    const r = result.rows[0];
    res.status(201).json({
      id: r.id,
      position_number: r.position_number,
      name: r.name,
      description: r.description,
      department_id: r.department_id,
      is_department_head: r.is_department_head === true,
      is_active: r.is_active ?? true,
    });
  } catch (err) {
    console.error('[positions POST]', err);
    if (err.code === '23505' && err.constraint === 'uq_positions_department_head_per_department') {
      return res.status(409).json({
        error: 'This department already has an official Department Head position',
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
  }
});

// PUT /api/positions/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const { id } = req.params;
    const { name, description, department_id, is_department_head, is_active } = req.body;

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
    if (is_department_head !== undefined) { updates.push(`is_department_head = $${i++}`); values.push(is_department_head === true); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    updates.push('updated_at = now()');
    values.push(id);

    client = await pool.connect();
    await client.query('BEGIN');

    if (department_id !== undefined) {
      await ensurePositionDepartmentChangeAllowed(client, {
        positionId: id,
        nextDepartmentId: department_id,
      });
    } else {
      const existing = await client.query(
        'SELECT id FROM positions WHERE id = $1::uuid FOR UPDATE',
        [id]
      );
      if (existing.rowCount === 0) {
        throw new PositionLifecycleError('Position not found', 404);
      }
    }

    const result = await client.query(
      `UPDATE positions SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, position_number, name, description, department_id,
                 is_department_head, is_active`,
      values
    );
    await client.query('COMMIT');
    const r = result.rows[0];
    res.json({
      id: r.id,
      position_number: r.position_number,
      name: r.name,
      description: r.description,
      department_id: r.department_id,
      is_department_head: r.is_department_head === true,
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
    if (err.code === '23505' && err.constraint === 'uq_positions_department_head_per_department') {
      return res.status(409).json({
        error: 'This department already has an official Department Head position',
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
