'use strict';
module.exports = function createDtrControllers({ broadcastBiometricUpdate, pool }) {
  return {
    restoreRecord: async (req, res) => {
      const reason = String(req.body?.reason || '').trim();
      if (reason.length < 3) {
        return res
          .status(400)
          .json({ error: 'A restoration reason of at least 3 characters is required' });
      }
      if (reason.length > 1000) {
        return res
          .status(400)
          .json({ error: 'Restoration reason must not exceed 1000 characters' });
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const deletionResult = await client.query(
          `SELECT *
       FROM dtr_daily_summary_deletions
       WHERE id = $1::uuid
       FOR UPDATE`,
          [req.params.deletionId]
        );
        if (deletionResult.rowCount === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Deleted DTR entry not found' });
        }

        const deletion = deletionResult.rows[0];
        if (deletion.restored_at) {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: 'This DTR entry has already been restored' });
        }

        const existing = await client.query(
          `SELECT id
       FROM dtr_daily_summary
       WHERE employee_id = $1::uuid AND attendance_date = $2::date
       LIMIT 1`,
          [deletion.employee_id, deletion.attendance_date]
        );
        if (existing.rowCount > 0) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error:
              'Attendance already exists for this employee and date. Remove the corrected entry before restoring the deleted record.',
          });
        }

        const snapshot = deletion.record_snapshot || {};
        const source = ['system', 'manual', 'adjusted'].includes(snapshot.source)
          ? snapshot.source
          : 'adjusted';
        const status = [
          'present',
          'late',
          'absent',
          'on_leave',
          'holiday',
          'rest_day',
          'incomplete',
        ].includes(snapshot.status)
          ? snapshot.status
          : 'incomplete';
        const pmStatus = ['present', 'late'].includes(snapshot.pm_status)
          ? snapshot.pm_status
          : null;

        const restored = await client.query(
          `INSERT INTO dtr_daily_summary (
         id, employee_id, attendance_date,
         assignment_id, shift_id, attendance_policy_id, holiday_id, leave_request_id,
         time_in, time_out, break_in, break_out,
         late_minutes, undertime_minutes, overtime_minutes, total_hours,
         status, pm_status, source, remarks, created_at, updated_at
       ) VALUES (
         $1::uuid, $2::uuid, $3::date,
         (SELECT id FROM assignments WHERE id = $4::uuid),
         (SELECT id FROM shifts WHERE id = $5::uuid),
         (SELECT id FROM attendance_policies WHERE id = $6::uuid),
         (SELECT id FROM holidays WHERE id = $7::uuid),
         (SELECT id FROM leave_requests WHERE id = $8::uuid),
         $9::timestamptz, $10::timestamptz, $11::timestamptz, $12::timestamptz,
         $13, $14, $15, $16::numeric,
         $17, $18, $19, $20, COALESCE($21::timestamptz, now()), now()
       )
       RETURNING id, employee_id, attendance_date::text AS attendance_date, source, status`,
          [
            deletion.deleted_dtr_summary_id,
            deletion.employee_id,
            deletion.attendance_date,
            snapshot.assignment_id || null,
            snapshot.shift_id || null,
            snapshot.attendance_policy_id || null,
            snapshot.holiday_id || null,
            snapshot.leave_request_id || null,
            snapshot.time_in || null,
            snapshot.time_out || null,
            snapshot.break_in || null,
            snapshot.break_out || null,
            Math.max(0, parseInt(snapshot.late_minutes, 10) || 0),
            Math.max(0, parseInt(snapshot.undertime_minutes, 10) || 0),
            Math.max(0, parseInt(snapshot.overtime_minutes, 10) || 0),
            Math.max(0, parseFloat(snapshot.total_hours) || 0),
            status,
            pmStatus,
            source,
            snapshot.remarks || null,
            snapshot.created_at || null,
          ]
        );

        await client.query(
          `UPDATE dtr_daily_summary_deletions
       SET restored_by = $2::uuid,
           restoration_reason = $3,
           restored_at = now()
       WHERE id = $1::uuid`,
          [deletion.id, req.user?.id || null, reason]
        );
        await client.query('COMMIT');

        const row = restored.rows[0];
        broadcastBiometricUpdate('dtr_refresh', {
          action: 'dtr_restored',
          userId: String(row.employee_id),
          date: row.attendance_date,
          userIds: [String(row.employee_id)],
          dates: [row.attendance_date],
        });
        res.json(row);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        if (err.code === '23505') {
          return res
            .status(409)
            .json({ error: 'Attendance already exists for this employee and date' });
        }
        console.error('[dtr-daily-summary deletion restore POST]', err);
        res.status(500).json({ error: 'Failed to restore DTR entry' });
      } finally {
        client.release();
      }
    },
  };
};
