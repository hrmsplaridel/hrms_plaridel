'use strict';
module.exports = function createDtrComponent({ MAX_DTR_BULK_REPORT_EMPLOYEES }) {
  function isTruthyQueryFlag(value) {
    return ['1', 'true', 'yes', 'on'].includes(
      String(value || '')
        .trim()
        .toLowerCase()
    );
  }

  function parseEmployeeIdList(value) {
    const values = Array.isArray(value) ? value : String(value || '').split(',');
    const ids = [
      ...new Set(values.map((item) => String(item).trim().toLowerCase()).filter(Boolean)),
    ];
    const uuidPattern =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (ids.some((id) => !uuidPattern.test(id))) {
      return { ids: [], error: 'employee_ids must contain valid UUID values' };
    }
    if (ids.length > MAX_DTR_BULK_REPORT_EMPLOYEES) {
      return {
        ids: [],
        error: `A bulk DTR report can include at most ${MAX_DTR_BULK_REPORT_EMPLOYEES} employees`,
      };
    }
    return { ids, error: null };
  }

  function inclusiveIsoDateRangeDays(startDate, endDate) {
    const isoDatePattern = /^\d{4}-\d{2}-\d{2}$/;
    if (
      !isoDatePattern.test(String(startDate || '')) ||
      !isoDatePattern.test(String(endDate || ''))
    ) {
      return null;
    }
    const startMs = Date.parse(`${startDate}T00:00:00Z`);
    const endMs = Date.parse(`${endDate}T00:00:00Z`);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs < startMs) return null;
    if (
      new Date(startMs).toISOString().slice(0, 10) !== startDate ||
      new Date(endMs).toISOString().slice(0, 10) !== endDate
    ) {
      return null;
    }
    return Math.floor((endMs - startMs) / 86400000) + 1;
  }
  return { isTruthyQueryFlag, parseEmployeeIdList, inclusiveIsoDateRangeDays };
};
