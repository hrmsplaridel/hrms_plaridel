const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  AdditionalPositionTransitionError,
  createAdditionalPositionTransition,
  updateAdditionalPositionTransition,
} = require('../services/additionalPositionTransition');
const {
  assignmentAccessDeniedForRows,
  filterAssignmentRowsForAccess,
  resolveAssignmentEmployeeAccess,
} = require('../services/assignmentAccess');
const {
  AssignmentHistoryError,
  deactivateAssignmentRecord,
  normalizeChangeReason,
  permanentlyDeleteFutureAssignment,
  writeAssignmentHistoryAudit,
} = require('../services/assignmentHistory');
const {
  AssignmentStatusError,
  assignmentStatusContext,
  assignmentStatusWhereSql,
  computedAssignmentStatusSql,
} = require('../services/assignmentStatus');

const router = express.Router();
const protect = [authMiddleware];

function mapOtherPositionRow(row) {
  return {
    id: row.id,
    employee_id: row.employee_id,
    department_id: row.department_id,
    position_id: row.position_id,
    effective_from: row.effective_from,
    effective_to: row.effective_to,
    is_active: row.is_active,
    computed_status: row.computed_status,
    official_date: row.official_date,
    can_permanently_delete: row.can_permanently_delete === true,
    remarks: row.remarks,
    department_name: row.department_name,
    position_name: row.position_name,
    employee_name: row.employee_name,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

// GET /api/employee-other-positions?employee_id=uuid&status=Current|Upcoming|Expired|Archived|All
// GET /api/employee-other-positions?position_title=Title&status=Current
router.get('/', protect, async (req, res) => {
  try {
    const employeeId = (req.query.employee_id || '').toString().trim();
    const positionTitle = (req.query.position_title || '').toString().trim();
    const statusContext = assignmentStatusContext(req.query.status, {
      fallback: 'All',
    });

    if (!employeeId && !positionTitle) {
      return res.status(400).json({ error: 'employee_id or position_title is required' });
    }

    const access = resolveAssignmentEmployeeAccess(req.user, employeeId || null, {
      allowDirectorySearch: Boolean(positionTitle),
    });
    if (!access.allowed) {
      return res.status(access.statusCode).json({ error: access.error });
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
    const todayPlaceholder = `$${i++}`;
    params.push(statusContext.today);
    const statusWhere = assignmentStatusWhereSql(
      'eop',
      statusContext.status,
      todayPlaceholder
    );
    const where = whereParts.join(' AND ');

    const result = await pool.query(
      `SELECT eop.id, eop.employee_id, eop.department_id, eop.position_id,
              eop.effective_from::text AS effective_from,
              eop.effective_to::text AS effective_to,
              eop.is_active, eop.remarks, eop.created_at, eop.updated_at,
              ${computedAssignmentStatusSql('eop', todayPlaceholder)} AS computed_status,
              ${todayPlaceholder}::date::text AS official_date,
              (eop.effective_from > ${todayPlaceholder}::date) AS can_permanently_delete,
              u.full_name AS employee_name,
              d.name AS department_name,
              p.name AS position_name,
              COALESCE(eop.department_id, p.department_id) AS access_department_id
       FROM employee_other_positions eop
       JOIN users u ON u.id = eop.employee_id
       LEFT JOIN departments d ON d.id = eop.department_id
       JOIN positions p ON p.id = eop.position_id
       WHERE ${where} ${statusWhere}
       ORDER BY eop.is_active DESC, eop.effective_from DESC, eop.created_at DESC`,
      params,
    );

    const visibleRows = await filterAssignmentRowsForAccess(pool, access, result.rows);
    if (assignmentAccessDeniedForRows(access, result.rows, visibleRows)) {
      return res.status(403).json({
        error: 'You can only view additional positions within your supervised departments',
      });
    }

    res.json(visibleRows.map(mapOtherPositionRow));
  } catch (err) {
    if (err instanceof AssignmentStatusError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[employee-other-positions GET]', err);
    res.status(500).json({ error: 'Failed to fetch employee other positions' });
  }
});

// POST /api/employee-other-positions - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  let client;
  let transactionStarted = false;
  try {
    const {
      employee_id,
      department_id,
      position_id,
      effective_from,
      effective_to,
      is_active = true,
      remarks,
    } = req.body;

    client = await pool.connect();
    await client.query('BEGIN');
    transactionStarted = true;
    const position = await createAdditionalPositionTransition(client, {
      employeeId: employee_id,
      departmentId: department_id,
      positionId: position_id,
      effectiveFrom: effective_from,
      effectiveTo: effective_to,
      isActive: is_active === true,
      remarks,
      createdBy: req.user?.id,
    });
    await writeAssignmentHistoryAudit(client, {
      actorId: req.user?.id,
      recordType: 'additional',
      recordId: position.id,
      action: 'employee_other_position_created',
      reason: String(remarks || '').trim() || 'Additional position created',
      before: null,
      after: position,
    });
    await client.query('COMMIT');
    transactionStarted = false;
    res.status(201).json(position);
  } catch (err) {
    if (transactionStarted) await client.query('ROLLBACK');
    if (err instanceof AdditionalPositionTransitionError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid additional position selection' });
    }
    if (err.code === '23505' || err.code === '23P01') {
      return res.status(409).json({ error: 'Additional position conflicts with an existing record' });
    }
    console.error('[employee-other-positions POST]', err);
    res.status(500).json({ error: 'Failed to create employee other position' });
  } finally {
    client?.release();
  }
});

// PUT /api/employee-other-positions/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  let transactionStarted = false;
  try {
    const { id } = req.params;
    const {
      department_id,
      position_id,
      effective_from,
      effective_to,
      is_active,
      remarks,
      change_reason,
    } = req.body;

    if (
      department_id === undefined &&
      position_id === undefined &&
      effective_from === undefined &&
      effective_to === undefined &&
      is_active === undefined &&
      remarks === undefined
    ) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    client = await pool.connect();
    await client.query('BEGIN');
    transactionStarted = true;
    const transition = await updateAdditionalPositionTransition(client, {
      id,
      changes: {
        departmentId: department_id,
        positionId: position_id,
        effectiveFrom: effective_from,
        effectiveTo: effective_to,
        isActive: is_active,
        remarks,
      },
    });
    const isDeactivating = is_active === false && transition.before.is_active !== false;
    const deactivationReason = isDeactivating
      ? normalizeChangeReason(change_reason)
      : null;
    await writeAssignmentHistoryAudit(client, {
      actorId: req.user?.id,
      recordType: 'additional',
      recordId: id,
      action: isDeactivating
        ? 'employee_other_position_deactivated'
        : 'employee_other_position_updated',
      reason:
        deactivationReason ||
        String(change_reason || '').trim() ||
        String(remarks || '').trim() ||
        'Additional position updated',
      before: transition.before,
      after: transition.after,
    });

    await client.query('COMMIT');
    transactionStarted = false;
    res.json(transition.after);
  } catch (err) {
    if (transactionStarted) {
      await client.query('ROLLBACK');
    }
    if (err instanceof AssignmentHistoryError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err instanceof AdditionalPositionTransitionError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid additional position selection' });
    }
    if (err.code === '23505' || err.code === '23P01') {
      return res.status(409).json({ error: 'Additional position conflicts with an existing record' });
    }
    console.error('[employee-other-positions PUT]', err);
    res.status(500).json({ error: 'Failed to update employee other position' });
  } finally {
    client?.release();
  }
});

// DELETE /api/employee-other-positions/:id - archive without erasing history
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    try {
      const result = await deactivateAssignmentRecord(client, {
        actorId: req.user?.id,
        recordType: 'additional',
        recordId: req.params.id,
        reason: req.body?.reason,
      });
      await client.query('COMMIT');
      res.json({
        message: result.changed
          ? 'Employee other position deactivated and retained in history'
          : 'Employee other position is already inactive',
        assignment: result.record,
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } catch (err) {
    if (err instanceof AssignmentHistoryError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[employee-other-positions DELETE]', err);
    res.status(500).json({ error: 'Failed to deactivate employee other position' });
  } finally {
    client?.release();
  }
});

// DELETE /api/employee-other-positions/:id/permanent - unused future mistake only
router.delete('/:id/permanent', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    try {
      await permanentlyDeleteFutureAssignment(client, {
        actorId: req.user?.id,
        recordType: 'additional',
        recordId: req.params.id,
        reason: req.body?.reason,
      });
      await client.query('COMMIT');
      res.json({ message: 'Mistaken future other position permanently deleted' });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } catch (err) {
    if (err instanceof AssignmentHistoryError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[employee-other-positions permanent DELETE]', err);
    res.status(500).json({
      error: 'Failed to permanently delete employee other position',
    });
  } finally {
    client?.release();
  }
});

module.exports = router;
