'use strict';
module.exports = function createDtrControllers({
  getAssignmentShiftForDate,
  getHolidayByDate,
  inclusiveIsoDateRangeDays,
  isOvernight,
  minutesToTimeStr,
  resolveExpectedLogsForDay,
  resolveShiftType,
  todayInHrmsTimezone,
}) {
  return {
    getShiftForDate: async (req, res) => {
      try {
        const employeeId = String(req.query.employee_id || '').trim();
        const date = String(req.query.date || '').trim();
        const uuidPattern =
          /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        if (!uuidPattern.test(employeeId)) {
          return res.status(400).json({ error: 'A valid employee_id is required' });
        }
        if (inclusiveIsoDateRangeDays(date, date) !== 1) {
          return res.status(400).json({ error: 'A valid date is required' });
        }

        const shiftInfo = await getAssignmentShiftForDate(employeeId, date);
        if (!shiftInfo) {
          return res.status(404).json({
            error: 'No employee shift assignment is effective on the selected date',
          });
        }

        const expected = resolveExpectedLogsForDay(shiftInfo, null);
        const resolvedPunchMode = resolveShiftType(shiftInfo) || shiftInfo.punchMode || 'auto';
        const expectedPunches = expected.needsInOut
          ? ['time_in', 'time_out']
          : [
              ...(expected.needsAm ? ['time_in', 'break_out'] : []),
              ...(expected.needsPm ? ['break_in', 'time_out'] : []),
            ];
        return res.json({
          employee_id: employeeId,
          date,
          punch_mode: resolvedPunchMode,
          start_minutes: shiftInfo.startMinutes,
          end_minutes: shiftInfo.endMinutes,
          break_end_minutes: shiftInfo.breakEndMinutes,
          break_start_minutes: shiftInfo.breakStartMinutes,
          is_overnight: isOvernight(shiftInfo),
          capture_window_minutes: shiftInfo.captureWindowMinutes,
          expected_punches: expectedPunches,
        });
      } catch (err) {
        console.error('[dtr-daily-summary shift-for-date GET]', err);
        return res
          .status(500)
          .json({ error: 'Failed to fetch the employee shift for the selected date' });
      }
    },

    getMyShiftToday: async (req, res) => {
      try {
        const userId = req.user?.id;
        if (!userId) return res.status(401).json({ error: 'Not authenticated' });
        const today = todayInHrmsTimezone();
        const activeHoliday = await getHolidayByDate(today);
        const shiftInfo = await getAssignmentShiftForDate(userId, today);
        if (!shiftInfo || shiftInfo.endMinutes == null) {
          return res.json({ start_time: null, end_time: null }); // no shift or no end = no restriction
        }
        res.json({
          start_time:
            shiftInfo.startMinutes != null ? minutesToTimeStr(shiftInfo.startMinutes) : null,
          start_minutes: shiftInfo.startMinutes != null ? shiftInfo.startMinutes : null,
          end_time: minutesToTimeStr(shiftInfo.endMinutes),
          end_minutes: shiftInfo.endMinutes,
        });
      } catch (err) {
        console.error('[dtr-daily-summary my-shift-today GET]', err);
        res.status(500).json({ error: 'Failed to fetch shift' });
      }
    },
  };
};
