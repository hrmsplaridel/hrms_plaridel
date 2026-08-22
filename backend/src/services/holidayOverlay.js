'use strict';

const {
  expandNonRecurringToWindow,
  expandRecurringToWindow,
} = require('./holidayRangeUtils');

function dateOnly(value) {
  if (value == null) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  if (value instanceof Date) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  return String(value).slice(0, 10);
}

function isMissingCoverageColumn(error) {
  return error?.code === '42703' || /coverage|column.*does not exist/i.test(error?.message || '');
}

async function queryActiveHolidays(client, startStr, endStr) {
  const baseSql = (coverageColumn) =>
    `SELECT id, name, holiday_type, date_from, date_to, recurring,
            ${coverageColumn}
       FROM holidays
      WHERE (is_active IS NULL OR is_active = true)
        AND (
          recurring = true
          OR (date_from <= $2::date AND date_to >= $1::date)
        )
      ORDER BY recurring ASC, date_from ASC, date_to ASC, id ASC`;

  try {
    return await client.query(baseSql('coverage'), [startStr, endStr]);
  } catch (error) {
    if (!isMissingCoverageColumn(error)) throw error;
    return client.query(
      baseSql(`'whole_day'::text AS coverage`),
      [startStr, endStr]
    );
  }
}

/**
 * Resolve the active holiday configuration for every date in a window.
 * Non-recurring records take precedence over recurring templates.
 */
async function loadHolidayOverlayMap(client, startDate, endDate) {
  const startStr = dateOnly(startDate);
  const endStr = dateOnly(endDate);
  if (!startStr || !endStr || startStr > endStr) return new Map();

  const result = await queryActiveHolidays(client, startStr, endStr);
  const byDate = new Map();

  for (const row of result.rows) {
    const dates = row.recurring
      ? expandRecurringToWindow(
          dateOnly(row.date_from),
          dateOnly(row.date_to),
          startStr,
          endStr
        )
      : expandNonRecurringToWindow(
          dateOnly(row.date_from),
          dateOnly(row.date_to),
          startStr,
          endStr
        );

    for (const dateStr of dates) {
      if (byDate.has(dateStr)) continue;
      byDate.set(dateStr, {
        dateStr,
        id: row.id,
        name: row.name,
        holiday_type: row.holiday_type || 'regular',
        coverage: row.coverage || 'whole_day',
      });
    }
  }

  return byDate;
}

function hasPhysicalPunches(record) {
  return !!(
    record?.time_in ||
    record?.break_out ||
    record?.break_in ||
    record?.time_out
  );
}

function resolveAttendanceHolidayOverlay(record, activeHoliday) {
  const staleStoredHoliday = record?.status === 'holiday' && !activeHoliday;
  const restoredStatus = staleStoredHoliday
    ? (hasPhysicalPunches(record) ? 'present' : 'absent')
    : record?.status;
  return {
    status: activeHoliday ? 'holiday' : restoredStatus,
    holidayId: activeHoliday?.id || null,
    holidayName: activeHoliday?.name || null,
    holidayType: activeHoliday?.holiday_type || null,
    coverage: activeHoliday?.coverage || null,
    staleStoredHoliday,
  };
}

module.exports = {
  dateOnly,
  hasPhysicalPunches,
  loadHolidayOverlayMap,
  resolveAttendanceHolidayOverlay,
};
