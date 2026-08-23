const PRIVILEGED_ASSIGNMENT_ROLES = new Set(['admin', 'hr', 'supervisor']);

function normalizeId(value) {
  const normalized = value == null ? '' : String(value).trim();
  return normalized || null;
}

function resolveAssignmentEmployeeAccess(user, requestedEmployeeId) {
  const requestedId = normalizeId(requestedEmployeeId);
  if (!requestedId) {
    return {
      allowed: false,
      statusCode: 400,
      error: 'employee_id is required',
      employeeId: null,
    };
  }

  if (PRIVILEGED_ASSIGNMENT_ROLES.has(user?.role)) {
    return {
      allowed: true,
      statusCode: 200,
      error: null,
      employeeId: requestedId,
    };
  }

  const authenticatedId = normalizeId(user?.id);
  if (!authenticatedId) {
    return {
      allowed: false,
      statusCode: 401,
      error: 'Authenticated employee id is required',
      employeeId: null,
    };
  }
  if (requestedId !== authenticatedId) {
    return {
      allowed: false,
      statusCode: 403,
      error: 'You can only view your own assignment',
      employeeId: null,
    };
  }

  return {
    allowed: true,
    statusCode: 200,
    error: null,
    employeeId: authenticatedId,
  };
}

module.exports = {
  resolveAssignmentEmployeeAccess,
};
