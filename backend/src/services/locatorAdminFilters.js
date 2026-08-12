const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const LOCATOR_STATUSES = new Set([
  'pending',
  'pending_department_head',
  'pending_hr',
  'returned_for_correction',
  'approved',
  'revoked',
  'rejected_by_department_head',
  'rejected_by_hr',
  'cancelled',
]);

function parseInteger(value, fallback, { min, max }) {
  if (value == null || String(value).trim() === '') return fallback;
  if (!/^\d+$/.test(String(value).trim())) return null;
  const parsed = Number.parseInt(String(value), 10);
  return parsed >= min && parsed <= max ? parsed : null;
}

function parseDateOnly(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return undefined;
  }
  return raw;
}

function parseStatusFilter(value) {
  const status = String(value || '').trim().toLowerCase();
  if (!status) return null;
  if (status === 'pending_hr') return ['pending_hr', 'pending'];
  if (status === 'rejected') {
    return ['rejected_by_department_head', 'rejected_by_hr'];
  }
  return LOCATOR_STATUSES.has(status) ? [status] : undefined;
}

function parseLocatorAdminFilters(query = {}) {
  const page = parseInteger(query.page, 1, { min: 1, max: 1000000 });
  const pageSize = parseInteger(query.page_size, 10, { min: 1, max: 100 });
  if (page == null || pageSize == null) {
    return {
      ok: false,
      error: 'page must be positive and page_size must be between 1 and 100.',
    };
  }

  const statuses = parseStatusFilter(query.status);
  if (statuses === undefined) {
    return { ok: false, error: 'Invalid status filter.' };
  }

  const departmentId = String(query.department_id || '').trim() || null;
  const employeeId = String(query.employee_id || '').trim() || null;
  if (departmentId && !UUID_PATTERN.test(departmentId)) {
    return { ok: false, error: 'Invalid department_id filter.' };
  }
  if (employeeId && !UUID_PATTERN.test(employeeId)) {
    return { ok: false, error: 'Invalid employee_id filter.' };
  }

  const from = parseDateOnly(query.from);
  const to = parseDateOnly(query.to);
  if (from === undefined || to === undefined) {
    return { ok: false, error: 'Date filters must use YYYY-MM-DD.' };
  }
  if (from && to && from > to) {
    return { ok: false, error: 'The from date cannot be after the to date.' };
  }

  const search = String(query.search || '').trim();
  if (search.length > 100) {
    return { ok: false, error: 'Search text cannot exceed 100 characters.' };
  }

  return {
    ok: true,
    filters: {
      page,
      pageSize,
      statuses,
      departmentId,
      employeeId,
      from,
      to,
      search: search || null,
    },
  };
}

module.exports = {
  parseLocatorAdminFilters,
  parseStatusFilter,
};
