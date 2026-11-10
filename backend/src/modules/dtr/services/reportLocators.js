'use strict';
const { projectAttendanceCoverage } = require('../../../services/attendanceCoverageProjection');
module.exports = function createDtrComponent({
  computeAttendanceRemark,
  evaluateLocatorCoverage,
  getShiftInfoForDateFromAssignments,
  isOvernight,
  locatorAttendanceRemark,
  resolveShiftType,
  resolveAttendancePolicy,
  getAttendancePolicyForEmployeeDate,
}) {
  async function addLocatorReportRows({
    assignmentsByEmployee,
    existingKeys,
    holidayByDate,
    locatorByKey,
    rows,
    scopedDepartmentId,
    userIdToName,
  }) {
    for (const [key, locator] of locatorByKey.entries()) {
      if (existingKeys.has(key)) continue;
      const [empId, dateStr] = key.split('|');
      const shiftInfo = getShiftInfoForDateFromAssignments(assignmentsByEmployee, empId, dateStr);
      if (
        scopedDepartmentId &&
        String(shiftInfo?.departmentId || '') !== String(scopedDepartmentId)
      ) {
        continue;
      }
      const holidayInfo = holidayByDate.get(dateStr) || null;
      const locatorCoverage = evaluateLocatorCoverage({
        locator,
        shiftInfo,
        holidayInfo,
        date: dateStr,
      });
      if (!locatorCoverage.isFullCoverage) continue;
      existingKeys.add(key);
      rows.push({
        id: null,
        user_id: empId,
        record_date: dateStr,
        time_in: null,
        break_out: null,
        break_in: null,
        time_out: null,
        total_hours: null,
        late_minutes: 0,
        undertime_minutes: 0,
        status: 'on_field',
        pm_status: null,
        remarks: null,
        source: 'adjusted',
        attendance_remark: locatorAttendanceRemark(locator),
        holiday_id: null,
        leave_request_id: null,
        locator_slip_id: locator.id || null,
        locator_slip_request_type: locator.request_type || 'locator',
        locator_slip_request_type_label: locator.request_type_label || null,
        locator_slip_dtr_slot_label: locator.dtr_slot_label || null,
        locator_slip_dtr_print_label: locator.dtr_print_label || null,
        locator_slip_coverage_mode: locator.coverage_mode || null,
        locator_slip_office: locator.office || null,
        locator_slip_reason: locator.reason || null,
        locator_slip_segments: locator.segments || [],
        holiday_name: null,
        holiday_type: null,
        coverage: null,
        created_at: null,
        updated_at: null,
        employee_name: userIdToName[empId] || null,
        shift_punch_mode: resolveShiftType(shiftInfo) || 'auto',
        shift_overnight: isOvernight(shiftInfo),
      });
    }
  }

  async function annotateLocatorReportRows({
    attendancePolicyContext,
    assignmentsByEmployee,
    holidayByDate,
    locatorByKey,
    rows,
    savedShiftsByDate,
  }) {
    for (const row of rows) {
      const rowKey = `${row.user_id}|${row.record_date}`;
      const locator = locatorByKey.get(rowKey);
      if (!locator) continue;
      const rowDateStr = String(row.record_date).slice(0, 10);
      const holidayInfo = holidayByDate.get(rowDateStr) || null;
      if (row.status === 'on_leave' || holidayInfo?.coverage === 'whole_day') continue;
      row.locator_slip_id = locator.id || null;
      row.locator_slip_request_type = locator.request_type || 'locator';
      row.locator_slip_request_type_label = locator.request_type_label || null;
      row.locator_slip_dtr_slot_label = locator.dtr_slot_label || null;
      row.locator_slip_dtr_print_label = locator.dtr_print_label || null;
      row.locator_slip_coverage_mode = locator.coverage_mode || null;
      row.locator_slip_office = locator.office || null;
      row.locator_slip_reason = locator.reason || null;
      row.locator_slip_segments = locator.segments || [];

      const shiftInfo =
        savedShiftsByDate.get(rowKey) ||
        getShiftInfoForDateFromAssignments(assignmentsByEmployee, row.user_id, rowDateStr);
      const policy = attendancePolicyContext
        ? resolveAttendancePolicy(attendancePolicyContext, row.user_id, rowDateStr, shiftInfo)
        : await getAttendancePolicyForEmployeeDate(row.user_id, rowDateStr);
      Object.assign(row, await projectAttendanceCoverage({ record: row, date: rowDateStr,
        shiftInfo, holidayInfo, locator, policy }));
      const effectiveLocatorSegments = locator.segments || [];
      row.attendance_remark = await computeAttendanceRemark(
        row,
        shiftInfo,
        row.holiday_id,
        row.leave_request_id,
        holidayInfo,
        effectiveLocatorSegments
      );
    }
  }
  return { addLocatorReportRows, annotateLocatorReportRows };
};
