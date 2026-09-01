'use strict';

class PositionLifecycleError extends Error {
  constructor(message, statusCode = 409, details = null) {
    super(message);
    this.name = 'PositionLifecycleError';
    this.statusCode = statusCode;
    this.details = details;
  }
}

const POSITION_DEPENDENCIES = Object.freeze([
  {
    key: 'primary_assignments',
    label: 'primary assignments',
    table: 'assignments',
    column: 'position_id',
  },
  {
    key: 'additional_positions',
    label: 'additional positions',
    table: 'employee_other_positions',
    column: 'position_id',
  },
]);

const POSITION_DEACTIVATION_DEPENDENCIES = Object.freeze([
  { key: 'primary_assignments', label: 'current or future primary assignments' },
  { key: 'additional_positions', label: 'current or future additional positions' },
  { key: 'department_head_periods', label: 'current or future Department Head designations' },
]);

function nullableId(value) {
  if (value === null || value === undefined || value === '') return null;
  return String(value);
}

async function lockPositionForUpdate(db, positionId) {
  const result = await db.query(
    `SELECT id, position_number, name, description, department_id,
            is_department_head, is_active
       FROM positions
      WHERE id = $1::uuid
      FOR UPDATE`,
    [positionId]
  );
  return result.rows[0] || null;
}

function positionDependencyCountsSql(positionAlias = 'p') {
  return POSITION_DEPENDENCIES.map(
    ({ key, table, column }) =>
      `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = ${positionAlias}.id) AS dependency_${key}`
  ).join(',\n       ');
}

function positionDeactivationCountsSql(positionIdExpression = 'p.id', todayPlaceholder = '$1') {
  return `(
            SELECT COUNT(*)::int
            FROM assignments a
            WHERE a.position_id = ${positionIdExpression}
              AND a.is_active = true
              AND (a.effective_to IS NULL OR a.effective_to >= ${todayPlaceholder}::date)
          ) AS deactivation_primary_assignments,
          (
            SELECT COUNT(*)::int
            FROM employee_other_positions other_position
            WHERE other_position.position_id = ${positionIdExpression}
              AND other_position.is_active = true
              AND (
                other_position.effective_to IS NULL
                OR other_position.effective_to >= ${todayPlaceholder}::date
              )
          ) AS deactivation_additional_positions,
          (
            SELECT COUNT(*)::int
            FROM position_department_head_periods head_period
            WHERE head_period.position_id = ${positionIdExpression}
              AND head_period.is_active = true
              AND (
                head_period.effective_to IS NULL
                OR head_period.effective_to >= ${todayPlaceholder}::date
              )
          ) AS deactivation_department_head_periods`;
}

function positionDependencyCountsFromRow(row = {}) {
  return Object.fromEntries(
    POSITION_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`dependency_${key}`] || 0),
    ])
  );
}

function positionDependencyBlockers(counts = {}) {
  return POSITION_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function positionDeactivationCountsFromRow(row = {}) {
  return Object.fromEntries(
    POSITION_DEACTIVATION_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`deactivation_${key}`] || 0),
    ])
  );
}

function positionDeactivationBlockers(counts = {}) {
  return POSITION_DEACTIVATION_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function cleanPositionDeleteReason(value) {
  const reason = String(value || '').trim();
  if (!reason) {
    throw new PositionLifecycleError(
      'A reason is required to delete a mistaken position',
      400
    );
  }
  if (reason.length > 1000) {
    throw new PositionLifecycleError(
      'Position deletion reason must not exceed 1000 characters',
      400
    );
  }
  return reason;
}

async function writePositionAudit(
  db,
  { actorId, action, positionId, before = null, after = null, reason = null }
) {
  await db.query(
    `INSERT INTO audit_logs (
       user_id, action, entity_type, entity_id, details
     ) VALUES ($1::uuid, $2, 'position', $3::uuid, $4)`,
    [
      actorId || null,
      action,
      positionId,
      JSON.stringify({ reason, before, after }),
    ]
  );
}

async function positionAssignmentDependencyCounts(db, positionId) {
  const result = await db.query(
    `SELECT ${POSITION_DEPENDENCIES.map(
      ({ key, table, column }) =>
        `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = $1::uuid) AS dependency_${key}`
    ).join(',\n            ')}`,
    [positionId]
  );
  return positionDependencyCountsFromRow(result.rows[0]);
}

async function ensurePositionDeactivationAllowed(
  db,
  { positionId, effectiveDate, lockedPosition = null }
) {
  const position = lockedPosition || await lockPositionForUpdate(db, positionId);
  if (!position) {
    throw new PositionLifecycleError('Position not found', 404);
  }
  const result = await db.query(
    `SELECT ${positionDeactivationCountsSql('$1::uuid', '$2')}`,
    [positionId, effectiveDate]
  );
  const dependencies = positionDeactivationCountsFromRow(result.rows[0]);
  const blockers = positionDeactivationBlockers(dependencies);
  if (blockers.length > 0) {
    const details = blockers
      .map((item) => `${item.count} ${item.label}`)
      .join(', ');
    throw new PositionLifecycleError(
      `Position cannot be deactivated because it has ${details}. End or transfer these periods first.`,
      409,
      { blockers, dependencies, official_date: effectiveDate }
    );
  }
  return position;
}

async function ensureActivePositionDepartmentAllowed(
  db,
  { departmentId, positionIsActive }
) {
  const normalizedDepartmentId = nullableId(departmentId);
  if (!positionIsActive || normalizedDepartmentId === null) return null;

  const result = await db.query(
    `SELECT id, name, is_active
       FROM departments
      WHERE id = $1::uuid
      FOR SHARE`,
    [normalizedDepartmentId]
  );
  const department = result.rows[0] || null;
  if (!department) {
    throw new PositionLifecycleError('Selected department not found', 400);
  }
  if (department.is_active !== true) {
    throw new PositionLifecycleError(
      `Active positions cannot be assigned to the inactive ${department.name || 'selected'} department. Reactivate the department or select an active department.`,
      409,
      {
        department_id: normalizedDepartmentId,
        department_name: department.name || null,
      }
    );
  }
  return department;
}

async function ensurePositionDepartmentChangeAllowed(
  db,
  { positionId, nextDepartmentId }
) {
  const position = await lockPositionForUpdate(db, positionId);
  if (!position) {
    throw new PositionLifecycleError('Position not found', 404);
  }

  const currentDepartmentId = nullableId(position.department_id);
  const normalizedNextDepartmentId = nullableId(nextDepartmentId);
  if (currentDepartmentId === normalizedNextDepartmentId) return position;

  const dependencies = await positionAssignmentDependencyCounts(db, positionId);
  if (dependencies.primary_assignments > 0 || dependencies.additional_positions > 0) {
    throw new PositionLifecycleError(
      'This position has assignment history and cannot be moved to another department. Create a new position and use Assignment Management to transfer employees.',
      409,
      { dependencies }
    );
  }

  return position;
}

async function deleteMistakenPosition(
  db,
  { actorId, positionId, reason }
) {
  const normalizedReason = cleanPositionDeleteReason(reason);
  const position = await lockPositionForUpdate(db, positionId);
  if (!position) {
    throw new PositionLifecycleError('Position not found', 404);
  }

  const counts = await positionAssignmentDependencyCounts(db, positionId);
  const blockers = positionDependencyBlockers(counts);
  if (blockers.length > 0) {
    const details = blockers
      .map((item) => `${item.count} ${item.label}`)
      .join(', ');
    throw new PositionLifecycleError(
      `Position cannot be permanently deleted because it is used by ${details}`,
      409,
      { blockers }
    );
  }

  await db.query('DELETE FROM positions WHERE id = $1::uuid', [positionId]);
  await writePositionAudit(db, {
    actorId,
    action: 'position_mistake_deleted',
    positionId,
    before: position,
    reason: normalizedReason,
  });

  return { position, reason: normalizedReason };
}

module.exports = {
  POSITION_DEACTIVATION_DEPENDENCIES,
  POSITION_DEPENDENCIES,
  PositionLifecycleError,
  cleanPositionDeleteReason,
  deleteMistakenPosition,
  ensureActivePositionDepartmentAllowed,
  ensurePositionDeactivationAllowed,
  ensurePositionDepartmentChangeAllowed,
  lockPositionForUpdate,
  positionAssignmentDependencyCounts,
  positionDependencyBlockers,
  positionDependencyCountsFromRow,
  positionDependencyCountsSql,
  positionDeactivationBlockers,
  positionDeactivationCountsFromRow,
  positionDeactivationCountsSql,
  writePositionAudit,
};
