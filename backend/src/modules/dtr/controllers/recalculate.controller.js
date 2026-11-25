'use strict';
module.exports = function createDtrControllers({
  _holidaysHasCoverageColumn,
  applyAttendancePolicyPenalties,
  broadcastBiometricUpdate,
  computeAttendanceRemark,
  computeLateMinutes,
  computePmLateStatus,
  computeStatusFromShift,
  computeTotalHoursFromRecord,
  computeUndertimeMinutes,
  dtrAuditSnapshot,
  getAssignmentShiftForDate,
  loadHolidayOverlayMap,
  pool,
  resolveShiftType,
  toIsoDateStr,
}) {
  const {
    applyRecalculation,
    insertRecalculationAudit,
    lockSummaryForRecalculation,
  } = require('../repositories/summaryRecords')({ _holidaysHasCoverageColumn, pool });
  return {
    recalculateRecord: async (req, res) => {
      let client;
      let transactionStarted = false;
      try {
        const { id } = req.params;
        client = await pool.connect();
        await client.query('BEGIN');
        transactionStarted = true;

        const rejectRecalc = async (statusCode, payload) => {
          await client.query('ROLLBACK');
          transactionStarted = false;
          return res.status(statusCode).json(payload);
        };

        const check = await lockSummaryForRecalculation(client, id);
        if (check.rows.length === 0) {
          return rejectRecalc(404, { error: 'Record not found' });
        }

        const existing = check.rows[0];
        const employeeId = existing.employee_id;
        // Preserve the PostgreSQL calendar date instead of shifting a Date to UTC.
        const dateStr =
          (existing.attendance_date_iso && String(existing.attendance_date_iso).slice(0, 10)) ||
          toIsoDateStr(existing.attendance_date);
        const holidayByDate = await loadHolidayOverlayMap(client, dateStr, dateStr);
        const holidayInfo = holidayByDate.get(dateStr) || null;
        const holidayId = holidayInfo?.id || null;
        const coverage = holidayInfo?.coverage || null;
        const shiftInfo =
          existing.shift_snapshot || (await getAssignmentShiftForDate(employeeId, dateStr));

        const shiftType = resolveShiftType(shiftInfo);
        const statusTimeIn =
          shiftType === 'single_session' ? existing.time_in || existing.break_in : existing.time_in;
        let status = existing.status;
        if (holidayId != null && coverage === 'whole_day') {
          status = 'holiday';
        } else if (status !== 'on_leave') {
          status = statusTimeIn
            ? await computeStatusFromShift(employeeId, dateStr, statusTimeIn)
            : existing.status === 'holiday'
              ? 'absent'
              : existing.status;
        }

        let pmStatus = existing.pm_status;
        if (holidayId == null && status !== 'on_leave') {
          pmStatus = existing.break_in
            ? await computePmLateStatus(employeeId, dateStr, existing.break_in)
            : null;
        }

        const totalHours = computeTotalHoursFromRecord(existing, shiftInfo);
        let lateMinutes = 0;
        let undertimeMinutes = 0;
        const isHolidayOrLeave = holidayId != null || status === 'holiday' || status === 'on_leave';
        const isPartialSuspension =
          isHolidayOrLeave && (coverage === 'am_only' || coverage === 'pm_only');
        if (!isHolidayOrLeave || isPartialSuspension) {
          const rawLate = await computeLateMinutes(
            employeeId,
            dateStr,
            existing.time_in,
            existing.break_in,
            status,
            holidayId,
            coverage
          );
          const rawUnder = await computeUndertimeMinutes(
            employeeId,
            dateStr,
            existing.time_out,
            existing.break_out,
            status,
            holidayId,
            coverage,
            existing.time_in,
            existing.break_in
          );
          const adjusted = await applyAttendancePolicyPenalties(
            employeeId,
            dateStr,
            rawLate,
            rawUnder
          );
          lateMinutes = adjusted.lateMinutes;
          undertimeMinutes = adjusted.undertimeMinutes;
        }

        const attendanceRemark = await computeAttendanceRemark(
          {
            ...existing,
            status,
            late_minutes: lateMinutes,
            undertime_minutes: undertimeMinutes,
            holiday_id: holidayId,
            holiday_name: holidayInfo?.name || null,
            coverage,
          },
          shiftInfo,
          holidayId,
          existing.leave_request_id,
          holidayInfo
        );

        const r = await applyRecalculation(client, {
          summaryId: id,
          totalHours,
          lateMinutes,
          undertimeMinutes,
          status,
          pmStatus,
          holidayId,
        });

        await insertRecalculationAudit(client, {
          actorId: req.user?.id || null,
          summaryId: id,
          details: {
            employee_id: String(r.employee_id),
            attendance_date: dateStr,
            before: dtrAuditSnapshot(existing),
            after: dtrAuditSnapshot(r),
          },
        });

        await client.query('COMMIT');
        transactionStarted = false;

        broadcastBiometricUpdate('dtr_refresh', {
          action: 'dtr_recalculated',
          userId: String(r.employee_id),
          date: dateStr,
          userIds: [String(r.employee_id)],
          dates: [dateStr],
        });

        res.json({
          id: r.id,
          user_id: r.employee_id,
          record_date: dateStr,
          time_in: r.time_in,
          break_out: r.break_out,
          break_in: r.break_in,
          time_out: r.time_out,
          total_hours: r.total_hours != null ? parseFloat(r.total_hours) : null,
          late_minutes: r.late_minutes != null ? parseInt(r.late_minutes, 10) : 0,
          undertime_minutes: r.undertime_minutes != null ? parseInt(r.undertime_minutes, 10) : 0,
          status: r.status,
          pm_status: r.pm_status,
          source: r.source || null,
          attendance_remark: attendanceRemark,
          updated_at: r.updated_at,
        });
      } catch (err) {
        if (transactionStarted && client) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {
            // Preserve original recalculation failure.
          }
        }
        console.error('[dtr-daily-summary recalculate POST]', err);
        res.status(500).json({ error: 'Failed to recalculate DTR record' });
      } finally {
        client?.release();
      }
    },
  };
};
