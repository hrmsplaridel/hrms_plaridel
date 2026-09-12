'use strict';

const DEFAULT_TTL_MS = 60 * 1000;
const stores = new Map();

function storeFor(namespace) {
  const key = String(namespace || 'default');
  if (!stores.has(key)) stores.set(key, new Map());
  return stores.get(key);
}

function getAttendancePolicyCache(namespace, key, { ttlMs = DEFAULT_TTL_MS } = {}) {
  const store = storeFor(namespace);
  const entry = store.get(String(key));
  if (!entry) return { found: false, value: null };
  if (Date.now() - entry.at >= ttlMs) {
    store.delete(String(key));
    return { found: false, value: null };
  }
  return { found: true, value: entry.value };
}

function setAttendancePolicyCache(
  namespace,
  key,
  value,
  { employeeId = null, date = null, isDefault = false } = {}
) {
  storeFor(namespace).set(String(key), {
    at: Date.now(),
    value,
    employeeId: employeeId == null ? null : String(employeeId),
    date: date == null ? null : String(date),
    isDefault: isDefault === true,
  });
  return value;
}

function invalidateAttendancePolicyCache({
  employeeId = null,
  dateFrom = null,
  dateTo = null,
  includeDefaults = employeeId == null,
} = {}) {
  const employee = employeeId == null ? null : String(employeeId);
  let removed = 0;
  for (const store of stores.values()) {
    for (const [key, entry] of store.entries()) {
      if (entry.isDefault) {
        if (!includeDefaults) continue;
      } else {
        if (employee && entry.employeeId !== employee) continue;
        if (dateFrom && entry.date && entry.date < dateFrom) continue;
        if (dateTo && entry.date && entry.date > dateTo) continue;
      }
      store.delete(key);
      removed += 1;
    }
  }
  return removed;
}

module.exports = {
  DEFAULT_TTL_MS,
  getAttendancePolicyCache,
  invalidateAttendancePolicyCache,
  setAttendancePolicyCache,
};
