const PRIVILEGED_DTR_ROLES = new Set(['admin', 'hr', 'supervisor']);

function normalizeOptionalQueryValue(value) {
  const selected = Array.isArray(value) ? value[0] : value;
  const normalized = selected == null ? '' : String(selected).trim();
  return normalized || null;
}

function resolveDtrDailySummaryScope(user, query = {}) {
  const privileged = PRIVILEGED_DTR_ROLES.has(user?.role);
  if (!privileged) {
    return {
      privileged: false,
      employeeId: normalizeOptionalQueryValue(user?.id),
      departmentId: null,
    };
  }

  return {
    privileged: true,
    employeeId: normalizeOptionalQueryValue(query.employee_id),
    departmentId: normalizeOptionalQueryValue(query.department_id),
  };
}

module.exports = {
  resolveDtrDailySummaryScope,
};
