const { addDays } = require('../utils/dateRangeParser');

class AssignmentTransitionError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AssignmentTransitionError';
    this.statusCode = statusCode;
  }
}

function cleanDate(value, label, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) throw new AssignmentTransitionError(`${label} is required`);
    return null;
  }
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new AssignmentTransitionError(`${label} must use YYYY-MM-DD`);
  }
  const parsed = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  );
  if (
    parsed.getUTCFullYear() !== Number(match[1]) ||
    parsed.getUTCMonth() !== Number(match[2]) - 1 ||
    parsed.getUTCDate() !== Number(match[3])
  ) {
    throw new AssignmentTransitionError(`${label} is invalid`);
  }
  return text;
}

function validateRange(effectiveFrom, effectiveTo) {
  if (effectiveTo && effectiveTo < effectiveFrom) {
    throw new AssignmentTransitionError(
      'effective_to must be on or after effective_from'
    );
  }
}

async function closeOverlappingPredecessor(
  db,
  { employeeId, effectiveFrom, excludeAssignmentId = null }
) {
  const predecessor = await db.query(
    `SELECT id, effective_from::text AS effective_from,
            effective_to::text AS effective_to
     FROM assignments
     WHERE employee_id = $1::uuid
       AND is_active = true
       AND effective_from < $2::date
       AND (effective_to IS NULL OR effective_to >= $2::date)
       AND ($3::uuid IS NULL OR id <> $3::uuid)
     ORDER BY effective_from DESC, created_at DESC, id DESC
     LIMIT 1
     FOR UPDATE`,
    [employeeId, effectiveFrom, excludeAssignmentId]
  );
  if (predecessor.rowCount === 0) return null;

  const previousDay = addDays(effectiveFrom, -1);
  const updated = await db.query(
    `UPDATE assignments
     SET effective_to = $2::date,
         updated_at = now()
     WHERE id = $1::uuid
     RETURNING id, effective_from::text AS effective_from,
               effective_to::text AS effective_to, is_active`,
    [predecessor.rows[0].id, previousDay]
  );
  return updated.rows[0] || null;
}

async function findOverlappingAssignment(
  db,
  { employeeId, effectiveFrom, effectiveTo, excludeAssignmentId = null }
) {
  const result = await db.query(
    `SELECT id, effective_from::text AS effective_from,
            effective_to::text AS effective_to
     FROM assignments
     WHERE employee_id = $1::uuid
       AND is_active = true
       AND effective_from <= COALESCE($3::date, 'infinity'::date)
       AND COALESCE(effective_to, 'infinity'::date) >= $2::date
       AND ($4::uuid IS NULL OR id <> $4::uuid)
     ORDER BY effective_from, created_at, id
     LIMIT 1
     FOR UPDATE`,
    [employeeId, effectiveFrom, effectiveTo, excludeAssignmentId]
  );
  return result.rows[0] || null;
}

function overlapMessage(row) {
  const range = row?.effective_to
    ? `${row.effective_from} to ${row.effective_to}`
    : `${row?.effective_from || 'the selected date'} onward`;
  return `Assignment dates overlap an existing assignment effective ${range}`;
}

async function createAssignmentTransition(
  db,
  {
    employeeId,
    departmentId,
    positionId,
    shiftId,
    effectiveFrom,
    effectiveTo = null,
    isActive = true,
    remarks = null,
  }
) {
  const from = cleanDate(effectiveFrom, 'effective_from', { required: true });
  const to = cleanDate(effectiveTo, 'effective_to');
  validateRange(from, to);

  if (isActive) {
    await closeOverlappingPredecessor(db, {
      employeeId,
      effectiveFrom: from,
    });
    const conflict = await findOverlappingAssignment(db, {
      employeeId,
      effectiveFrom: from,
      effectiveTo: to,
    });
    if (conflict) {
      throw new AssignmentTransitionError(overlapMessage(conflict), 409);
    }
  }

  const result = await db.query(
    `INSERT INTO assignments (
       employee_id, department_id, position_id, shift_id,
       effective_from, effective_to, is_active, remarks
     )
     VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid,
             $5::date, $6::date, $7, $8)
     RETURNING id, employee_id, department_id, position_id, shift_id,
               effective_from::text AS effective_from,
               effective_to::text AS effective_to, is_active, remarks`,
    [
      employeeId,
      departmentId || null,
      positionId || null,
      shiftId || null,
      from,
      to,
      isActive === true,
      String(remarks || '').trim() || null,
    ]
  );
  return result.rows[0];
}

async function updateAssignmentTransition(db, { assignmentId, changes = {} }) {
  const existingResult = await db.query(
    `SELECT id, employee_id, department_id, position_id, shift_id,
            effective_from::text AS effective_from,
            effective_to::text AS effective_to, is_active, remarks
     FROM assignments
     WHERE id = $1::uuid
     FOR UPDATE`,
    [assignmentId]
  );
  if (existingResult.rowCount === 0) {
    throw new AssignmentTransitionError('Assignment not found', 404);
  }
  const existing = existingResult.rows[0];

  const from = cleanDate(
    changes.effectiveFrom === undefined
      ? existing.effective_from
      : changes.effectiveFrom,
    'effective_from',
    { required: true }
  );
  const to = cleanDate(
    changes.effectiveTo === undefined ? existing.effective_to : changes.effectiveTo,
    'effective_to'
  );
  validateRange(from, to);
  const isActive = changes.isActive === undefined
    ? existing.is_active !== false
    : changes.isActive === true;

  if (isActive) {
    await closeOverlappingPredecessor(db, {
      employeeId: existing.employee_id,
      effectiveFrom: from,
      excludeAssignmentId: assignmentId,
    });
    const conflict = await findOverlappingAssignment(db, {
      employeeId: existing.employee_id,
      effectiveFrom: from,
      effectiveTo: to,
      excludeAssignmentId: assignmentId,
    });
    if (conflict) {
      throw new AssignmentTransitionError(overlapMessage(conflict), 409);
    }
  }

  const result = await db.query(
    `UPDATE assignments
     SET department_id = $2::uuid,
         position_id = $3::uuid,
         shift_id = $4::uuid,
         effective_from = $5::date,
         effective_to = $6::date,
         is_active = $7,
         remarks = $8,
         updated_at = now()
     WHERE id = $1::uuid
     RETURNING id, employee_id, department_id, position_id, shift_id,
               effective_from::text AS effective_from,
               effective_to::text AS effective_to, is_active, remarks`,
    [
      assignmentId,
      changes.departmentId === undefined
        ? existing.department_id
        : changes.departmentId || null,
      changes.positionId === undefined
        ? existing.position_id
        : changes.positionId || null,
      changes.shiftId === undefined ? existing.shift_id : changes.shiftId || null,
      from,
      to,
      isActive,
      changes.remarks === undefined
        ? existing.remarks
        : String(changes.remarks || '').trim() || null,
    ]
  );
  return result.rows[0];
}

async function endEmployeeAssignmentsFromDate(db, { employeeId, effectiveFrom }) {
  const from = cleanDate(effectiveFrom, 'effective_from', { required: true });
  const previousDay = addDays(from, -1);
  await db.query(
    `SELECT id
     FROM assignments
     WHERE employee_id = $1::uuid
       AND is_active = true
     FOR UPDATE`,
    [employeeId]
  );
  await db.query(
    `UPDATE assignments
     SET is_active = false,
         updated_at = now()
     WHERE employee_id = $1::uuid
       AND is_active = true
       AND effective_from >= $2::date`,
    [employeeId, from]
  );
  await db.query(
    `UPDATE assignments
     SET effective_to = $3::date,
         updated_at = now()
     WHERE employee_id = $1::uuid
       AND is_active = true
       AND effective_from < $2::date
       AND (effective_to IS NULL OR effective_to >= $2::date)`,
    [employeeId, from, previousDay]
  );
}

module.exports = {
  AssignmentTransitionError,
  createAssignmentTransition,
  updateAssignmentTransition,
  endEmployeeAssignmentsFromDate,
};
