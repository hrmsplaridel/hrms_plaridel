'use strict';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const POSITION_STATUSES = new Map([
  ['active', 'Active'],
  ['inactive', 'Inactive'],
  ['all', 'All'],
]);

const DEFAULT_PAGE_SIZE = 10;
const MAX_PAGE_SIZE = 100;
const LEGACY_LOOKUP_LIMIT = 500;

function parseInteger(value, fallback, { min, max }) {
  if (value === null || value === undefined || String(value).trim() === '') {
    return fallback;
  }
  const text = String(value).trim();
  if (!/^\d+$/.test(text)) return null;
  const parsed = Number.parseInt(text, 10);
  return parsed >= min && parsed <= max ? parsed : null;
}

function parsePositionListFilters(query = {}) {
  const statusText = String(query.status || 'Active').trim().toLowerCase();
  const status = POSITION_STATUSES.get(statusText);
  if (!status) {
    return { ok: false, error: 'status must be Active, Inactive, or All' };
  }

  const departmentId = String(query.department_id || '').trim() || null;
  if (departmentId && !UUID_PATTERN.test(departmentId)) {
    return { ok: false, error: 'department_id must be a valid UUID' };
  }

  const paginated = String(query.paginated || '').trim().toLowerCase() === 'true';
  const page = parseInteger(query.page, 1, { min: 1, max: 1000000 });
  const requestedLimit = query.limit ?? query.page_size;
  const limit = parseInteger(requestedLimit, DEFAULT_PAGE_SIZE, {
    min: 1,
    max: MAX_PAGE_SIZE,
  });
  if (page === null || limit === null) {
    return {
      ok: false,
      error: `page must be positive and limit must be between 1 and ${MAX_PAGE_SIZE}`,
    };
  }

  const search = String(query.search || '').trim();
  if (search.length > 200) {
    return { ok: false, error: 'search must not exceed 200 characters' };
  }

  return {
    ok: true,
    status,
    departmentId,
    paginated,
    page,
    limit,
    search,
    responseLimit: paginated ? limit : LEGACY_LOOKUP_LIMIT,
  };
}

module.exports = {
  DEFAULT_PAGE_SIZE,
  LEGACY_LOOKUP_LIMIT,
  MAX_PAGE_SIZE,
  parsePositionListFilters,
};
