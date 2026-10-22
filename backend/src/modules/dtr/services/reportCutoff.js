'use strict';
module.exports = function createDtrComponent({
  addDaysToIsoDate,
  getAssignmentShiftForDate,
  getShiftInfoForDateFromAssignments,
  isAttendanceDateFinalized,
  nowMinutesInHrmsTimezone,
  todayInHrmsTimezone,
}) {
  async function resolveReportableThrough({ employeeId, rangeEnd, holidayByDate }) {
    const todayStr = todayInHrmsTimezone();
    const nowMinutes = nowMinutesInHrmsTimezone();
    let candidate = rangeEnd < todayStr ? rangeEnd : todayStr;

    for (let checked = 0; checked < 3; checked += 1) {
      const shiftInfo = await getAssignmentShiftForDate(employeeId, candidate);
      if (
        isAttendanceDateFinalized({
          dateStr: candidate,
          todayStr,
          nowMinutes,
          shiftInfo,
          holidayInfo: holidayByDate.get(candidate) || null,
        })
      ) {
        return candidate;
      }
      candidate = addDaysToIsoDate(candidate, -1);
    }
    return candidate;
  }

  function resolveReportableThroughFromAssignments({
    employeeId,
    rangeEnd,
    holidayByDate,
    assignmentsByEmployee,
  }) {
    const todayStr = todayInHrmsTimezone();
    const nowMinutes = nowMinutesInHrmsTimezone();
    let candidate = rangeEnd < todayStr ? rangeEnd : todayStr;

    for (let checked = 0; checked < 3; checked += 1) {
      const shiftInfo = getShiftInfoForDateFromAssignments(
        assignmentsByEmployee,
        employeeId,
        candidate
      );
      if (
        isAttendanceDateFinalized({
          dateStr: candidate,
          todayStr,
          nowMinutes,
          shiftInfo,
          holidayInfo: holidayByDate.get(candidate) || null,
        })
      ) {
        return candidate;
      }
      candidate = addDaysToIsoDate(candidate, -1);
    }
    return candidate;
  }
  return { resolveReportableThrough, resolveReportableThroughFromAssignments };
};
