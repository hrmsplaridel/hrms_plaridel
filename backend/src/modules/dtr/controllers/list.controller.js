'use strict';
module.exports = function createDtrComponent({
  DEFAULT_DTR_PAGE_SIZE,
  MAX_DTR_PAGE_SIZE,
  MAX_DTR_RANGE_DAYS,
  _holidaysHasCoverageColumn,
  completeDtrReport,
  dtrRowConcurrency,
  getAssignmentsForEmployeesInRange,
  inclusiveIsoDateRangeDays,
  isTruthyQueryFlag,
  loadAttendancePolicyContext,
  loadHolidayOverlayMap,
  mapConcurrent,
  mapSavedAttendanceRow,
  parseEmployeeIdList,
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
      const params = [];
      const conditions = [];
      let i = 1;
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
      if (!privileged) {
        conditions.push(`d.employee_id = $${i++}`);
        params.push(scopedEmployeeId);
      }
      if (start_date) {
        conditions.push(`d.attendance_date >= $${i++}`);
        params.push(start_date);
      }
      if (end_date) {
        conditions.push(`d.attendance_date <= $${i++}`);
        params.push(end_date);
      }
      if (scopedEmployeeId && privileged) {
        conditions.push(`d.employee_id = $${i++}`);
        params.push(scopedEmployeeId);
      }
      if (requestedEmployeeIds.length > 0) {
        conditions.push(`d.employee_id = ANY($${i++}::uuid[])`);
        params.push(requestedEmployeeIds);
      }
      if (scopedDepartmentId) {
        const depIdx = i;
        conditions.push(`(
        SELECT a.department_id
        FROM assignments a
        WHERE a.employee_id = d.employee_id
          AND a.effective_from <= d.attendance_date
          AND (a.effective_to IS NULL OR a.effective_to >= d.attendance_date)
        ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
        LIMIT 1
      ) = $${depIdx}::uuid`);
        params.push(scopedDepartmentId);
        i += 1;
      }
      const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
      const sqlMaxRows = hasDateRange
        ? Math.min(parseInt(req.query.sql_cap, 10) || 100000, 250000)
        : Math.min(parseInt(limitRaw, 10) || 500, 1000);
      params.push(sqlMaxRows);

      const hasCoverage = await _holidaysHasCoverageColumn();
      const joinCols = hasCoverage
        ? 'h.name AS holiday_name, h.holiday_type AS holiday_type, h.coverage AS holiday_coverage'
        : 'h.name AS holiday_name, h.holiday_type AS holiday_type, NULL::text AS holiday_coverage';
      const result = await pool.query(
        `SELECT d.id, d.employee_id, d.attendance_date, d.attendance_date::text AS attendance_date_iso, d.time_in, d.break_out, d.break_in, d.time_out, d.total_hours,
              d.late_minutes, d.undertime_minutes, d.status, d.pm_status, d.remarks, d.source, d.holiday_id, d.shift_snapshot,
              d.leave_request_id AS base_leave_request_id,
              dlc.id AS leave_coverage_id,
              COALESCE(dlc.leave_request_id, d.leave_request_id) AS leave_request_id,
              lr.status AS leave_request_status,
              d.created_at, d.updated_at,
              u.full_name AS employee_name,
              ${joinCols},
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name
       FROM dtr_daily_summary d
       LEFT JOIN users u ON u.id = d.employee_id
       LEFT JOIN holidays h ON h.id = d.holiday_id
       LEFT JOIN dtr_leave_coverage dlc
         ON dlc.employee_id = d.employee_id
        AND dlc.attendance_date = d.attendance_date
        AND EXISTS (
          SELECT 1 FROM leave_requests approved_request
          WHERE approved_request.id = dlc.leave_request_id
            AND approved_request.status = 'approved'
        )
       LEFT JOIN leave_requests lr ON lr.id = COALESCE(dlc.leave_request_id, d.leave_request_id)
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       ${where}
       ORDER BY d.attendance_date DESC, d.time_in DESC NULLS LAST
       LIMIT $${i}`,
        params
      );
      const rawRows = result.rows;
      if (!hasCoverage) for (const r of rawRows) r.holiday_coverage = 'whole_day';

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
