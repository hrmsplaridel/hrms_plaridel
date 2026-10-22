'use strict';
module.exports = function createDtrControllers({
  HRMS_TIMEZONE,
  _holidaysHasCoverageColumn,
  applyAttendancePolicyPenalties,
  broadcastBiometricUpdate,
  computeLateMinutes,
  computePmLateStatus,
  computeStatusFromShift,
  computeTotalHours,
  computeUndertimeMinutes,
  dtrAuditSnapshot,
  getApprovedLeaveCoverageForDate,
  getAssignmentShiftForDate,
  minutesFromMidnightInTimeZone,
  minutesToTimeStr,
  pool,
  toIsoDateStr,
  todayInHrmsTimezone,
  validateDtrPunchDates,
}) {
  return {
    updateRecord: async (req, res) => {
      let client;
      let transactionStarted = false;
      try {
        const { id } = req.params;
        const {
          time_in,
          break_out,
          break_in,
          time_out,
          total_hours,
          status,
          remarks,
          edit_underlying_attendance,
        } = req.body;
        const editUnderlyingAttendance = edit_underlying_attendance === true;

        client = await pool.connect();
        await client.query('BEGIN');
        transactionStarted = true;

        const rejectEdit = async (statusCode, payload) => {
          await client.query('ROLLBACK');
          transactionStarted = false;
          return res.status(statusCode).json(payload);
        };

        const hasCoverage = await _holidaysHasCoverageColumn();
        const joinCols = hasCoverage
          ? 'h.coverage AS holiday_coverage'
          : 'NULL::text AS holiday_coverage';
        const check = await client.query(
          `SELECT d.*, d.attendance_date::text AS attendance_date_iso, ${joinCols}
       FROM dtr_daily_summary d
       LEFT JOIN holidays h ON h.id = d.holiday_id
       WHERE d.id = $1
       FOR UPDATE OF d`,
          [id]
        );
        if (check.rows.length === 0) {
          return rejectEdit(404, { error: 'Record not found' });
        }

        const existing = check.rows[0];
        const existingCoverage = existing.holiday_coverage || 'whole_day';
        const employeeId = existing.employee_id;
        const dateStr = toIsoDateStr(existing.attendance_date);
        const leaveCoverage = await getApprovedLeaveCoverageForDate(employeeId, dateStr, client);
        if (leaveCoverage && !editUnderlyingAttendance) {
          return rejectEdit(409, {
            error:
              'An approved leave covers this date. Use the Edit underlying attendance action or revoke the leave first.',
            leave_request_id: leaveCoverage.leave_request_id,
          });
        }

        const shiftInfo =
          existing.shift_snapshot || (await getAssignmentShiftForDate(employeeId, dateStr));
        const ti = time_in !== undefined ? time_in : existing.time_in;
        const bo = break_out !== undefined ? break_out : existing.break_out;
        const bi = break_in !== undefined ? break_in : existing.break_in;
        const to = time_out !== undefined ? time_out : existing.time_out;
        const punchDateValidation = validateDtrPunchDates({
          attendanceDate: dateStr,
          punches: { time_in: ti, break_out: bo, break_in: bi, time_out: to },
          shiftInfo,
          todayDate: todayInHrmsTimezone(),
          timeZone: HRMS_TIMEZONE,
        });
        if (!punchDateValidation.valid) {
          return rejectEdit(400, { error: punchDateValidation.error });
        }

        // Reject PM In (break_in) if after shift end time
        if (break_in !== undefined && break_in != null && existing.holiday_id == null) {
          if (shiftInfo && shiftInfo.endMinutes != null) {
            const breakInMins = minutesFromMidnightInTimeZone(break_in);
            const isOvernightShift =
              shiftInfo.startMinutes != null && shiftInfo.endMinutes <= shiftInfo.startMinutes;
            if (!isOvernightShift && breakInMins != null && breakInMins > shiftInfo.endMinutes) {
              return rejectEdit(400, {
                error: `PM clock-in time is after shift end. Shift ends at ${minutesToTimeStr(shiftInfo.endMinutes)}.`,
              });
            }
          }
        }

        const updates = [];
        const values = [];
        let i = 1;
        if (time_in !== undefined) {
          updates.push(`time_in = $${i++}`);
          values.push(time_in);
        }
        if (break_out !== undefined) {
          updates.push(`break_out = $${i++}`);
          values.push(break_out);
        }
        if (break_in !== undefined) {
          updates.push(`break_in = $${i++}`);
          values.push(break_in);
        }
        if (time_out !== undefined) {
          updates.push(`time_out = $${i++}`);
          values.push(time_out);
        }

        const anyTimeChanged =
          time_in !== undefined ||
          break_out !== undefined ||
          break_in !== undefined ||
          time_out !== undefined;
        const computedTotal = computeTotalHours(ti, bo, bi, to, shiftInfo);
        if (total_hours !== undefined) {
          updates.push(`total_hours = $${i++}::numeric`);
          const parsedTotal =
            total_hours === null || total_hours === '' ? null : parseFloat(total_hours);
          values.push(Number.isFinite(parsedTotal) ? parsedTotal : computedTotal);
        } else if (anyTimeChanged) {
          updates.push(`total_hours = $${i++}::numeric`);
          values.push(computedTotal);
        }

        // The API response uses `on_leave` while coverage is active, but that is an
        // overlay and must never be written into the underlying attendance row.
        let resolvedStatus = editUnderlyingAttendance ? undefined : status;
        if (time_in !== undefined) {
          if (existing.holiday_id != null) {
            resolvedStatus = 'holiday';
          } else {
            resolvedStatus = await computeStatusFromShift(employeeId, dateStr, time_in);
          }
        }
        if (resolvedStatus !== undefined) {
          updates.push(`status = $${i++}`);
          values.push(resolvedStatus);
        }

        let resolvedPmStatus = undefined;
        if (break_in !== undefined && existing.holiday_id == null) {
          resolvedPmStatus = bi ? await computePmLateStatus(employeeId, dateStr, bi) : null;
        }
        if (resolvedPmStatus !== undefined) {
          updates.push(`pm_status = $${i++}`);
          values.push(resolvedPmStatus);
        }
        if (remarks !== undefined) {
          updates.push(`remarks = $${i++}`);
          values.push(remarks);
        }

        const finalStatus = resolvedStatus !== undefined ? resolvedStatus : existing.status;
        const isHolidayOrLeave =
          existing.holiday_id != null || finalStatus === 'holiday' || finalStatus === 'on_leave';
        const isPartialSuspension =
          isHolidayOrLeave && (existingCoverage === 'am_only' || existingCoverage === 'pm_only');
        if (anyTimeChanged && (!isHolidayOrLeave || isPartialSuspension)) {
          const bo = break_out !== undefined ? break_out : existing.break_out;
          const rawLate = await computeLateMinutes(
            employeeId,
            dateStr,
            ti,
            bi,
            finalStatus,
            existing.holiday_id,
            existingCoverage
          );
          const rawUnder = await computeUndertimeMinutes(
            employeeId,
            dateStr,
            to,
            bo,
            finalStatus,
            existing.holiday_id,
            existingCoverage,
            ti,
            bi
          );
          const adjusted = await applyAttendancePolicyPenalties(
            employeeId,
            dateStr,
            rawLate,
            rawUnder
          );
          updates.push(`late_minutes = $${i++}`);
          values.push(adjusted.lateMinutes);
          updates.push(`undertime_minutes = $${i++}`);
          values.push(adjusted.undertimeMinutes);
        }

        if (updates.length === 0) {
          return rejectEdit(400, { error: 'No fields to update' });
        }
        if (!existing.shift_snapshot && shiftInfo) {
          updates.push('shift_snapshot = $' + i++ + '::jsonb');
          values.push(JSON.stringify(shiftInfo));
        }
        updates.push("source = 'adjusted'");
        updates.push('updated_at = now()');
        values.push(id);

        const result = await client.query(
          `UPDATE dtr_daily_summary SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING *, attendance_date::text AS attendance_date_iso`,
          values
        );
        const r = result.rows[0];
        const recordDateStr =
          (r.attendance_date_iso && String(r.attendance_date_iso).slice(0, 10)) ||
          toIsoDateStr(existing.attendance_date);

        await client.query(
          `INSERT INTO audit_logs (
         user_id, action, entity_type, entity_id, details, created_at
       ) VALUES (
         $1::uuid, 'dtr_time_entry_adjusted', 'dtr_daily_summary', $2::uuid, $3, now()
       )`,
          [
            req.user?.id || null,
            id,
            JSON.stringify({
              employee_id: String(r.employee_id),
              attendance_date: recordDateStr,
              edited_under_leave_coverage: Boolean(leaveCoverage),
              leave_request_id: leaveCoverage?.leave_request_id || null,
              before: dtrAuditSnapshot(existing),
              after: dtrAuditSnapshot(r),
            }),
          ]
        );

        await client.query('COMMIT');
        transactionStarted = false;

        broadcastBiometricUpdate('dtr_refresh', {
          action: 'dtr_adjusted',
          userId: String(r.employee_id),
          date: recordDateStr,
          userIds: [String(r.employee_id)],
          dates: [recordDateStr],
        });

        res.json({
          id: r.id,
          user_id: r.employee_id,
          record_date: recordDateStr,
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
          updated_at: r.updated_at,
        });
      } catch (err) {
        if (transactionStarted && client) {
          try {
            await client.query('ROLLBACK');
          } catch (_) {
            // Preserve the original update or audit failure.
          }
        }
        console.error('[dtr-daily-summary PUT]', err);
        res.status(500).json({ error: 'Failed to update DTR record' });
      } finally {
        client?.release();
      }
    },
  };
};
