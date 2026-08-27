const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { resolveAssignmentEmployeeAccess } = require('../services/assignmentAccess');
const {
  AssignmentTransitionError,
  createAssignmentTransition,
  updateAssignmentTransition,
} = require('../services/assignmentTransition');
const {
  AssignmentHistoryError,
  deactivateAssignmentRecord,
  normalizeChangeReason,
  permanentlyDeleteFutureAssignment,
  repairPrimaryPredecessorAfterFutureChange,
  writeAssignmentHistoryAudit,
} = require('../services/assignmentHistory');
const {
  EmployeePolicyAssignmentError,
  upsertEmployeePolicyAssignment,
} = require('../services/employeePolicyAssignment');

const router = express.Router();
const protect = [authMiddleware];

function parseDate(val) {
  if (!val) return null;
  const d = new Date(val);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

function parseTime(val) {
  if (!val) return null;
  const s = String(val);
  return s.match(/^\d{1,2}:\d{2}/) ? (s.length <= 5 ? s + ':00' : s.substring(0, 8)) : null;
}

/** Normalize a DATE / timestamp column from pg for comparison with parseDate() output (YYYY-MM-DD). */
function dateFromRow(val) {
  if (val == null) return null;
  if (typeof val === 'string') {
    const s = val.split('T')[0];
    return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
  }
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  return parseDate(val);
}

/** ef, et are YYYY-MM-DD; et null means open-ended. */
function effectiveToBeforeFrom(ef, et) {
  return ef != null && et != null && et < ef;
}

// GET /api/assignments?employee_id=uuid - list assignments for employee (Schema v2: effective_from/to, override times)
router.get('/', protect, async (req, res) => {
  try {
    const access = resolveAssignmentEmployeeAccess(req.user, req.query.employee_id);
    if (!access.allowed) {
      return res.status(access.statusCode).json({ error: access.error });
    }
    const employeeId = access.employeeId;
    const status = req.query.status || 'Active';

    let statusWhere = '';
    if (status === 'Active') statusWhere = 'AND (a.is_active IS NULL OR a.is_active = true)';
    else if (status === 'Inactive') statusWhere = 'AND a.is_active = false';

    const result = await pool.query(
      `SELECT a.id, a.employee_id, a.department_id, a.position_id, a.shift_id,
              a.override_start_time, a.override_end_time, a.override_break_end,
              a.effective_from::text AS effective_from,
              a.effective_to::text AS effective_to,
              a.is_active, a.remarks,
              d.name AS department_name, p.name AS position_name, s.name AS shift_name,
              s.start_time AS shift_start_time, s.end_time AS shift_end_time,
              s.break_end AS shift_break_end, s.punch_mode,
              s.working_days AS shift_working_days
       FROM assignments a
       LEFT JOIN departments d ON a.department_id = d.id
       LEFT JOIN positions p ON a.position_id = p.id
       LEFT JOIN shifts s ON a.shift_id = s.id
       WHERE a.employee_id = $1 ${statusWhere}
       ORDER BY a.effective_from DESC`,
      [employeeId]
    );

    res.json(result.rows.map((r) => {
      const wd = r.shift_working_days;
      const workingDays = Array.isArray(wd)
        ? wd.map((x) => (typeof x === 'number' ? x : parseInt(x, 10))).filter((x) => Number.isFinite(x))
        : (wd != null ? [1, 2, 3, 4, 5] : null);
      return {
        id: r.id,
        employee_id: r.employee_id,
        department_id: r.department_id,
        position_id: r.position_id,
        shift_id: r.shift_id,
        effective_from: r.effective_from,
        effective_to: r.effective_to,
        is_active: r.is_active ?? true,
        remarks: r.remarks,
        department_name: r.department_name,
        position_name: r.position_name,
        shift_name: r.shift_name,
        start_time: r.override_start_time || r.shift_start_time,
        end_time: r.override_end_time || r.shift_end_time,
        break_end: r.override_break_end || r.shift_break_end,
        punch_mode: r.punch_mode || 'auto',
        date_assigned: r.effective_from,
        working_days: workingDays?.length ? workingDays : [1, 2, 3, 4, 5],
      };
    }));
  } catch (err) {
    console.error('[assignments GET]', err);
    res.status(500).json({ error: 'Failed to fetch assignments' });
  }
});

// POST /api/assignments - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    const {
      employee_id,
      department_id,
      position_id,
      shift_id,
      effective_from,
      effective_to,
      is_active = true,
      remarks,
      attendance_policy_id,
    } = req.body;
    const hasPolicyChange = Object.prototype.hasOwnProperty.call(
      req.body || {},
      'attendance_policy_id'
    );
    if (!employee_id || !effective_from) {
      return res.status(400).json({ error: 'employee_id and effective_from are required' });
    }
    const ef = parseDate(effective_from);
    if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
    const et = effective_to != null && effective_to !== '' ? parseDate(effective_to) : null;
    if (effective_to != null && effective_to !== '' && !et) return res.status(400).json({ error: 'Invalid effective_to' });
    if (effectiveToBeforeFrom(ef, et)) {
      return res.status(400).json({ error: 'effective_to must be on or after effective_from' });
    }

    await client.query('BEGIN');
    try {
      const assignment = await createAssignmentTransition(client, {
        employeeId: employee_id,
        departmentId: department_id,
        positionId: position_id,
        shiftId: shift_id,
        effectiveFrom: ef,
        effectiveTo: et,
        isActive: is_active === true,
        remarks,
      });
      const policyAssignment = hasPolicyChange
        ? await upsertEmployeePolicyAssignment(client, {
            employeeId: employee_id,
            attendancePolicyId: attendance_policy_id,
            effectiveFrom: assignment.effective_from,
            effectiveTo: assignment.effective_to,
            isActive: assignment.is_active !== false,
          })
        : null;
      await client.query('COMMIT');
      res.status(201).json({
        ...assignment,
        policy_assignment: policyAssignment,
      });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    }
  } catch (err) {
    if (
      err instanceof AssignmentTransitionError ||
      err instanceof EmployeePolicyAssignmentError
    ) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '23P01') {
      return res.status(409).json({ error: 'Assignment dates overlap an existing assignment' });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid assignment selection' });
    }
    console.error('[assignments POST]', err);
    res.status(500).json({ error: 'Failed to create assignment' });
  } finally {
    client?.release();
  }
});

// PUT /api/assignments/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    const { id } = req.params;
    const {
      department_id,
      position_id,
      shift_id,
      effective_from,
      effective_to,
      is_active,
      remarks,
      change_reason,
      attendance_policy_id,
    } = req.body;
    const hasPolicyChange = Object.prototype.hasOwnProperty.call(
      req.body || {},
      'attendance_policy_id'
    );
    if (
      department_id === undefined &&
      position_id === undefined &&
      shift_id === undefined &&
      effective_from === undefined &&
      effective_to === undefined &&
      is_active === undefined &&
      remarks === undefined
    ) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    const parsedEffectiveFrom = effective_from === undefined
      ? undefined
      : parseDate(effective_from);
    if (effective_from !== undefined && !parsedEffectiveFrom) {
      return res.status(400).json({ error: 'Invalid effective_from' });
    }
    const parsedEffectiveTo = effective_to === undefined
      ? undefined
      : (effective_to === null || effective_to === '' ? null : parseDate(effective_to));
    if (effective_to !== undefined && effective_to !== null && effective_to !== '' && !parsedEffectiveTo) {
      return res.status(400).json({ error: 'Invalid effective_to' });
    }

    await client.query('BEGIN');
    try {
      const beforeResult = await client.query(
        `SELECT id, employee_id, department_id, position_id, shift_id,
                effective_from::text AS effective_from,
                effective_to::text AS effective_to, is_active, remarks
           FROM assignments
          WHERE id = $1::uuid`,
        [id]
      );
      if (beforeResult.rowCount === 0) {
        throw new AssignmentTransitionError('Assignment not found', 404);
      }
      const before = beforeResult.rows[0];
      const isDeactivating = is_active === false && before.is_active !== false;
      const deactivationReason = isDeactivating
        ? normalizeChangeReason(change_reason)
        : null;
      const assignment = await updateAssignmentTransition(client, {
        assignmentId: id,
        changes: {
          departmentId: department_id,
          positionId: position_id,
          shiftId: shift_id,
          effectiveFrom: parsedEffectiveFrom,
          effectiveTo: parsedEffectiveTo,
          isActive: is_active === undefined ? undefined : is_active === true,
          remarks,
        },
      });
      const shouldRepairPredecessor =
        isDeactivating ||
        (
          assignment.is_active !== false &&
          assignment.effective_from > before.effective_from
        );
      const restoredPredecessor = shouldRepairPredecessor
        ? await repairPrimaryPredecessorAfterFutureChange(client, {
            previousRecord: before,
            replacementRecord: assignment,
          })
        : null;
      const policyAssignment = hasPolicyChange
        ? await upsertEmployeePolicyAssignment(client, {
            employeeId: assignment.employee_id,
            attendancePolicyId: attendance_policy_id,
            effectiveFrom: assignment.effective_from,
            effectiveTo: assignment.effective_to,
            isActive: assignment.is_active !== false,
          })
        : null;
      if (isDeactivating) {
        await writeAssignmentHistoryAudit(client, {
          actorId: req.user?.id,
          recordType: 'primary',
          recordId: id,
          action: 'assignment_deactivated',
          reason: deactivationReason,
          before,
          after: assignment,
        });
      }
      if (restoredPredecessor) {
        await writeAssignmentHistoryAudit(client, {
          actorId: req.user?.id,
          recordType: 'primary',
          recordId: restoredPredecessor.after.id,
          action: 'assignment_predecessor_restored',
          reason:
            deactivationReason ||
            String(change_reason || '').trim() ||
            'Future assignment effective date changed',
          before: restoredPredecessor.before,
          after: restoredPredecessor.after,
        });
      }
      await client.query('COMMIT');
      res.json({
        ...assignment,
        policy_assignment: policyAssignment,
        predecessor_restored: restoredPredecessor?.after || null,
      });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    }
  } catch (err) {
    if (
      err instanceof AssignmentTransitionError ||
      err instanceof AssignmentHistoryError ||
      err instanceof EmployeePolicyAssignmentError
    ) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '23P01') {
      return res.status(409).json({ error: 'Assignment dates overlap an existing assignment' });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid assignment selection' });
    }
    console.error('[assignments PUT]', err);
    res.status(500).json({ error: 'Failed to update assignment' });
  } finally {
    client?.release();
  }
});

// DELETE /api/assignments/:id - archive without erasing history (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    try {
      const result = await deactivateAssignmentRecord(client, {
        actorId: req.user?.id,
        recordType: 'primary',
        recordId: req.params.id,
        reason: req.body?.reason,
      });
      await client.query('COMMIT');
      res.json({
        message: result.changed
          ? 'Assignment deactivated and retained in history'
          : 'Assignment is already inactive',
        assignment: result.record,
        predecessor_restored: result.restoredPredecessor?.after || null,
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } catch (err) {
    if (err instanceof AssignmentHistoryError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[assignments DELETE]', err);
    res.status(500).json({ error: 'Failed to deactivate assignment' });
  } finally {
    client?.release();
  }
});

// DELETE /api/assignments/:id/permanent - remove an unused future mistake only
router.delete('/:id/permanent', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    try {
      const result = await permanentlyDeleteFutureAssignment(client, {
        actorId: req.user?.id,
        recordType: 'primary',
        recordId: req.params.id,
        reason: req.body?.reason,
      });
      await client.query('COMMIT');
      res.json({
        message: 'Mistaken future assignment permanently deleted',
        restored_previous_assignment: result.restoredPredecessor?.after || null,
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } catch (err) {
    if (err instanceof AssignmentHistoryError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[assignments permanent DELETE]', err);
    res.status(500).json({ error: 'Failed to permanently delete assignment' });
  } finally {
    client?.release();
  }
});

module.exports = router;
