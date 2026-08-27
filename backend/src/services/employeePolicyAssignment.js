'use strict';

class EmployeePolicyAssignmentError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'EmployeePolicyAssignmentError';
    this.statusCode = statusCode;
  }
}

function cleanDate(value, label, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) throw new EmployeePolicyAssignmentError(`${label} is required`);
    return null;
  }
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new EmployeePolicyAssignmentError(`${label} must use YYYY-MM-DD`);
  }
  const parsed = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  );
  if (
    parsed.getUTCFullYear() !== Number(match[1]) ||
    parsed.getUTCMonth() !== Number(match[2]) - 1 ||
    parsed.getUTCDate() !== Number(match[3])
  ) {
    throw new EmployeePolicyAssignmentError(`${label} is invalid`);
  }
  return text;
}

async function upsertEmployeePolicyAssignment(
  db,
  {
    employeeId,
    attendancePolicyId,
    effectiveFrom,
    effectiveTo = null,
    isActive = true,
  }
) {
  const employee = String(employeeId || '').trim();
  if (!employee) {
    throw new EmployeePolicyAssignmentError('employee_id is required');
  }
  const from = cleanDate(effectiveFrom, 'effective_from', { required: true });
  const to = cleanDate(effectiveTo, 'effective_to');
  if (to && to < from) {
    throw new EmployeePolicyAssignmentError(
      'effective_to must be on or after effective_from'
    );
  }

  await db.query(
    `UPDATE policy_assignments
     SET is_active = false,
         effective_to = COALESCE(effective_to, $2::date),
         updated_at = now()
     WHERE employee_id = $1::uuid
       AND department_id IS NULL
       AND shift_id IS NULL
       AND (is_active IS NULL OR is_active = true)
       AND effective_from <= COALESCE($3::date, '9999-12-31'::date)
       AND COALESCE(effective_to, '9999-12-31'::date) >= $2::date`,
    [employee, from, to]
  );

  const policyId = attendancePolicyId == null
    ? null
    : String(attendancePolicyId).trim() || null;
  if (!policyId) return null;

  const inserted = await db.query(
    `INSERT INTO policy_assignments (
       attendance_policy_id, employee_id, department_id, shift_id,
       effective_from, effective_to, is_active
     )
     VALUES ($1::uuid, $2::uuid, NULL, NULL, $3::date, $4::date, $5)
     RETURNING id, attendance_policy_id, employee_id,
               effective_from::text AS effective_from,
               effective_to::text AS effective_to, is_active`,
    [policyId, employee, from, to, isActive === true]
  );
  return inserted.rows[0] || null;
}

module.exports = {
  EmployeePolicyAssignmentError,
  upsertEmployeePolicyAssignment,
};
