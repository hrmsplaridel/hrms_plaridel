const ORGANIZATION_ASSIGNMENT_ROLES = new Set(['admin', 'hr']);

function normalizeId(value) {
  const normalized = value == null ? '' : String(value).trim();
  return normalized || null;
}

function normalizeRole(value) {
  return String(value || '').trim().toLowerCase();
}

function denied(statusCode, error) {
  return {
    allowed: false,
    statusCode,
    error,
    employeeId: null,
    scope: 'denied',
    requesterId: null,
  };
}

function resolveAssignmentEmployeeAccess(
  user,
  requestedEmployeeId,
  { allowDirectorySearch = false } = {}
) {
  const requestedId = normalizeId(requestedEmployeeId);
  const authenticatedId = normalizeId(user?.id);
  const role = normalizeRole(user?.role);

  if (!authenticatedId) {
    return denied(401, 'Authenticated employee id is required');
  }
  if (!requestedId && !allowDirectorySearch) {
    return denied(400, 'employee_id is required');
  }
  if (ORGANIZATION_ASSIGNMENT_ROLES.has(role)) {
    return {
      allowed: true,
      statusCode: 200,
      error: null,
      employeeId: requestedId,
      scope: 'organization',
      requesterId: authenticatedId,
    };
  }
  if (requestedId && requestedId === authenticatedId) {
    return {
      allowed: true,
      statusCode: 200,
      error: null,
      employeeId: authenticatedId,
      scope: 'self',
      requesterId: authenticatedId,
    };
  }
  if (role === 'supervisor') {
    return {
      allowed: true,
      statusCode: 200,
      error: null,
      employeeId: requestedId,
      scope: 'supervised_departments',
      requesterId: authenticatedId,
    };
  }
  if (!requestedId && allowDirectorySearch) {
    return denied(403, 'Employee directory assignment search is restricted');
  }
  return denied(403, 'You can only view your own assignment records');
}

function dateText(value, fallback) {
  if (value == null || value === '') return fallback;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : fallback;
}

function recordRange(row) {
  return {
    from: dateText(row?.effective_from, '0001-01-01'),
    to: dateText(row?.effective_to, '9999-12-31'),
  };
}

function rangesOverlap(left, right) {
  return left.from <= right.to && right.from <= left.to;
}

function assignmentPeriod(row) {
  return {
    employeeId: normalizeId(row?.employee_id),
    departmentId: normalizeId(row?.department_id),
    ...recordRange(row),
  };
}

async function loadAssignmentPeriods(db, employeeIds) {
  const ids = [...new Set(employeeIds.map(normalizeId).filter(Boolean))];
  if (ids.length === 0) return [];
  const result = await db.query(
    `SELECT employee_id::text AS employee_id,
            department_id::text AS department_id,
            effective_from::text AS effective_from,
            effective_to::text AS effective_to
       FROM assignments
      WHERE employee_id = ANY($1::uuid[])
        AND department_id IS NOT NULL
        AND is_active = true
      ORDER BY employee_id, effective_from, created_at, id`,
    [ids]
  );
  return result.rows.map(assignmentPeriod);
}

async function loadReviewerDepartmentPeriods(db, reviewerId) {
  const result = await db.query(
    `SELECT a.employee_id::text AS employee_id,
            a.department_id::text AS department_id,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to
       FROM assignments a
       JOIN positions p ON p.id = a.position_id
      WHERE a.employee_id = $1::uuid
        AND a.department_id IS NOT NULL
        AND a.is_active = true
        AND (p.is_active IS NULL OR p.is_active = true)
        AND p.is_department_head = true
      ORDER BY a.effective_from, a.created_at, a.id`,
    [reviewerId]
  );
  return result.rows.map(assignmentPeriod);
}

function rowDepartmentId(row) {
  return normalizeId(row?.access_department_id ?? row?.department_id);
}

async function filterAssignmentRowsForAccess(db, access, rows) {
  const records = Array.isArray(rows) ? rows : [];
  if (!access?.allowed) return [];
  if (access.scope === 'organization' || access.scope === 'self') return records;
  if (access.scope !== 'supervised_departments') return [];

  const reviewerPeriods = await loadReviewerDepartmentPeriods(db, access.requesterId);
  if (reviewerPeriods.length === 0) return [];

  const unresolvedEmployeeIds = records
    .filter((row) => !rowDepartmentId(row))
    .map((row) => row.employee_id);
  const targetPeriods = await loadAssignmentPeriods(db, unresolvedEmployeeIds);

  return records.filter((row) => {
    const range = recordRange(row);
    const explicitDepartmentId = rowDepartmentId(row);
    const employeeId = normalizeId(row.employee_id);
    const matchingTargetPeriods = explicitDepartmentId
      ? [{ employeeId, departmentId: explicitDepartmentId, ...range }]
      : targetPeriods.filter(
          (period) => period.employeeId === employeeId && rangesOverlap(period, range)
        );

    return matchingTargetPeriods.some((targetPeriod) =>
      reviewerPeriods.some(
        (reviewerPeriod) =>
          reviewerPeriod.departmentId === targetPeriod.departmentId &&
          rangesOverlap(reviewerPeriod, range) &&
          rangesOverlap(reviewerPeriod, targetPeriod)
      )
    );
  });
}

function assignmentAccessDeniedForRows(access, originalRows, visibleRows) {
  return (
    access?.scope === 'supervised_departments' &&
    Array.isArray(originalRows) &&
    originalRows.length > 0 &&
    (!Array.isArray(visibleRows) || visibleRows.length === 0) &&
    Boolean(access.employeeId)
  );
}

module.exports = {
  assignmentAccessDeniedForRows,
  filterAssignmentRowsForAccess,
  rangesOverlap,
  resolveAssignmentEmployeeAccess,
};
