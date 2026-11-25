'use strict';
module.exports = function createDtrControllers({ getHolidayByDate, pool, todayInHrmsTimezone }) {
  const {
    countLateOn,
    countOnLeaveOn,
    countPendingLeaveApprovals,
    countPresentOn,
  } = require('../repositories/dashboard')({ pool });
  return {
    getDashboardSummary: async (req, res) => {
      try {
        const today = todayInHrmsTimezone();
        const todayHoliday = await getHolidayByDate(today);
        const isWholeDayHoliday = todayHoliday?.coverage === 'whole_day';
        const present = await countPresentOn(today);
        const late = await countLateOn(today);

        let onLeaveToday = 0;
        try {
          onLeaveToday = await countOnLeaveOn(today);
        } catch (leaveErr) {
          console.warn(
            '[dtr-daily-summary/summary GET] on_leave_today:',
            leaveErr?.message || leaveErr
          );
        }

        let pendingApproval = 0;
        try {
          pendingApproval = await countPendingLeaveApprovals();
        } catch (pendErr) {
          console.warn(
            '[dtr-daily-summary/summary GET] pending_approval:',
            pendErr?.message || pendErr
          );
        }

        res.json({
          present_today: isWholeDayHoliday ? 0 : present,
          late_today: isWholeDayHoliday ? 0 : late,
          on_leave_today: onLeaveToday,
          pending_approval: pendingApproval,
        });
      } catch (err) {
        console.error('[dtr-daily-summary/summary GET]', err);
        res.status(500).json({ error: 'Failed to fetch DTR summary counts' });
      }
    },
  };
};
