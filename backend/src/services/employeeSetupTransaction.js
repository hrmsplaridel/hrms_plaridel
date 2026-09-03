const {
  AssignmentTransitionError,
  createAssignmentTransition,
  endEmployeeAssignmentsFromDate,
} = require('./assignmentTransition');
const {
  EmployeePolicyAssignmentError,
  upsertEmployeePolicyAssignment,
} = require('./employeePolicyAssignment');

class EmployeeSetupValidationError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'EmployeeSetupValidationError';
    this.statusCode = statusCode;
  }
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function cleanRequiredId(value, label) {
  const id = String(value || '').trim();
  if (!id) {
    throw new EmployeeSetupValidationError(`${label} is required`);
  }
  return id;
}

function normalizeDateOnly(value, label, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) {
      throw new EmployeeSetupValidationError(`${label} is required`);
    }
    return null;
  }

  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new EmployeeSetupValidationError(`${label} must use YYYY-MM-DD`);
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw new EmployeeSetupValidationError(`${label} is invalid`);
  }
  return text;
}

function normalizeEmployeeSetup(setup, defaults = {}) {
  if (setup === undefined) return null;
  if (setup === null || typeof setup !== 'object' || Array.isArray(setup)) {
    throw new EmployeeSetupValidationError('setup must be an object');
  }

  const hasAssignmentChange = hasOwn(setup, 'assignment');
  const hasPolicyChange = hasOwn(setup, 'policy_assignment');
  if (!hasAssignmentChange && !hasPolicyChange) return null;

  let assignment;
  if (hasAssignmentChange) {
    if (setup.assignment === null) {
      assignment = null;
    } else if (
      typeof setup.assignment === 'object' &&
      !Array.isArray(setup.assignment)
    ) {
      assignment = {
        departmentId: cleanRequiredId(
          setup.assignment.department_id,
          'Department'
        ),
        positionId: cleanRequiredId(setup.assignment.position_id, 'Position'),
        shiftId: cleanRequiredId(setup.assignment.shift_id, 'Shift'),
      };
    } else {
      throw new EmployeeSetupValidationError(
        'assignment must be an object or null'
      );
    }
  }

  let policyAssignment;
  if (hasPolicyChange) {
    if (setup.policy_assignment === null) {
      policyAssignment = null;
    } else if (
      typeof setup.policy_assignment === 'object' &&
      !Array.isArray(setup.policy_assignment)
    ) {
      policyAssignment = {
        attendancePolicyId: cleanRequiredId(
          setup.policy_assignment.attendance_policy_id,
          'Attendance policy'
        ),
      };
    } else {
      throw new EmployeeSetupValidationError(
        'policy_assignment must be an object or null'
      );
    }
  }

  const effectiveFrom = normalizeDateOnly(
    setup.effective_from ?? defaults.effectiveFrom,
    'Setup effective date',
    { required: true }
  );
  const effectiveTo = normalizeDateOnly(
    setup.effective_to ?? defaults.effectiveTo,
    'Setup end date'
  );
  if (effectiveTo && effectiveTo < effectiveFrom) {
    throw new EmployeeSetupValidationError(
      'Setup end date must be on or after its effective date'
    );
  }

  return {
    hasAssignmentChange,
    assignment,
    hasPolicyChange,
    policyAssignment,
    effectiveFrom,
    effectiveTo,
    isActive:
      setup.is_active === undefined
        ? defaults.isActive !== false
        : setup.is_active === true,
  };
}

async function validateSetupReferences(db, setup) {
  if (setup?.policyAssignment) {
    const result = await db.query(
      `SELECT 1
       FROM attendance_policies
       WHERE id = $1::uuid
       LIMIT 1`,
      [setup.policyAssignment.attendancePolicyId]
    );
    if (result.rowCount === 0) {
      throw new EmployeeSetupValidationError(
        'Selected attendance policy was not found'
      );
    }
  }
}

async function applyEmployeeSetup(db, { employeeId, setup, remarks }) {
  if (!setup) return { assignment: null, policyAssignment: null };
  await validateSetupReferences(db, setup);

  let assignment = null;
  if (setup.hasAssignmentChange) {
    if (setup.assignment) {
      try {
        assignment = await createAssignmentTransition(db, {
          employeeId,
          departmentId: setup.assignment.departmentId,
          positionId: setup.assignment.positionId,
          shiftId: setup.assignment.shiftId,
          effectiveFrom: setup.effectiveFrom,
          effectiveTo: setup.effectiveTo,
          isActive: setup.isActive,
          remarks,
        });
      } catch (error) {
        if (error instanceof AssignmentTransitionError) {
          throw new EmployeeSetupValidationError(
            error.message,
            error.statusCode
          );
        }
        throw error;
      }
    } else {
      await endEmployeeAssignmentsFromDate(db, {
        employeeId,
        effectiveFrom: setup.effectiveFrom,
      });
    }
  }

  let policyAssignment = null;
  if (setup.hasPolicyChange) {
    try {
      policyAssignment = await upsertEmployeePolicyAssignment(db, {
        employeeId,
        attendancePolicyId:
          setup.policyAssignment?.attendancePolicyId ?? null,
        effectiveFrom: setup.effectiveFrom,
        effectiveTo: setup.effectiveTo,
        isActive: setup.isActive,
      });
    } catch (error) {
      if (error instanceof EmployeePolicyAssignmentError) {
        throw new EmployeeSetupValidationError(
          error.message,
          error.statusCode
        );
      }
      throw error;
    }
  }

  return { assignment, policyAssignment };
}

module.exports = {
  EmployeeSetupValidationError,
  normalizeEmployeeSetup,
  validateSetupReferences,
  applyEmployeeSetup,
};
