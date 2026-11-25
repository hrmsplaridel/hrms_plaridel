'use strict';
module.exports = function createDtrControllers({ broadcastBiometricUpdate, pool }) {
  const {
    findSummaryForDay,
    insertRestoredSummary,
    lockDeletion,
    markDeletionRestored,
  } = require('../repositories/deletionAudit')({ pool });
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
        const deletionResult = await lockDeletion(client, req.params.deletionId);
        if (deletionResult.rowCount === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Deleted DTR entry not found' });
        }

        const deletion = deletionResult.rows[0];
        if (deletion.restored_at) {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: 'This DTR entry has already been restored' });
        }

        const existing = await findSummaryForDay(
          client,
          deletion.employee_id,
          deletion.attendance_date
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

        const restored = await insertRestoredSummary(client, {
          deletion,
          snapshot,
          status,
          pmStatus,
          source,
        });

        await markDeletionRestored(client, {
          deletionId: deletion.id,
          actorId: req.user?.id || null,
          reason,
        });
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
