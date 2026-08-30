'use strict';

class DepartmentLifecycleError extends Error {
  constructor(message, statusCode = 400, blockers = null) {
    super(message);
    this.name = 'DepartmentLifecycleError';
    this.statusCode = statusCode;
    this.blockers = blockers;
  }
}

const DEPARTMENT_DEPENDENCIES = Object.freeze([
  { key: 'positions', label: 'positions', table: 'positions', column: 'department_id' },
  { key: 'assignments', label: 'employee assignments', table: 'assignments', column: 'department_id' },
  { key: 'additional_positions', label: 'additional positions', table: 'employee_other_positions', column: 'department_id' },
  { key: 'policy_assignments', label: 'attendance policies', table: 'policy_assignments', column: 'department_id' },
  { key: 'leave_requests', label: 'leave requests', table: 'leave_requests', column: 'review_department_id' },
  { key: 'locator_slips', label: 'locator requests', table: 'locator_slips', column: 'department_id' },
  { key: 'workflow_steps', label: 'DocuTracker workflow steps', table: 'docutracker_workflow_steps', column: 'department_id' },
  { key: 'escalation_configs', label: 'DocuTracker escalation rules', table: 'docutracker_escalation_configs', column: 'department_id' },
]);

function cleanReason(value) {
  const reason = String(value || '').trim();
  if (!reason) {
    throw new DepartmentLifecycleError(
      'A reason is required to delete a mistaken department'
    );
  }
  if (reason.length > 1000) {
    throw new DepartmentLifecycleError(
      'Department deletion reason must not exceed 1000 characters'
    );
  }
  return reason;
}

function departmentDependencyCountsSql(departmentAlias = 'd') {
  return DEPARTMENT_DEPENDENCIES.map(
    ({ key, table, column }) =>
      `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = ${departmentAlias}.id) AS dependency_${key}`
  ).join(',\n       ');
}

function dependencyCountsFromRow(row = {}) {
  return Object.fromEntries(
    DEPARTMENT_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`dependency_${key}`] || 0),
    ])
  );
}

function dependencyBlockers(counts = {}) {
  return DEPARTMENT_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function dependencyMessage(blockers) {
  const details = blockers
    .map((item) => `${item.count} ${item.label}`)
    .join(', ');
  return `Department cannot be permanently deleted because it is used by ${details}`;
}

async function loadDepartmentDependencyCounts(db, departmentId) {
  const result = await db.query(
    `SELECT ${DEPARTMENT_DEPENDENCIES.map(
      ({ key, table, column }) =>
        `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = $1::uuid) AS dependency_${key}`
    ).join(',\n            ')}`,
    [departmentId]
  );
  return dependencyCountsFromRow(result.rows[0]);
}

async function deleteMistakenDepartment(
  db,
  { actorId, departmentId, reason }
) {
  const normalizedReason = cleanReason(reason);
  const existing = await db.query(
    `SELECT id, department_number, name, description, is_active,
            created_at, updated_at
       FROM departments
      WHERE id = $1::uuid
      FOR UPDATE`,
    [departmentId]
  );
  if (existing.rowCount === 0) {
    throw new DepartmentLifecycleError('Department not found', 404);
  }

  const department = existing.rows[0];
  const counts = await loadDepartmentDependencyCounts(db, departmentId);
  const blockers = dependencyBlockers(counts);
  if (blockers.length > 0) {
    throw new DepartmentLifecycleError(
      dependencyMessage(blockers),
      409,
      blockers
    );
  }

  await db.query('DELETE FROM departments WHERE id = $1::uuid', [departmentId]);
  await db.query(
    `INSERT INTO audit_logs (
       user_id, action, entity_type, entity_id, details
     ) VALUES ($1::uuid, 'department_mistake_deleted', 'department', $2::uuid, $3)`,
    [
      actorId || null,
      departmentId,
      JSON.stringify({ reason: normalizedReason, before: department }),
    ]
  );

  return { department, reason: normalizedReason };
}

module.exports = {
  DEPARTMENT_DEPENDENCIES,
  DepartmentLifecycleError,
  cleanReason,
  deleteMistakenDepartment,
  departmentDependencyCountsSql,
  dependencyBlockers,
  dependencyCountsFromRow,
  loadDepartmentDependencyCounts,
};
