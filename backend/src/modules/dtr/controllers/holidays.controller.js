'use strict';
module.exports = function createDtrControllers({
  broadcastBiometricUpdate,
  loadHolidayOverlayMap,
  pool,
}) {
  return {
    syncHolidays: async (req, res) => {
      try {
        const { start_date, end_date } = req.body;
        const start = start_date || new Date().toISOString().slice(0, 10);
        const end = end_date || start;
        if (start > end) {
          return res.status(400).json({ error: 'end_date must be on or after start_date' });
        }
        const overlays = await loadHolidayOverlayMap(pool, start, end);
        broadcastBiometricUpdate('dtr_refresh', {
          action: 'holidays_refreshed',
          coveredDates: overlays.size,
          dateFrom: start,
          dateTo: end,
        });
        res.json({ updated: 0, covered_dates: overlays.size, overlay_only: true });
      } catch (err) {
        console.error('[dtr-daily-summary sync-holidays POST]', err);
        res.status(500).json({ error: 'Failed to sync holidays to DTR summary' });
      }
    },
  };
};
