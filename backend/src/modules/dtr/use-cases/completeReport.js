'use strict';
module.exports = function createDtrComponent({
  addAbsenceReportRows,
  addHolidayReportRows,
  addLeaveReportRows,
  addLocatorReportRows,
  annotateLocatorReportRows,
  attachReportPolicies,
  getApprovedLeaveCoverageInRange,
  getApprovedLeaveKeysInRange,
  getApprovedLocatorByDateInRange,
  getAssignmentsForEmployeesInRange,
  loadAttendancePolicyContext,
  loadScheduleOverrides,
  nowMinutesInHrmsTimezone,
  pool,
  toIsoDateStr,
  todayInHrmsTimezone,
}) {
  async function completeDtrReport({
    activeHolidayByDate,
    endStr,
    rawRows,
    requestedEmployeeIds,
    rows,
    savedShiftsByDate,
    scopedDepartmentId,
    scopedEmployeeId,
    startStr,
  }) {
    let reportScheduleOverrides, reportEmployeeIds, reportAssignmentsByEmployee;

    const existingKeys = new Set(
      rawRows.map((r) => {
        const dateStr =
          (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
          toIsoDateStr(r.attendance_date);
        return `${r.employee_id}|${dateStr}`;
      })
    );
    const userIdToName = {};
    for (const r of rawRows) {
      if (r.employee_id && r.employee_name) userIdToName[r.employee_id] = r.employee_name;
    }
    let employeeIds;
    if (scopedEmployeeId) {
      employeeIds = [scopedEmployeeId];
      if (!userIdToName[scopedEmployeeId]) {
        const u = await pool.query('SELECT full_name FROM users WHERE id = $1', [scopedEmployeeId]);
        if (u.rows[0]) userIdToName[scopedEmployeeId] = u.rows[0].full_name;
      }
    } else if (requestedEmployeeIds.length > 0) {
      const selectedEmployees = await pool.query(
        `SELECT id, full_name
           FROM users
           WHERE id = ANY($1::uuid[])
           ORDER BY full_name`,
        [requestedEmployeeIds]
      );
      const availableById = new Map(selectedEmployees.rows.map((row) => [String(row.id), row]));
      employeeIds = requestedEmployeeIds.filter((id) => availableById.has(id));
      for (const employee of selectedEmployees.rows) {
        if (employee.id && employee.full_name) {
          userIdToName[employee.id] = employee.full_name;
        }
      }
    } else if (scopedDepartmentId && startStr && endStr) {
      const deptEmps = await pool.query(
        `SELECT DISTINCT u.id, u.full_name
           FROM assignments a
           JOIN users u ON u.id = a.employee_id AND u.is_active = true
           WHERE a.department_id = $1
             AND a.effective_from <= $2::date
             AND (a.effective_to IS NULL OR a.effective_to >= $3::date)
           ORDER BY u.full_name`,
        [scopedDepartmentId, endStr, startStr]
      );
      employeeIds = deptEmps.rows.map((r) => r.id).filter(Boolean);
      for (const r of deptEmps.rows) {
        if (r.id && r.full_name) userIdToName[r.id] = r.full_name;
      }
    } else {
      // Employees with at least one active assignment overlapping the date range (not all active users).
      const assignedEmps = await pool.query(
        `SELECT DISTINCT u.id, u.full_name
           FROM assignments a
           JOIN users u ON u.id = a.employee_id AND u.is_active = true
           WHERE a.effective_from <= $1::date
             AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
           ORDER BY u.full_name`,
        [endStr, startStr]
      );
      employeeIds = assignedEmps.rows.map((r) => r.id).filter(Boolean);
      for (const r of assignedEmps.rows) {
        if (r.id && r.full_name) userIdToName[r.id] = r.full_name;
      }
    }

    const assignmentsByEmployee = await getAssignmentsForEmployeesInRange(
      employeeIds,
      startStr,
      endStr
    );
    const scheduleOverrides = await loadScheduleOverrides(pool, employeeIds, startStr, endStr);
    reportScheduleOverrides = scheduleOverrides;
    reportEmployeeIds = employeeIds;
    reportAssignmentsByEmployee = assignmentsByEmployee;
    const attendancePolicyContext = await loadAttendancePolicyContext(
      pool,
      employeeIds,
      startStr,
      endStr,
      assignmentsByEmployee
    );

    const holidayByDate = activeHolidayByDate;
    const holidaysInRange = Array.from(holidayByDate.values());
    const leaveCoverageByKey = await getApprovedLeaveCoverageInRange(employeeIds, startStr, endStr);
    const legacyLeaveKeys = await getApprovedLeaveKeysInRange(employeeIds, startStr, endStr);
    const leaveKeys = new Set([...legacyLeaveKeys, ...leaveCoverageByKey.keys()]);

    // 1) Inject synthetic holiday rows for dates with no record — only for employees
    //    scheduled that calendar day (same working-day + assignment rules as absent injection).
    await addHolidayReportRows({
      assignmentsByEmployee,
      employeeIds,
      existingKeys,
      holidaysInRange,
      rows,
      scheduleOverrides,
      scopedDepartmentId,
      userIdToName,
    });

    // 2) Inject exact approved leave coverage where no underlying DTR row exists.
    await addLeaveReportRows({
      assignmentsByEmployee,
      existingKeys,
      leaveCoverageByKey,
      rows,
      scopedDepartmentId,
      userIdToName,
    });

    // 3) Inject synthetic "Absent" rows for working days with no record, only after shift end / for past dates
    // Use HRMS_TIMEZONE so "today" matches the business calendar date, not the server's UTC date.
    const todayStr = todayInHrmsTimezone();
    const nowMinutes = nowMinutesInHrmsTimezone();

    const locatorByKey = await getApprovedLocatorByDateInRange(employeeIds, startStr, endStr);

    // Iterate by calendar date (YYYY-MM-DD) to avoid timezone shifting: e.g. "Day 14" must not show as March 13 in UTC+8.
    const startD = new Date(`${startStr}T12:00:00`); // noon avoids UTC date shift
    const endD = new Date(`${endStr}T12:00:00`);
    await addAbsenceReportRows({
      assignmentsByEmployee,
      attendancePolicyContext,
      employeeIds,
      endD,
      existingKeys,
      holidayByDate,
      leaveKeys,
      locatorByKey,
      nowMinutes,
      rows,
      scheduleOverrides,
      scopedDepartmentId,
      startD,
      todayStr,
      userIdToName,
    });

    // 4) Inject synthetic rows for approved locator slips with no existing DTR row.
    await addLocatorReportRows({
      assignmentsByEmployee,
      existingKeys,
      holidayByDate,
      locatorByKey,
      rows,
      scopedDepartmentId,
      userIdToName,
    });

    // 5) Annotate existing rows with locator metadata for transparency.
    await annotateLocatorReportRows({
      assignmentsByEmployee,
      holidayByDate,
      locatorByKey,
      rows,
      savedShiftsByDate,
    });

    // Reports must use the same date-aware policy precedence as DTR and
    // month-end processing. Attach both the resolved policy and the official
    // per-day contribution after locator/leave/holiday overlays are final.
    await attachReportPolicies({
      assignmentsByEmployee,
      attendancePolicyContext,
      rows,
      savedShiftsByDate,
    });

    rows.sort((a, b) => {
      const dA = a.record_date;
      const dB = b.record_date;
      if (dA !== dB) return String(dB).localeCompare(String(dA));
      // pg may return timestamptz as Date objects; localeCompare needs strings.
      const tInB = b.time_in != null ? String(b.time_in) : '';
      const tInA = a.time_in != null ? String(a.time_in) : '';
      return tInB.localeCompare(tInA);
    });

    return { reportScheduleOverrides, reportEmployeeIds, reportAssignmentsByEmployee };
  }
  return { completeDtrReport };
};
