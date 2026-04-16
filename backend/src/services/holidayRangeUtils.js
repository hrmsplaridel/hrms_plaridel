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
  const start = new Date(year, t0.m - 1, t0.d, 12, 0, 0);
  const endSameYear = new Date(year, t1.m - 1, t1.d, 12, 0, 0);
  const out = [];
  if (endSameYear >= start) {
    const cur = new Date(start);
    while (cur <= endSameYear) {
      out.push(toYyyyMmDd(cur));
      cur.setDate(cur.getDate() + 1);
    }
  } else {
    const endDec = new Date(year, 11, 31, 12, 0, 0);
    let cur = new Date(start);
    while (cur <= endDec) {
      out.push(toYyyyMmDd(cur));
      cur.setDate(cur.getDate() + 1);
    }
    const endNext = new Date(year + 1, t1.m - 1, t1.d, 12, 0, 0);
    cur = new Date(year + 1, 0, 1, 12, 0, 0);
    while (cur <= endNext) {
      out.push(toYyyyMmDd(cur));
      cur.setDate(cur.getDate() + 1);
    }
  }
  return out;
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
