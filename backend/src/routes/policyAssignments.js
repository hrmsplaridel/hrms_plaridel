const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  EmployeePolicyAssignmentError,
  upsertEmployeePolicyAssignment,
} = require('../services/employeePolicyAssignment');
const { writeAssignmentHistoryAudit } = require('../services/assignmentHistory');
const {
  queueAssignmentReconciliation,
  rebuildAfterAssignmentCommit,
} = require('../services/assignmentReconciliation');

const router = express.Router();
const protect = [authMiddleware];

function parseDate(val) {
  if (!val) return null;
  const d = new Date(val);
  return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

// GET /api/policy-assignments?employee_id=uuid&status=Active|Inactive|All
router.get('/', protect, async (req, res) => {
  try {
    const employeeId = req.query.employee_id;
    if (!employeeId) return res.status(400).json({ error: 'employee_id is required' });
    const status = req.query.status || 'Active';
    let statusWhere = '';
    if (status === 'Active') statusWhere = 'AND (pa.is_active IS NULL OR pa.is_active = true)';
    else if (status === 'Inactive') statusWhere = 'AND pa.is_active = false';

    const result = await pool.query(
      `SELECT pa.id, pa.attendance_policy_id, pa.employee_id, pa.department_id, pa.shift_id,
              pa.effective_from, pa.effective_to, pa.is_active,
              p.name AS policy_name
       FROM policy_assignments pa
       JOIN attendance_policies p ON p.id = pa.attendance_policy_id
       WHERE pa.employee_id = $1 ${statusWhere}
       ORDER BY pa.effective_from DESC, pa.created_at DESC`,
      [employeeId]
    );

    res.json(
      result.rows.map((r) => ({
        id: r.id,
        attendance_policy_id: r.attendance_policy_id,
        employee_id: r.employee_id,
        department_id: r.department_id,
        shift_id: r.shift_id,
        effective_from: r.effective_from,
        effective_to: r.effective_to,
        is_active: r.is_active ?? true,
        policy_name: r.policy_name,
      }))
    );
  } catch (err) {
    console.error('[policy-assignments GET]', err);
    res.status(500).json({ error: 'Failed to fetch policy assignments' });
  }
});

// POST /api/policy-assignments/employee-upsert (admin only)
// Upsert employee-level policy assignment for a date range.
// If attendance_policy_id is null, deactivates overlapping employee-level policy assignments.
router.post('/employee-upsert', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    const {
      employee_id,
      attendance_policy_id,
      effective_from,
      effective_to,
      is_active = true,
    } = req.body || {};

    if (!employee_id || !effective_from) {
      return res.status(400).json({ error: 'employee_id and effective_from are required' });
    }
    const ef = parseDate(effective_from);
    if (!ef) return res.status(400).json({ error: 'Invalid effective_from' });
    const et = effective_to != null && effective_to !== '' ? parseDate(effective_to) : null;
    if (effective_to != null && effective_to !== '' && !et) {
      return res.status(400).json({ error: 'Invalid effective_to' });
    }
    if (ef != null && et != null && et < ef) {
      return res.status(400).json({ error: 'effective_to must be on or after effective_from' });
    }

    client = await pool.connect();
    await client.query('BEGIN');
    try {
      const transition = await upsertEmployeePolicyAssignment(client, {
        employeeId: employee_id,
        attendancePolicyId: attendance_policy_id,
        effectiveFrom: ef,
        effectiveTo: et,
        isActive: !!is_active,
        includeTransition: true,
      });
      const policyAssignment = transition.assignment;
      await writeAssignmentHistoryAudit(client, {
        actorId: req.user?.id,
        recordType: 'policy',
        recordId: policyAssignment?.id || transition.before[0]?.id || null,
        action: 'employee_policy_assignment_updated',
        reason: policyAssignment
          ? 'Employee attendance policy period saved'
          : 'Employee attendance policy removed for selected period',
        before: transition.before,
        after: transition.after,
      });
      const queued = await queueAssignmentReconciliation(client, {
        employeeId: employee_id,
        before: null,
        after: { effective_from: ef, effective_to: et },
        reason: 'employee_policy_assignment_updated',
        metadata: { policy_assignment_id: policyAssignment?.id || null },
      });
      await client.query('COMMIT');
      const reconciliation = await rebuildAfterAssignmentCommit(employee_id, queued);
      res.status(policyAssignment ? 201 : 200).json({
        policy_assignment: policyAssignment,
        reconciliation,
      });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    }
  } catch (err) {
    if (err instanceof EmployeePolicyAssignmentError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('[policy-assignments employee-upsert POST]', err);
    res.status(500).json({ error: 'Failed to upsert employee policy assignment' });
  } finally {
    client?.release();
  }
});

module.exports = router;
