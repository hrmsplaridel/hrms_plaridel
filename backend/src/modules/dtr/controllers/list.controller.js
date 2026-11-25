'use strict';
module.exports = function createDtrComponent({
  DEFAULT_DTR_PAGE_SIZE,
  MAX_DTR_PAGE_SIZE,
  MAX_DTR_RANGE_DAYS,
  annotateLocatorReportRows,
  completeDtrReport,
  dtrRowConcurrency,
  getAssignmentsForEmployeesInRange,
  getApprovedLocatorByDateInRange,
  inclusiveIsoDateRangeDays,
  isTruthyQueryFlag,
  loadAttendancePolicyContext,
  loadHolidayOverlayMap,
  mapConcurrent,
  mapSavedAttendanceRow,
  parseEmployeeIdList,
  listSavedSummaryRows,
  pool,
  resolveDtrDailySummaryScope,
  resolveReportableThrough,
  toIsoDateStr,
}) {
  // GET /api/dtr-daily-summary - list for admin (filters: start_date, end_date, employee_id, department_id, limit, offset)
  // - No date range: `limit` applies to SQL only (default 500, max 1000), e.g. dashboard "recent" list.
  // - With start_date + end_date: the final merged result is paginated and exposes its total count.
  async function listDtrDailySummaries(req, res) {
    try {
      const {
        start_date,
        end_date,
        employee_id,
        employee_ids,
        department_id,
        limit: limitRaw,
        offset: offsetRaw,
      } = req.query;
      if (!!start_date !== !!end_date) {
        return res.status(400).json({ error: 'start_date and end_date must be provided together' });
      }
      const hasDateRange = !!(start_date && end_date);
      if (hasDateRange) {
        const rangeDays = inclusiveIsoDateRangeDays(start_date, end_date);
        if (rangeDays == null) {
          return res.status(400).json({ error: 'Invalid attendance date range' });
        }
        if (rangeDays > MAX_DTR_RANGE_DAYS) {
          return res.status(400).json({
            error: `Attendance date range cannot exceed ${MAX_DTR_RANGE_DAYS} days`,
          });
        }
      }
      const recomputeExistingRows = isTruthyQueryFlag(req.query.recompute);
      const {
        privileged,
        employeeId: scopedEmployeeId,
        departmentId: scopedDepartmentId,
      } = resolveDtrDailySummaryScope(req.user, { employee_id, department_id });
      const parsedEmployeeIds = parseEmployeeIdList(employee_ids);
      if (parsedEmployeeIds.error) {
        return res.status(400).json({ error: parsedEmployeeIds.error });
      }
      const requestedEmployeeIds = parsedEmployeeIds.ids;
      if (requestedEmployeeIds.length > 0 && !privileged) {
        return res.status(403).json({ error: 'Bulk employee DTR access is not allowed' });
      }
      if (!privileged && !scopedEmployeeId) {
        return res.status(401).json({ error: 'Authenticated employee id is required' });
      }
      const sqlMaxRows = hasDateRange
        ? Math.min(parseInt(req.query.sql_cap, 10) || 100000, 250000)
        : Math.min(parseInt(limitRaw, 10) || 500, 1000);
      const rawRows = await listSavedSummaryRows({
        privileged,
        scopedEmployeeId,
        startDate: start_date,
        endDate: end_date,
        requestedEmployeeIds,
        scopedDepartmentId,
        sqlMaxRows,
      });

      const startStr = start_date ? String(start_date).slice(0, 10) : null;
      const endStr = end_date ? String(end_date).slice(0, 10) : null;
      const rawEmployeeIds = [...new Set(rawRows.map((r) => r.employee_id).filter(Boolean))];
      const rawDateStrings = rawRows
        .map(
          (r) =>
            (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
            toIsoDateStr(r.attendance_date)
        )
        .filter(Boolean)
        .sort();
      const rawRangeStart = startStr || rawDateStrings[0] || null;
      const rawRangeEnd = endStr || rawDateStrings[rawDateStrings.length - 1] || null;
      const rawAssignmentsByEmployee =
        rawEmployeeIds.length > 0 && rawRangeStart && rawRangeEnd
          ? await getAssignmentsForEmployeesInRange(rawEmployeeIds, rawRangeStart, rawRangeEnd)
          : new Map();
      const rawAttendancePolicyContext =
        rawEmployeeIds.length > 0 && rawRangeStart && rawRangeEnd
          ? await loadAttendancePolicyContext(
              pool,
              rawEmployeeIds,
              rawRangeStart,
              rawRangeEnd,
              rawAssignmentsByEmployee
            )
          : null;
      const activeHolidayByDate =
        rawRangeStart && rawRangeEnd
          ? await loadHolidayOverlayMap(pool, rawRangeStart, rawRangeEnd)
          : new Map();

      let reportEmployeeIds = rawEmployeeIds;
      let reportAssignmentsByEmployee = rawAssignmentsByEmployee;
      let reportScheduleOverrides = new Map();
      const savedShiftsByDate = new Map();
      const rows = await mapConcurrent(rawRows, dtrRowConcurrency, async (r) =>
        mapSavedAttendanceRow(r, {
          activeHolidayByDate,
          rawAssignmentsByEmployee,
          rawAttendancePolicyContext,
          recomputeExistingRows,
          savedShiftsByDate,
        })
      );

      // Inject synthetic holiday rows for dates with no record
      if (startStr && endStr) {
        ({ reportScheduleOverrides, reportEmployeeIds, reportAssignmentsByEmployee } =
          await completeDtrReport({
            activeHolidayByDate,
            endStr,
            rawRows,
            requestedEmployeeIds,
            rows,
            savedShiftsByDate,
            scopedDepartmentId,
            scopedEmployeeId,
            startStr,
          }));
      } else if (rawEmployeeIds.length && rawRangeStart && rawRangeEnd) {
        await annotateLocatorReportRows({ rows, savedShiftsByDate,
          assignmentsByEmployee: rawAssignmentsByEmployee,
          attendancePolicyContext: rawAttendancePolicyContext,
          holidayByDate: activeHolidayByDate,
          locatorByKey: await getApprovedLocatorByDateInRange(rawEmployeeIds, rawRangeStart, rawRangeEnd),
        });
      }

      const authorizedRows = privileged
        ? rows
        : rows.filter((row) => String(row.user_id) === String(scopedEmployeeId));
      if (req.bulkReport && res.locals) {
        res.locals.dtrReportContext = {
          employeeIds: reportEmployeeIds,
          assignmentsByEmployee: reportAssignmentsByEmployee,
          scheduleOverrides: reportScheduleOverrides,
          holidayByDate: activeHolidayByDate,
          rangeStart: startStr,
          rangeEnd: endStr,
        };
      }
      let payload = authorizedRows;
      if (hasDateRange && !req.bulkReport) {
        if (scopedEmployeeId && endStr) {
          const reportableThrough = await resolveReportableThrough({
            employeeId: scopedEmployeeId,
            rangeEnd: endStr,
            holidayByDate: activeHolidayByDate,
          });
          res.setHeader('X-Reportable-Through', reportableThrough);
        }
        const off = Math.max(0, parseInt(offsetRaw, 10) || 0);
        const pageSize = Math.min(
          Math.max(1, parseInt(limitRaw, 10) || DEFAULT_DTR_PAGE_SIZE),
          MAX_DTR_PAGE_SIZE
        );
        res.setHeader(
          'Access-Control-Expose-Headers',
          'X-Total-Count, X-Limit, X-Offset, X-Reportable-Through'
        );
        res.setHeader('X-Total-Count', String(authorizedRows.length));
        res.setHeader('X-Limit', String(pageSize));
        res.setHeader('X-Offset', String(off));
        payload = authorizedRows.slice(off, off + pageSize);
      }

      res.json(payload);
    } catch (err) {
      console.error('[dtr-daily-summary GET]', err);
      res.status(500).json({ error: 'Failed to fetch DTR summary' });
    }
  }
  return { listDtrDailySummaries };
};
