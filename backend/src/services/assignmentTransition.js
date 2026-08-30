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

function cleanRequiredSelectionId(value, label) {
  const id = String(value || '').trim();
  if (!id) {
    throw new AssignmentTransitionError(`${label} is required`);
  }
  return id.toLowerCase();
}

async function validateAssignmentSelection(
  db,
  {
    employeeId,
    departmentId,
    positionId,
    shiftId,
    requireActiveReferences = true,
  }
) {
  const employee = cleanRequiredSelectionId(employeeId, 'Employee');
  const department = cleanRequiredSelectionId(departmentId, 'Department');
  const position = cleanRequiredSelectionId(positionId, 'Position');
  const shift = cleanRequiredSelectionId(shiftId, 'Shift');
  const result = await db.query(
    `SELECT
       (u.id IS NOT NULL) AS employee_exists,
       COALESCE(u.is_active, false) AS employee_is_active,
       COALESCE(u.employment_status, 'active') AS employee_status,
       u.date_hired::text AS employee_date_hired,
       u.separation_date::text AS employee_separation_date,
       (d.id IS NOT NULL) AS department_exists,
       COALESCE(d.is_active, false) AS department_is_active,
       (p.id IS NOT NULL) AS position_exists,
       COALESCE(p.is_active, false) AS position_is_active,
       COALESCE(p.is_department_head, false) AS position_is_department_head,
       p.department_id::text AS position_department_id,
       (s.id IS NOT NULL) AS shift_exists,
       COALESCE(s.is_active, false) AS shift_is_active
     FROM (SELECT 1) seed
     LEFT JOIN users u ON u.id = $1::uuid
     LEFT JOIN departments d ON d.id = $2::uuid
     LEFT JOIN positions p ON p.id = $3::uuid
     LEFT JOIN shifts s ON s.id = $4::uuid`,
    [employee, department, position, shift]
  );
  const row = result.rows[0] || {};
  if (!row.employee_exists) {
    throw new AssignmentTransitionError('Selected employee was not found');
  }
  if (!row.department_exists) {
    throw new AssignmentTransitionError('Selected department was not found');
  }
  if (!row.position_exists) {
    throw new AssignmentTransitionError('Selected position was not found');
  }
  if (String(row.position_department_id || '') !== department) {
    throw new AssignmentTransitionError(
      'Selected position does not belong to the selected department'
    );
  }
  if (!row.shift_exists) {
    throw new AssignmentTransitionError('Selected shift was not found');
  }
  if (requireActiveReferences) {
    if (
      !row.employee_is_active ||
      String(row.employee_status || 'active').toLowerCase() !== 'active'
    ) {
      throw new AssignmentTransitionError(
        'An active assignment requires an active employee account',
        409
      );
    }
    if (!row.department_is_active) {
      throw new AssignmentTransitionError(
        'Selected department is inactive',
        409
      );
    }
    if (!row.position_is_active) {
      throw new AssignmentTransitionError('Selected position is inactive', 409);
    }
    if (!row.shift_is_active) {
      throw new AssignmentTransitionError('Selected shift is inactive', 409);
    }
  }

  return {
    employeeId: employee,
    departmentId: department,
    positionId: position,
    shiftId: shift,
    employeeIsActive: row.employee_is_active === true,
    employeeStatus: String(row.employee_status || 'active').toLowerCase(),
    employeeDateHired: row.employee_date_hired || null,
    employeeSeparationDate: row.employee_separation_date || null,
    positionIsDepartmentHead: row.position_is_department_head === true,
  };
}

function validateEmployeeServiceCoverage(
  selection,
  { effectiveFrom, effectiveTo }
) {
  const hiredOn = selection.employeeDateHired;
  const separatedOn = selection.employeeSeparationDate;

  if (hiredOn && effectiveFrom < hiredOn) {
    throw new AssignmentTransitionError(
      `Assignment coverage cannot begin before the employee's hire date (${hiredOn})`,
      409
    );
  }

  if (separatedOn && (!effectiveTo || effectiveTo > separatedOn)) {
    throw new AssignmentTransitionError(
      `Assignment coverage cannot extend beyond the employee's separation date (${separatedOn})`,
      409
    );
  }

  const employeeIsActive =
    selection.employeeIsActive && selection.employeeStatus === 'active';
  if (!employeeIsActive && !separatedOn) {
    throw new AssignmentTransitionError(
      'Assignment coverage cannot be changed for an inactive employee without a separation date',
      409
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
  return updated.rows[0]
    ? { before: predecessor.rows[0], after: updated.rows[0] }
    : null;
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

async function assertNoOverlappingDepartmentHeadAssignment(
  db,
  {
    departmentId,
    positionId,
    effectiveFrom,
    effectiveTo,
    excludeAssignmentId = null,
    isDepartmentHead = null,
  }
) {
  if (isDepartmentHead === false) return;
  if (isDepartmentHead !== true) {
    const positionResult = await db.query(
      `SELECT is_department_head
       FROM positions
       WHERE id = $1::uuid
         AND department_id = $2::uuid`,
      [positionId, departmentId]
    );
    if (positionResult.rows[0]?.is_department_head !== true) return;
  }

  // Serialize Head changes by department before checking effective periods.
  await db.query(
    `SELECT id FROM departments WHERE id = $1::uuid FOR UPDATE`,
    [departmentId]
  );
  const conflict = await db.query(
    `SELECT a.id, a.employee_id,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to
     FROM assignments a
     JOIN positions p ON p.id = a.position_id
     WHERE a.department_id = $1::uuid
       AND p.is_department_head = true
       AND a.is_active = true
       AND a.effective_from <= COALESCE($3::date, 'infinity'::date)
       AND COALESCE(a.effective_to, 'infinity'::date) >= $2::date
       AND ($4::uuid IS NULL OR a.id <> $4::uuid)
     ORDER BY a.effective_from, a.created_at, a.id
     LIMIT 1
     FOR UPDATE OF a`,
    [departmentId, effectiveFrom, effectiveTo, excludeAssignmentId]
  );
  if (conflict.rowCount > 0) {
    throw new AssignmentTransitionError(
      'This department already has a Department Head assignment during the selected effective period',
      409
    );
  }
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
    includeTransition = false,
  }
) {
  const from = cleanDate(effectiveFrom, 'effective_from', { required: true });
  const to = cleanDate(effectiveTo, 'effective_to');
  validateRange(from, to);
  const selection = await validateAssignmentSelection(db, {
    employeeId,
    departmentId,
    positionId,
    shiftId,
    requireActiveReferences: isActive === true,
  });
  if (isActive) {
    validateEmployeeServiceCoverage(selection, {
      effectiveFrom: from,
      effectiveTo: to,
    });
  }

  let closedPredecessor = null;
  if (isActive) {
    closedPredecessor = await closeOverlappingPredecessor(db, {
      employeeId: selection.employeeId,
      effectiveFrom: from,
    });
    const conflict = await findOverlappingAssignment(db, {
      employeeId: selection.employeeId,
      effectiveFrom: from,
      effectiveTo: to,
    });
    if (conflict) {
      throw new AssignmentTransitionError(overlapMessage(conflict), 409);
    }
    await assertNoOverlappingDepartmentHeadAssignment(db, {
      departmentId: selection.departmentId,
      positionId: selection.positionId,
      effectiveFrom: from,
      effectiveTo: to,
      isDepartmentHead: selection.positionIsDepartmentHead,
    });
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
      selection.employeeId,
      selection.departmentId,
      selection.positionId,
      selection.shiftId,
      from,
      to,
      isActive === true,
      String(remarks || '').trim() || null,
    ]
  );
  const assignment = result.rows[0];
  return includeTransition ? { assignment, closedPredecessor } : assignment;
}

async function updateAssignmentTransition(
  db,
  { assignmentId, changes = {}, includeTransition = false }
) {
  const existingResult = await db.query(
    `SELECT id, employee_id, department_id, position_id, shift_id,
            (SELECT p.is_department_head FROM positions p
             WHERE p.id = assignments.position_id) AS position_is_department_head,
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
  const selection = {
    employeeId: existing.employee_id,
    departmentId:
      changes.departmentId === undefined
        ? existing.department_id
        : changes.departmentId,
    positionId:
      changes.positionId === undefined ? existing.position_id : changes.positionId,
    shiftId: changes.shiftId === undefined ? existing.shift_id : changes.shiftId,
  };
  const selectionChanged =
    changes.departmentId !== undefined ||
    changes.positionId !== undefined ||
    changes.shiftId !== undefined;
  const reactivating = existing.is_active === false && isActive;
  const coverageChanged =
    from !== existing.effective_from || to !== existing.effective_to;
  let validatedSelection = null;
  if (selectionChanged || reactivating) {
    validatedSelection = await validateAssignmentSelection(db, {
      ...selection,
      requireActiveReferences: isActive,
    });
  } else if (isActive && coverageChanged) {
    validatedSelection = await validateAssignmentSelection(db, {
      ...selection,
      requireActiveReferences: false,
    });
  } else if (isActive) {
    cleanRequiredSelectionId(selection.departmentId, 'Department');
    cleanRequiredSelectionId(selection.positionId, 'Position');
    cleanRequiredSelectionId(selection.shiftId, 'Shift');
  }
  if (isActive && validatedSelection) {
    validateEmployeeServiceCoverage(validatedSelection, {
      effectiveFrom: from,
      effectiveTo: to,
    });
  }

  let closedPredecessor = null;
  if (isActive) {
    closedPredecessor = await closeOverlappingPredecessor(db, {
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
    await assertNoOverlappingDepartmentHeadAssignment(db, {
      departmentId: selection.departmentId,
      positionId: selection.positionId,
      effectiveFrom: from,
      effectiveTo: to,
      excludeAssignmentId: assignmentId,
      isDepartmentHead: validatedSelection
        ? validatedSelection.positionIsDepartmentHead === true
        : existing.position_is_department_head === true,
    });
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
      selection.departmentId,
      selection.positionId,
      selection.shiftId,
      from,
      to,
      isActive,
      changes.remarks === undefined
        ? existing.remarks
        : String(changes.remarks || '').trim() || null,
    ]
  );
  const assignment = result.rows[0];
  return includeTransition ? { assignment, closedPredecessor } : assignment;
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
  validateAssignmentSelection,
  assertNoOverlappingDepartmentHeadAssignment,
  createAssignmentTransition,
  updateAssignmentTransition,
  endEmployeeAssignmentsFromDate,
};
