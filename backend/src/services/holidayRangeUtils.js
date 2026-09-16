'use strict';

/**
 * Helpers for holidays stored as [date_from, date_to] with optional recurring (month/day template).
 */

/** @param {string} s */
function parseYmd(s) {
  const parts = String(s).split('T')[0].split('-');
  return {
    y: parseInt(parts[0], 10),
    m: parseInt(parts[1], 10),
    d: parseInt(parts[2], 10),
  };
}

/** @param {Date} d */
function toYyyyMmDd(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function monthDayKey(value) {
  return value.m * 100 + value.d;
}

function isValidRecurringMonthDay(value) {
  if (!Number.isInteger(value.m) || !Number.isInteger(value.d)) return false;
  // Year 2000 is a leap year, so February 29 remains a valid template date.
  const date = new Date(Date.UTC(2000, value.m - 1, value.d));
  return date.getUTCMonth() === value.m - 1 && date.getUTCDate() === value.d;
}

function datesInYearMatching(year, predicate) {
  const out = [];
  const current = new Date(year, 0, 1, 12, 0, 0);
  while (current.getFullYear() === year) {
    const key = (current.getMonth() + 1) * 100 + current.getDate();
    if (predicate(key)) out.push(toYyyyMmDd(current));
    current.setDate(current.getDate() + 1);
  }
  return out;
}

/**
 * Dates in [dateFrom, dateTo] intersected with [windowStart, windowEnd], inclusive (non-recurring).
 * @param {string} dateFromStr
 * @param {string} dateToStr
 * @param {string} windowStart
 * @param {string} windowEnd
 * @returns {string[]}
 */
function expandNonRecurringToWindow(dateFromStr, dateToStr, windowStart, windowEnd) {
  const ws = windowStart.slice(0, 10);
  const we = windowEnd.slice(0, 10);
  const df = dateFromStr.slice(0, 10);
  const dt = dateToStr.slice(0, 10);
  const start = df > ws ? df : ws;
  const end = dt < we ? dt : we;
  if (start > end) return [];
  const out = [];
  const cur = new Date(`${start}T12:00:00`);
  const endD = new Date(`${end}T12:00:00`);
  while (cur <= endD) {
    out.push(toYyyyMmDd(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return out;
}

/**
 * One calendar year of a recurring template (month/day from date_from through date_to).
 * Handles cross-year spans (e.g. Dec 28 – Jan 3).
 * @param {{ m: number, d: number }} t0
 * @param {{ m: number, d: number }} t1
 * @param {number} year
 */
function expandTemplateInYear(t0, t1, year) {
  if (!isValidRecurringMonthDay(t0) || !isValidRecurringMonthDay(t1)) return [];
  const startKey = monthDayKey(t0);
  const endKey = monthDayKey(t1);
  if (endKey >= startKey) {
    return datesInYearMatching(year, (key) => key >= startKey && key <= endKey);
  }
  return [
    ...datesInYearMatching(year, (key) => key >= startKey),
    ...datesInYearMatching(year + 1, (key) => key <= endKey),
  ];
}

/**
 * Recurring holiday: all dates in [windowStart, windowEnd] that match the template.
 * @param {string} templateFromStr
 * @param {string} templateToStr
 * @param {string} windowStart
 * @param {string} windowEnd
 * @returns {string[]}
 */
function expandRecurringToWindow(templateFromStr, templateToStr, windowStart, windowEnd) {
  const ws = windowStart.slice(0, 10);
  const we = windowEnd.slice(0, 10);
  const t0 = parseYmd(templateFromStr);
  const t1 = parseYmd(templateToStr);
  const y0 = parseInt(ws.slice(0, 4), 10);
  const y1 = parseInt(we.slice(0, 4), 10);
  const out = [];
  const seen = new Set();
  for (let year = y0 - 1; year <= y1 + 1; year++) {
    for (const ds of expandTemplateInYear(t0, t1, year)) {
      if (ds >= ws && ds <= we && !seen.has(ds)) {
        seen.add(ds);
        out.push(ds);
      }
    }
  }
  return out.sort();
}

/**
 * Whether dateStr (YYYY-MM-DD) falls on the recurring template (same month/day span each year).
 */
function dateInRecurringRange(dateStr, templateFromStr, templateToStr) {
  const ds = dateStr.slice(0, 10);
  const y = parseInt(ds.slice(0, 4), 10);
  const t0 = parseYmd(templateFromStr);
  const t1 = parseYmd(templateToStr);
  for (const testY of [y - 1, y, y + 1]) {
    if (expandTemplateInYear(t0, t1, testY).includes(ds)) return true;
  }
  return false;
}

module.exports = {
  expandNonRecurringToWindow,
  expandRecurringToWindow,
  dateInRecurringRange,
  toYyyyMmDd,
};
