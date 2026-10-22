'use strict';
module.exports = function createDtrComponent({ HRMS_TIMEZONE }) {
  /** Parse time value to minutes from midnight. Returns null if invalid. */
  function timeToMinutes(timeStr) {
    if (!timeStr) return null;
    if (timeStr instanceof Date) {
      const h = timeStr.getHours();
      const m = timeStr.getMinutes();
      if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
      return Math.min(24 * 60 - 1, Math.max(0, h * 60 + m));
    }
    const s = String(timeStr).trim();
    // Accept "HH:MM", "HH:MM:SS", "HH:MM:SS.ssssss"
    const m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/);
    if (!m) return null;
    const h = parseInt(m[1], 10);
    const min = parseInt(m[2], 10);
    if (!Number.isFinite(h) || !Number.isFinite(min)) return null;
    return Math.min(24 * 60 - 1, Math.max(0, h * 60 + min));
  }

  /** Format minutes from midnight as "HH:MM". */
  function minutesToTimeStr(mins) {
    const h = Math.floor(mins / 60) % 24;
    const m = mins % 60;
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
  }

  /**
   * Returns today's date string (YYYY-MM-DD) in HRMS_TIMEZONE, not UTC.
   * Prevents off-by-one issues when the server runs in UTC but the business
   * timezone is e.g. Asia/Manila (+08:00).
   */
  function todayInHrmsTimezone() {
    const now = new Date();
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: HRMS_TIMEZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(now);
    const y = parts.find((p) => p.type === 'year')?.value ?? '';
    const m = parts.find((p) => p.type === 'month')?.value ?? '';
    const d = parts.find((p) => p.type === 'day')?.value ?? '';
    return `${y}-${m}-${d}`;
  }

  /**
   * Returns current minutes-from-midnight (0-1439) in HRMS_TIMEZONE.
   * Uses the same Intl machinery as minutesFromMidnightInTimeZone() so
   * the result is consistent with shift boundary comparisons throughout.
   */
  function nowMinutesInHrmsTimezone() {
    return minutesFromMidnightInTimeZone(new Date(), HRMS_TIMEZONE) ?? 0;
  }

  /** Get minutes-from-midnight in a specific IANA timezone from a Date/ISO value. */
  function minutesFromMidnightInTimeZone(val, timeZone = HRMS_TIMEZONE) {
    if (!val) return null;
    const d = val instanceof Date ? val : new Date(val);
    if (isNaN(d.getTime())) return null;
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
    }).formatToParts(d);
    const hh = parseInt(parts.find((p) => p.type === 'hour')?.value ?? '0', 10);
    const mm = parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);
    if (!Number.isFinite(hh) || !Number.isFinite(mm)) return null;
    return hh * 60 + mm;
  }

  /** Normalize date value to YYYY-MM-DD for PostgreSQL. Handles Date objects and ISO strings. */
  function toIsoDateStr(val) {
    if (!val) return null;
    if (val instanceof Date) return val.toISOString().slice(0, 10);
    const s = String(val);
    const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? m[0] : null;
  }

  /** Return calendar date YYYY-MM-DD for API responses (avoids timezone shift when JSON serializes Date as UTC). */
  function toDateOnlyResponse(val) {
    if (!val) return null;
    const s = String(val);
    const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? m[0] : null;
  }

  /** ISO weekday (1=Mon..7=Sun) from YYYY-MM-DD. */
  function isoWeekdayFromDateStr(dateStr) {
    const d = new Date(`${dateStr}T00:00:00`);
    const js = d.getDay(); // 0=Sun..6=Sat
    return js === 0 ? 7 : js;
  }
  return {
    timeToMinutes,
    minutesToTimeStr,
    todayInHrmsTimezone,
    nowMinutesInHrmsTimezone,
    minutesFromMidnightInTimeZone,
    toIsoDateStr,
    toDateOnlyResponse,
    isoWeekdayFromDateStr,
  };
};
