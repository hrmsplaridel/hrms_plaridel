'use strict';
module.exports = function createDtrControllers({
  broadcastBiometricUpdate,
  getApprovedLeaveCoverageForDate,
  isTruthyQueryFlag,
  pool,
}) {
  const {
    deleteSummary,
    insertDeletionRecord,
    listDeletions: listDeletionAudit,
    lockSummaryForDeletion,
  } = require('../repositories/deletionAudit')({ pool });
  return {
    listDeletions: async (req, res) => {
      try {
        const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 100, 1), 500);
        const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
        const includeRestored = isTruthyQueryFlag(req.query.include_restored);
        const rows = await listDeletionAudit({
          includeRestored,
          employeeId: req.query.employee_id,
          startDate: req.query.start_date,
          endDate: req.query.end_date,
          limit,
          offset,
        });

        res.json({
          items: rows.map(({ total_count, ...row }) => row),
          total: rows[0]?.total_count || 0,
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
        const target = await lockSummaryForDeletion(client, req.params.id);
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
        await insertDeletionRecord(client, {
          row,
          reason,
          actorId: req.user?.id || null,
        });
        await deleteSummary(client, req.params.id);

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
