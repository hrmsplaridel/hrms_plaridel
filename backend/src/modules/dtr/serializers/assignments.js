'use strict';
module.exports = function createDtrComponent({}) {
  function assignmentForBulkReport(assignment) {
    return {
      id: assignment.id || null,
      department_id: assignment.departmentId || null,
      department_name: assignment.departmentName || null,
      position_name: assignment.positionName || null,
      shift_id: assignment.shiftId || null,
      shift_name: assignment.shiftName || null,
      effective_from: assignment.effective_from,
      effective_to: assignment.effective_to,
      start_time: assignment.startTime,
      end_time: assignment.endTime,
      break_end: assignment.breakEnd,
      punch_mode: assignment.punchMode || 'auto',
      working_days: assignment.workingDays || [1, 2, 3, 4, 5],
    };
  }

  function scheduleOverridesForEmployee(overrides, employeeId, assignment) {
    if (!(overrides instanceof Map)) return [];
    const prefix = `${employeeId}|`;
    const rows = [];
    for (const [key, isWorkingDay] of overrides.entries()) {
      if (!String(key).startsWith(prefix)) continue;
      const date = String(key).slice(prefix.length);
      if (date < assignment.effective_from) continue;
      if (assignment.effective_to && date > assignment.effective_to) continue;
      rows.push({ date, is_working_day: isWorkingDay === true });
    }
    return rows.sort((a, b) => a.date.localeCompare(b.date));
  }
  return { assignmentForBulkReport, scheduleOverridesForEmployee };
};
