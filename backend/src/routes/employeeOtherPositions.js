const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

let ensurePromise = null;

function parseDate(val) {
  if (!val) return null;
  const d = new Date(val);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

function effectiveToBeforeFrom(ef, et) {
  return ef != null && et != null && et < ef;
}

async function ensureEmployeeOtherPositionsTable() {
  await pool.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
  await pool.query(`
    CREATE TABLE IF NOT EXISTS employee_other_positions (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
      position_id UUID NOT NULL REFERENCES positions(id) ON DELETE RESTRICT,
      effective_from DATE NOT NULL,
      effective_to DATE,
      is_active BOOLEAN NOT NULL DEFAULT true,
      remarks TEXT,
      created_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_employee_other_positions_employee
      ON employee_other_positions(employee_id, effective_from DESC)
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_employee_other_positions_position
      ON employee_other_positions(position_id)
  `);
}

function ensureTable() {
  if (!ensurePromise) {
    ensurePromise = ensureEmployeeOtherPositionsTable().catch((err) => {
      ensurePromise = null;
      throw err;
    });
  }
  return ensurePromise;
}

function mapOtherPositionRow(row) {
  return {
    id: row.id,
    employee_id: row.employee_id,
    department_id: row.department_id,
    position_id: row.position_id,
    effective_from: row.effective_from,
    effective_to: row.effective_to,
    is_active: row.is_active,
    remarks: row.remarks,
    department_name: row.department_name,
    position_name: row.position_name,
    employee_name: row.employee_name,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

// GET /api/employee-other-positions?employee_id=uuid&status=Active|Inactive|All
// GET /api/employee-other-positions?position_title=Title&status=Active
router.get('/', protect, async (req, res) => {
  try {
    await ensureTable();
    const employeeId = (req.query.employee_id || '').toString().trim();
    const positionTitle = (req.query.position_title || '').toString().trim();
    const status = req.query.status || 'All';

    if (!employeeId && !positionTitle) {
      return res.status(400).json({ error: 'employee_id or position_title is required' });
    }

    let statusWhere = '';
    if (status === 'Active') {
      statusWhere = `
        AND eop.is_active = true
        AND eop.effective_from <= CURRENT_DATE
        AND (eop.effective_to IS NULL OR eop.effective_to >= CURRENT_DATE)
      `;
    } else if (status === 'Inactive') {
      statusWhere = `
        AND (
          eop.is_active = false
          OR eop.effective_from > CURRENT_DATE
          OR eop.effective_to < CURRENT_DATE
        )
      `;
    }

    const whereParts = [];
    const params = [];
    let i = 1;
    if (employeeId) {
      whereParts.push(`eop.employee_id = $${i++}`);
      params.push(employeeId);
    }
    if (positionTitle) {
      whereParts.push(`LOWER(p.name) = LOWER($${i++})`);
      params.push(positionTitle);
    }
    const where = whereParts.join(' AND ');

    const result = await pool.query(
      `SELECT eop.id, eop.employee_id, eop.department_id, eop.position_id,
              eop.effective_from::text AS effective_from,
              eop.effective_to::text AS effective_to,
              eop.is_active, eop.remarks, eop.created_at, eop.updated_at,
              u.full_name AS employee_name,
              d.name AS department_name,
              p.name AS position_name
       FROM employee_other_positions eop
       JOIN users u ON u.id = eop.employee_id
       LEFT JOIN departments d ON d.id = eop.department_id
       JOIN positions p ON p.id = eop.position_id
       WHERE ${where} ${statusWhere}
         AND (u.is_active IS NULL OR u.is_active = true)
       ORDER BY eop.is_active DESC, eop.effective_from DESC, eop.created_at DESC`,
      params,
    );

    res.json(result.rows.map(mapOtherPositionRow));
  } catch (err) {
    console.error('[employee-other-positions GET]', err);
    res.status(500).json({ error: 'Failed to fetch employee other positions' });
  }
});

// POST /api/employee-other-positions - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    await ensureTable();
    const {
      employee_id,
      department_id,
      position_id,
      effective_from,
      effective_to,
      is_active = true,
      remarks,
    } = req.body;

    if (!employee_id || !position_id || !effective_from) {
      return res.status(400).json({
        error: 'employee_id, position_id, and effective_from are required',
      });
    }

    const ef = parseDate(effective_from);
    if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
    const et = effective_to != null && effective_to !== '' ? parseDate(effective_to) : null;
    if (effective_to != null && effective_to !== '' && !et) {
      return res.status(400).json({ error: 'Invalid effective_to' });
    }
    if (effectiveToBeforeFrom(ef, et)) {
      return res.status(400).json({ error: 'effective_to must be on or after effective_from' });
    }

    const result = await pool.query(
      `INSERT INTO employee_other_positions (
         employee_id, department_id, position_id,
         effective_from, effective_to, is_active, remarks, created_by
       )
       VALUES ($1, $2, $3, $4::date, $5::date, $6, $7, $8)
       RETURNING id, employee_id, department_id, position_id,
                 effective_from::text AS effective_from,
                 effective_to::text AS effective_to, is_active, remarks,
                 created_at, updated_at`,
      [
        employee_id,
        department_id || null,
        position_id,
        ef,
        et,
        !!is_active,
        String(remarks || '').trim() || null,
        req.user?.id || null,
      ],
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('[employee-other-positions POST]', err);
    res.status(500).json({ error: 'Failed to create employee other position' });
  }
});

// PUT /api/employee-other-positions/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    await ensureTable();
    const { id } = req.params;
    const {
      department_id,
      position_id,
      effective_from,
      effective_to,
      is_active,
      remarks,
    } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

    if (department_id !== undefined) {
      updates.push(`department_id = $${i++}`);
      values.push(department_id || null);
    }
    if (position_id !== undefined) {
      if (!position_id) return res.status(400).json({ error: 'position_id is required' });
      updates.push(`position_id = $${i++}`);
      values.push(position_id);
    }
    if (effective_from !== undefined) {
      const ef = parseDate(effective_from);
      if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
      updates.push(`effective_from = $${i++}::date`);
      values.push(ef);
    }
    if (effective_to !== undefined) {
      const et = effective_to === null || effective_to === '' ? null : parseDate(effective_to);
      if (effective_to !== null && effective_to !== '' && !et) {
        return res.status(400).json({ error: 'Invalid effective_to' });
      }
      updates.push(`effective_to = $${i++}::date`);
      values.push(et);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${i++}`);
      values.push(!!is_active);
    }
    if (remarks !== undefined) {
      updates.push(`remarks = $${i++}`);
      values.push(String(remarks || '').trim() || null);
    }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });

    const existing = await pool.query(
      `SELECT id, effective_from::text AS effective_from, effective_to::text AS effective_to
       FROM employee_other_positions
       WHERE id = $1`,
      [id],
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Employee other position not found' });
    }

    const row = existing.rows[0];
    const mergedEffectiveFrom =
      effective_from !== undefined ? parseDate(effective_from) : row.effective_from;
    const mergedEffectiveTo =
      effective_to !== undefined
        ? (effective_to === null || effective_to === '' ? null : parseDate(effective_to))
        : row.effective_to;
    if (effectiveToBeforeFrom(mergedEffectiveFrom, mergedEffectiveTo)) {
      return res.status(400).json({ error: 'effective_to must be on or after effective_from' });
    }

    updates.push('updated_at = now()');
    values.push(id);
    const result = await pool.query(
      `UPDATE employee_other_positions SET ${updates.join(', ')}
       WHERE id = $${i}
       RETURNING id, employee_id, department_id, position_id,
                 effective_from::text AS effective_from,
                 effective_to::text AS effective_to, is_active, remarks,
                 created_at, updated_at`,
      values,
    );

    res.json(result.rows[0]);
  } catch (err) {
    console.error('[employee-other-positions PUT]', err);
    res.status(500).json({ error: 'Failed to update employee other position' });
  }
});

// DELETE /api/employee-other-positions/:id - hard delete (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    await ensureTable();
    const result = await pool.query(
      'DELETE FROM employee_other_positions WHERE id = $1 RETURNING id',
      [req.params.id],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Employee other position not found' });
    }
    res.status(204).send();
  } catch (err) {
    console.error('[employee-other-positions DELETE]', err);
    res.status(500).json({ error: 'Failed to delete employee other position' });
  }
});

module.exports = router;
