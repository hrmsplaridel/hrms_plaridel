'use strict';
module.exports = function createDtrComponent({
  computeAttendanceRemark,
  computeUndertimeMinutes,
  evaluateLocatorCoverage,
  getShiftInfoForDateFromAssignments,
  isOvernight,
  locatorAttendanceRemark,
  locatorSegmentsForMissingPunches,
  resolveShiftType,
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
      row.locator_slip_id = locator.id || null;
      row.locator_slip_request_type = locator.request_type || 'locator';
      row.locator_slip_request_type_label = locator.request_type_label || null;
      row.locator_slip_dtr_slot_label = locator.dtr_slot_label || null;
      row.locator_slip_dtr_print_label = locator.dtr_print_label || null;
      row.locator_slip_coverage_mode = locator.coverage_mode || null;
      row.locator_slip_office = locator.office || null;
      row.locator_slip_reason = locator.reason || null;
      row.locator_slip_segments = locator.segments || [];

      const rowDateStr = String(row.record_date).slice(0, 10);
      const holidayInfo = holidayByDate.get(rowDateStr) || null;
      const shiftInfo =
        savedShiftsByDate.get(rowKey) ||
        getShiftInfoForDateFromAssignments(assignmentsByEmployee, row.user_id, rowDateStr);
      const hasFullShiftCoverage = evaluateLocatorCoverage({
        locator,
        shiftInfo,
        holidayInfo,
        date: rowDateStr,
      }).isFullCoverage;
      const hasAnyLog = !!(row.time_in || row.break_out || row.break_in || row.time_out);
      const effectiveLocatorSegments = locatorSegmentsForMissingPunches(locator, row);

      // Physical punches are authoritative. Locator coverage can fill missing
      // slots, but it must not erase penalties calculated from real punches.
      if (
        !hasAnyLog &&
        hasFullShiftCoverage &&
        row.status !== 'holiday' &&
        row.status !== 'on_leave'
      ) {
        row.late_minutes = 0;
        row.undertime_minutes = 0;
      }

      if (
        !hasAnyLog &&
        hasFullShiftCoverage &&
        row.status !== 'holiday' &&
        row.status !== 'on_leave'
      ) {
        row.status = 'on_field';
        row.late_minutes = 0;
        row.undertime_minutes = 0;
        row.attendance_remark = locatorAttendanceRemark(locator);
      }

      // Re-evaluate remark/undertime with locator segment substitution so
      // partial approved locator segments (e.g., AM IN) can satisfy
      // completeness checks with existing punches.
      const coverage = holidayInfo?.coverage || row.coverage || null;
      row.undertime_minutes = await computeUndertimeMinutes(
        row.user_id,
        rowDateStr,
        row.time_out,
        row.break_out,
        row.status,
        row.holiday_id,
        coverage,
        row.time_in,
        row.break_in,
        effectiveLocatorSegments,
        shiftInfo
      );
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
