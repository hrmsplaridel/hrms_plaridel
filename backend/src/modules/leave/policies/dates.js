'use strict';
module.exports = function createLeaveComponent({}) {
  function toIsoDateStr(val) {
    if (!val) return null;
    if (val instanceof Date) {
      // Manually format so we don't shift by timezone.
      const y = val.getFullYear();
      const m = String(val.getMonth() + 1).padStart(2, '0');
      const d = String(val.getDate()).padStart(2, '0');
      return `${y}-${m}-${d}`;
    }
    const s = String(val);
    const match = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
    return match ? match[0] : null;
  }

  function isValidIsoCalendarDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return false;
    const [year, month, day] = value.split('-').map(Number);
    const parsed = new Date(Date.UTC(year, month - 1, day));
    return (
      parsed.getUTCFullYear() === year &&
      parsed.getUTCMonth() === month - 1 &&
      parsed.getUTCDate() === day
    );
  }

  function invalidProvidedDate(rawValue, normalizedValue) {
    if (rawValue == null || String(rawValue).trim() === '') return false;
    return !isValidIsoCalendarDate(normalizedValue);
  }

  // Public filing dates are calendar dates, not timestamps or date-like prefixes.
  function requiredLeaveDateRangeError(startDate, endDate) {
    if (
      startDate == null ||
      endDate == null ||
      (typeof startDate === 'string' && !startDate.trim()) ||
      (typeof endDate === 'string' && !endDate.trim())
    ) {
      return 'start_date and end_date are required';
    }
    if (typeof startDate !== 'string' || !isValidIsoCalendarDate(startDate)) {
      return 'start_date must be a valid date in YYYY-MM-DD format';
    }
    if (typeof endDate !== 'string' || !isValidIsoCalendarDate(endDate)) {
      return 'end_date must be a valid date in YYYY-MM-DD format';
    }
    if (endDate < startDate) return 'end_date cannot be earlier than start_date';
    return null;
  }

  function isWeekday(dateObj) {
    const d = dateObj.getDay(); // 0 Sun .. 6 Sat
    return d !== 0 && d !== 6;
  }

  function isoWeekdayFromDateString(dateStr) {
    const d = new Date(`${dateStr}T12:00:00`);
    if (isNaN(d.getTime())) return null;
    const day = d.getDay(); // 0 Sun .. 6 Sat
    return day === 0 ? 7 : day;
  }

  function normalizeWorkingDays(value) {
    const source = Array.isArray(value)
      ? value
      : typeof value === 'string'
        ? value.match(/\d+/g) || []
        : [1, 2, 3, 4, 5];
    const days = source
      .map((d) => parseInt(d, 10))
      .filter((d) => Number.isInteger(d) && d >= 1 && d <= 7);
    return days.length > 0 ? days : [1, 2, 3, 4, 5];
  }

  function calendarYearsForDateRange(startStr, endStr) {
    const startYear = parseInt(String(startStr || '').slice(0, 4), 10);
    const endYear = parseInt(String(endStr || '').slice(0, 4), 10);
    if (!Number.isInteger(startYear) || !Number.isInteger(endYear)) return [];
    const from = Math.min(startYear, endYear);
    const to = Math.max(startYear, endYear);
    const years = [];
    for (let year = from; year <= to; year += 1) years.push(year);
    return years;
  }

  function maxIsoDate(a, b) {
    if (!a) return b;
    if (!b) return a;
    return a > b ? a : b;
  }

  function minIsoDate(a, b) {
    if (!a) return b;
    if (!b) return a;
    return a < b ? a : b;
  }

  function formatDayCount(days) {
    const n = Number(days);
    if (!Number.isFinite(n)) return '0';
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, '');
  }
  return {
    toIsoDateStr,
    isValidIsoCalendarDate,
    invalidProvidedDate,
    requiredLeaveDateRangeError,
    isWeekday,
    isoWeekdayFromDateString,
    normalizeWorkingDays,
    calendarYearsForDateRange,
    maxIsoDate,
    minIsoDate,
    formatDayCount,
  };
};
