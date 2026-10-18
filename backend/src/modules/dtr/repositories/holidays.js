'use strict';
module.exports = function createDtrComponent({ loadHolidayOverlayMap, pool }) {
  /** True if holidays table has coverage column (work suspension migration applied). */
  let _holidaysHasCoverageColumnCached = null;

  async function _holidaysHasCoverageColumn() {
    if (_holidaysHasCoverageColumnCached != null) return _holidaysHasCoverageColumnCached;
    try {
      await pool.query('SELECT coverage FROM holidays LIMIT 1');
      _holidaysHasCoverageColumnCached = true;
    } catch {
      _holidaysHasCoverageColumnCached = false;
    }
    return _holidaysHasCoverageColumnCached;
  }

  /** Get active holiday for a date, if any. Non-recurring range match first, then recurring template. Returns { id, name, holiday_type, coverage } or null. Tolerates missing coverage column. */
  async function getHolidayByDate(dateStr) {
    const byDate = await loadHolidayOverlayMap(pool, dateStr, dateStr);
    return byDate.get(String(dateStr).slice(0, 10)) || null;
  }
  return { _holidaysHasCoverageColumn, getHolidayByDate };
};
