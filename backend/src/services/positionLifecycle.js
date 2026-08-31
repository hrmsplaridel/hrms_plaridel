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
  POSITION_DEPENDENCIES,
  PositionLifecycleError,
  cleanPositionDeleteReason,
  deleteMistakenPosition,
  ensurePositionDepartmentChangeAllowed,
  lockPositionForUpdate,
  positionAssignmentDependencyCounts,
  positionDependencyBlockers,
  positionDependencyCountsFromRow,
  positionDependencyCountsSql,
  writePositionAudit,
};
