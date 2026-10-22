'use strict';
module.exports = function createDtrControllers({
  MAX_DTR_BULK_REPORT_EMPLOYEES,
  assignmentForBulkReport,
  listDtrDailySummaries,
  parseEmployeeIdList,
  resolveReportableThroughFromAssignments,
  scheduleOverridesForEmployee,
}) {
  return {
    getBulkReport: async (req, res) => {
      try {
        const { employee_ids, start_date, end_date } = req.body || {};
        const parsedEmployeeIds = parseEmployeeIdList(employee_ids);
        if (parsedEmployeeIds.error) {
          return res.status(400).json({ error: parsedEmployeeIds.error });
        }
        if (parsedEmployeeIds.ids.length === 0) {
          return res.status(400).json({ error: 'employee_ids is required' });
        }
        if (!start_date || !end_date) {
          return res.status(400).json({ error: 'start_date and end_date are required' });
        }

        const captured = {
          statusCode: 200,
          body: null,
          headers: {},
          locals: {},
          status(code) {
            this.statusCode = code;
            return this;
          },
          json(body) {
            this.body = body;
            return this;
          },
          setHeader(name, value) {
            this.headers[String(name).toLowerCase()] = value;
          },
        };
        const reportRequest = Object.create(req);
        reportRequest.bulkReport = true;
        Object.defineProperty(reportRequest, 'query', {
          configurable: true,
          enumerable: true,
          value: {
            start_date,
            end_date,
            employee_ids: parsedEmployeeIds.ids,
            recompute: 'true',
          },
        });

        await listDtrDailySummaries(reportRequest, captured);
        if (captured.statusCode >= 400) {
          return res.status(captured.statusCode).json(
            captured.body || {
              error: 'Failed to prepare bulk DTR report',
            }
          );
        }

        const context = captured.locals.dtrReportContext || {};
        const availableIds = new Set((context.employeeIds || []).map((id) => String(id)));
        const recordsByEmployee = new Map();
        for (const row of Array.isArray(captured.body) ? captured.body : []) {
          const employeeId = String(row.user_id || '');
          if (!employeeId) continue;
          const employeeRows = recordsByEmployee.get(employeeId) || [];
          employeeRows.push(row);
          recordsByEmployee.set(employeeId, employeeRows);
        }

        const employees = [];
        const errors = [];
        for (const employeeId of parsedEmployeeIds.ids) {
          if (!availableIds.has(employeeId)) {
            errors.push({ employee_id: employeeId, error: 'Employee was not found' });
            continue;
          }
          const assignmentTimeline = context.assignmentsByEmployee?.get(employeeId) || [];
          employees.push({
            employee_id: employeeId,
            records: recordsByEmployee.get(employeeId) || [],
            assignments: assignmentTimeline.map((assignment) => ({
              ...assignmentForBulkReport(assignment),
              schedule_overrides: scheduleOverridesForEmployee(
                context.scheduleOverrides,
                employeeId,
                assignment
              ),
            })),
            reportable_through: resolveReportableThroughFromAssignments({
              employeeId,
              rangeEnd: context.rangeEnd || String(end_date).slice(0, 10),
              holidayByDate: context.holidayByDate || new Map(),
              assignmentsByEmployee: context.assignmentsByEmployee || new Map(),
            }),
          });
        }

        return res.json({
          start_date: String(start_date).slice(0, 10),
          end_date: String(end_date).slice(0, 10),
          batch_limit: MAX_DTR_BULK_REPORT_EMPLOYEES,
          employees,
          errors,
        });
      } catch (err) {
        console.error('[dtr-daily-summary POST /bulk-report]', err);
        return res.status(500).json({ error: 'Failed to prepare bulk DTR report' });
      }
    },
  };
};
