'use strict';
module.exports = function createDtrControllers({
  broadcastBiometricUpdate,
  getApprovedLeaveCoverageForDate,
  isTruthyQueryFlag,
  pool,
}) {
  return {
    listDeletions: async (req, res) => {
      try {
        const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 100, 1), 500);
        const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
        const includeRestored = isTruthyQueryFlag(req.query.include_restored);
        const params = [];
        const conditions = [];
        let i = 1;

        if (!includeRestored) conditions.push('dd.restored_at IS NULL');
        if (req.query.employee_id) {
          conditions.push(`dd.employee_id = $${i++}::uuid`);
          params.push(req.query.employee_id);
        }
        if (req.query.start_date) {
          conditions.push(`dd.attendance_date >= $${i++}::date`);
          params.push(req.query.start_date);
        }
        if (req.query.end_date) {
          conditions.push(`dd.attendance_date <= $${i++}::date`);
          params.push(req.query.end_date);
        }

        const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
        params.push(limit, offset);
        const result = await pool.query(
          `SELECT dd.id,
              dd.deleted_dtr_summary_id,
              dd.employee_id,
              dd.attendance_date::text AS attendance_date,
              dd.source,
              dd.reason,
              dd.deleted_by,
              dd.record_snapshot,
              dd.deleted_at,
              dd.restored_by,
              dd.restoration_reason,
              dd.restored_at,
              employee.full_name AS employee_name,
              deleted_actor.full_name AS deleted_by_name,
              restored_actor.full_name AS restored_by_name,
              COUNT(*) OVER()::int AS total_count
       FROM dtr_daily_summary_deletions dd
       LEFT JOIN users employee ON employee.id = dd.employee_id
       LEFT JOIN users deleted_actor ON deleted_actor.id = dd.deleted_by
       LEFT JOIN users restored_actor ON restored_actor.id = dd.restored_by
       ${where}
       ORDER BY (dd.restored_at IS NULL) DESC, dd.deleted_at DESC
       LIMIT $${i++} OFFSET $${i}`,
          params
        );

        res.json({
          items: result.rows.map(({ total_count, ...row }) => row),
          total: result.rows[0]?.total_count || 0,
        });
      } catch (err) {
        console.error('[dtr-daily-summary deletions GET]', err);
        res.status(500).json({ error: 'Failed to fetch deleted DTR entries' });
      }
    },

    deleteRecord: async (req, res) => {
      const reason = String(req.body?.reason || '').trim();
      if (reason.length < 3) {
        return res
          .status(400)
          .json({ error: 'A deletion reason of at least 3 characters is required' });
      }
      if (reason.length > 1000) {
        return res.status(400).json({ error: 'Deletion reason must not exceed 1000 characters' });
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const target = await client.query(
          `SELECT d.*, d.attendance_date::text AS attendance_date_iso
       FROM dtr_daily_summary d
       WHERE d.id = $1
       FOR UPDATE`,
          [req.params.id]
        );
        if (target.rowCount === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Record not found' });
        }

        const row = target.rows[0];
        const leaveCoverage = await getApprovedLeaveCoverageForDate(
          row.employee_id,
          row.attendance_date_iso,
          client
        );
        if (leaveCoverage) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error:
              'This attendance row is covered by approved leave and cannot be deleted. Revoke the leave before deleting the underlying attendance.',
            leave_request_id: leaveCoverage.leave_request_id,
          });
        }
        await client.query(
          `INSERT INTO dtr_daily_summary_deletions (
         deleted_dtr_summary_id,
         employee_id,
         attendance_date,
         source,
         reason,
         deleted_by,
         record_snapshot
       ) VALUES ($1::uuid, $2::uuid, $3::date, $4, $5, $6::uuid, $7::jsonb)`,
          [
            row.id,
            row.employee_id,
            row.attendance_date_iso,
            row.source,
            reason,
            req.user?.id || null,
            JSON.stringify(row),
          ]
        );
        await client.query('DELETE FROM dtr_daily_summary WHERE id = $1', [req.params.id]);

        await client.query('COMMIT');
        const deletedDateStr = row.attendance_date_iso
          ? String(row.attendance_date_iso).slice(0, 10)
          : null;
        broadcastBiometricUpdate('dtr_refresh', {
          action: 'dtr_deleted',
          userId: String(row.employee_id),
          date: deletedDateStr,
          userIds: [String(row.employee_id)],
          dates: deletedDateStr ? [deletedDateStr] : [],
        });
        res.status(204).send();
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[dtr-daily-summary DELETE]', err);
        res.status(500).json({ error: 'Failed to delete DTR record' });
      } finally {
        client.release();
      }
    },
  };
};
