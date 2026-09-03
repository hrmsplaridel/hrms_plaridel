class AdditionalPositionTransitionError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AdditionalPositionTransitionError';
    this.statusCode = statusCode;
  }
}

function cleanRequiredId(value, label) {
  const id = String(value || '').trim().toLowerCase();
  if (!id) {
    throw new AdditionalPositionTransitionError(`${label} is required`);
  }
  return id;
}

function cleanDate(value, label, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) {
      throw new AdditionalPositionTransitionError(`${label} is required`);
    }
    return null;
  }
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new AdditionalPositionTransitionError(`${label} must use YYYY-MM-DD`);
  }
  const parsed = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  );
  if (
    parsed.getUTCFullYear() !== Number(match[1]) ||
    parsed.getUTCMonth() !== Number(match[2]) - 1 ||
    parsed.getUTCDate() !== Number(match[3])
  ) {
    throw new AdditionalPositionTransitionError(`${label} is invalid`);
  }
  return text;
}

function validateRange(effectiveFrom, effectiveTo) {
  if (effectiveTo && effectiveTo < effectiveFrom) {
    throw new AdditionalPositionTransitionError(
      'effective_to must be on or after effective_from'
    );
  }
}

function cleanRemarks(value) {
  const remarks = String(value || '').trim();
  if (remarks.length > 1000) {
    throw new AdditionalPositionTransitionError(
      'Remarks must not exceed 1000 characters'
    );
  }
  return remarks || null;
}

async function lockEmployeeAdditionalPositions(db, employeeId) {
  await db.query(
    `SELECT pg_advisory_xact_lock(hashtext($1))`,
    [`employee-other-position:${employeeId}`]
  );
}

async function validateAdditionalPositionSelection(
  db,
  { employeeId, departmentId, positionId, requireActiveReferences = true }
) {
  const employee = cleanRequiredId(employeeId, 'Employee');
  const department = cleanRequiredId(departmentId, 'Department');
  const position = cleanRequiredId(positionId, 'Position');
  const result = await db.query(
    `SELECT
       (u.id IS NOT NULL) AS employee_exists,
       COALESCE(u.is_active, false) AS employee_is_active,
       COALESCE(u.employment_status, 'active') AS employee_status,
       (d.id IS NOT NULL) AS department_exists,
       COALESCE(d.is_active, false) AS department_is_active,
       (p.id IS NOT NULL) AS position_exists,
       COALESCE(p.is_active, false) AS position_is_active,
       p.department_id::text AS position_department_id
     FROM (SELECT 1) seed
     LEFT JOIN users u ON u.id = $1::uuid
     LEFT JOIN departments d ON d.id = $2::uuid
     LEFT JOIN positions p ON p.id = $3::uuid`,
    [employee, department, position]
  );
  const row = result.rows[0] || {};
  if (!row.employee_exists) {
    throw new AdditionalPositionTransitionError('Selected employee was not found');
  }
  if (!row.department_exists) {
    throw new AdditionalPositionTransitionError('Selected department was not found');
  }
  if (!row.position_exists) {
    throw new AdditionalPositionTransitionError('Selected position was not found');
  }
  if (String(row.position_department_id || '') !== department) {
    throw new AdditionalPositionTransitionError(
      'Selected position does not belong to the selected department'
    );
  }
  if (requireActiveReferences) {
    if (
      !row.employee_is_active ||
      String(row.employee_status || 'active').toLowerCase() !== 'active'
    ) {
      throw new AdditionalPositionTransitionError(
        'An active additional position requires an active employee account',
        409
      );
    }
    if (!row.department_is_active) {
      throw new AdditionalPositionTransitionError(
        'Selected department is inactive',
        409
      );
    }
    if (!row.position_is_active) {
      throw new AdditionalPositionTransitionError(
        'Selected position is inactive',
        409
      );
    }
  }
  return { employeeId: employee, departmentId: department, positionId: position };
}

async function assertNoDuplicateAdditionalPositionOverlap(
  db,
  {
    employeeId,
    departmentId,
    positionId,
    effectiveFrom,
    effectiveTo,
    excludeId = null,
  }
) {
  const result = await db.query(
    `SELECT id
       FROM employee_other_positions
      WHERE employee_id = $1::uuid
        AND department_id = $2::uuid
        AND position_id = $3::uuid
        AND is_active = true
        AND effective_from <= COALESCE($5::date, 'infinity'::date)
        AND COALESCE(effective_to, 'infinity'::date) >= $4::date
        AND ($6::uuid IS NULL OR id <> $6::uuid)
      LIMIT 1`,
    [employeeId, departmentId, positionId, effectiveFrom, effectiveTo, excludeId]
  );
  if (result.rowCount > 0) {
    throw new AdditionalPositionTransitionError(
      'This employee already has the same additional position for an overlapping period',
      409
    );
  }
}

async function createAdditionalPositionTransition(
  db,
  {
    employeeId,
    departmentId,
    positionId,
    effectiveFrom,
    effectiveTo = null,
    isActive = true,
    remarks = null,
    createdBy = null,
  }
) {
  const employee = cleanRequiredId(employeeId, 'Employee');
  const department = cleanRequiredId(departmentId, 'Department');
  const position = cleanRequiredId(positionId, 'Position');
  const from = cleanDate(effectiveFrom, 'effective_from', { required: true });
  const to = cleanDate(effectiveTo, 'effective_to');
  validateRange(from, to);
  await lockEmployeeAdditionalPositions(db, employee);
  await validateAdditionalPositionSelection(db, {
    employeeId: employee,
    departmentId: department,
    positionId: position,
    requireActiveReferences: isActive !== false,
  });
  if (isActive !== false) {
    await assertNoDuplicateAdditionalPositionOverlap(db, {
      employeeId: employee,
      departmentId: department,
      positionId: position,
      effectiveFrom: from,
      effectiveTo: to,
    });
  }
  const result = await db.query(
    `INSERT INTO employee_other_positions (
       employee_id, department_id, position_id,
       effective_from, effective_to, is_active, remarks, created_by
     ) VALUES ($1::uuid, $2::uuid, $3::uuid, $4::date, $5::date, $6, $7, $8::uuid)
     RETURNING id, employee_id, department_id, position_id,
               effective_from::text AS effective_from,
               effective_to::text AS effective_to, is_active, remarks,
               created_at, updated_at`,
    [
      employee,
      department,
      position,
      from,
      to,
      isActive !== false,
      cleanRemarks(remarks),
      createdBy || null,
    ]
  );
  return result.rows[0];
}

async function updateAdditionalPositionTransition(db, { id, changes = {} }) {
  const recordId = cleanRequiredId(id, 'Additional position');
  const existing = await db.query(
    `SELECT id, employee_id, department_id, position_id,
            effective_from::text AS effective_from,
            effective_to::text AS effective_to, is_active, remarks,
            created_at, updated_at
       FROM employee_other_positions
      WHERE id = $1::uuid
      FOR UPDATE`,
    [recordId]
  );
  if (existing.rowCount === 0) {
    throw new AdditionalPositionTransitionError('Employee other position not found', 404);
  }
  const before = existing.rows[0];
  const department = changes.departmentId === undefined
    ? before.department_id
    : cleanRequiredId(changes.departmentId, 'Department');
  const position = changes.positionId === undefined
    ? before.position_id
    : cleanRequiredId(changes.positionId, 'Position');
  const from = changes.effectiveFrom === undefined
    ? cleanDate(before.effective_from, 'effective_from', { required: true })
    : cleanDate(changes.effectiveFrom, 'effective_from', { required: true });
  const to = changes.effectiveTo === undefined
    ? cleanDate(before.effective_to, 'effective_to')
    : cleanDate(changes.effectiveTo, 'effective_to');
  const active = changes.isActive === undefined ? before.is_active !== false : changes.isActive !== false;
  const remarks = changes.remarks === undefined ? before.remarks : changes.remarks;
  validateRange(from, to);
  await lockEmployeeAdditionalPositions(db, before.employee_id);
  await validateAdditionalPositionSelection(db, {
    employeeId: before.employee_id,
    departmentId: department,
    positionId: position,
    requireActiveReferences: active,
  });
  if (active) {
    await assertNoDuplicateAdditionalPositionOverlap(db, {
      employeeId: before.employee_id,
      departmentId: department,
      positionId: position,
      effectiveFrom: from,
      effectiveTo: to,
      excludeId: recordId,
    });
  }
  const updated = await db.query(
    `UPDATE employee_other_positions
        SET department_id = $2::uuid,
            position_id = $3::uuid,
            effective_from = $4::date,
            effective_to = $5::date,
            is_active = $6,
            remarks = $7,
            updated_at = now()
      WHERE id = $1::uuid
      RETURNING id, employee_id, department_id, position_id,
                effective_from::text AS effective_from,
                effective_to::text AS effective_to, is_active, remarks,
                created_at, updated_at`,
    [recordId, department, position, from, to, active, cleanRemarks(remarks)]
  );
  return { before, after: updated.rows[0] };
}

module.exports = {
  AdditionalPositionTransitionError,
  assertNoDuplicateAdditionalPositionOverlap,
  createAdditionalPositionTransition,
  updateAdditionalPositionTransition,
  validateAdditionalPositionSelection,
};
