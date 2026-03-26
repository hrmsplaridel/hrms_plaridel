const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { processBiometricLogsToSummary } = require('../services/biometricProcessing');

const router = express.Router();
const protect = [authMiddleware];

/** Middleware: allow if X-Api-Key matches BIO_SYNC_API_KEY, else require JWT auth. */
function pushAuth(req, res, next) {
  const apiKey = req.get('X-Api-Key');
  const expectedKey = process.env.BIO_SYNC_API_KEY;
  if (expectedKey && apiKey === expectedKey) {
    return next();
  }
  authMiddleware(req, res, (err) => {
    if (err) return next(err);
    requireAdmin(req, res, next);
  });
}

function toIsoDate(val) {
  if (!val) return null;
  const d = val instanceof Date ? val : new Date(val);
  if (isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

/**
 * GET /api/biometric-attendance-logs/devices
 * Fetch active biometric devices for the external sync service.
 * Auth: X-Api-Key header
 */
router.get('/devices', pushAuth, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, ip_address, device_id FROM biometric_devices WHERE (is_active IS NULL OR is_active = true)`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('[biometric-attendance-logs GET devices]', err);
    res.status(500).json({ error: 'Failed to fetch devices' });
  }
});

/**
 * POST /api/biometric-attendance-logs/push
 * Push raw punches from a biometric device (e.g. ZKTeco sync service).
 * Auth: X-Api-Key header (BIO_SYNC_API_KEY) or JWT + admin.
 * Body: { punches: [{ biometric_user_id, logged_at }], device_id?, source_name? }
 * - Looks up user_id from users WHERE biometric_user_id = ?
 * - Skips punches for unmatched biometric_user_id (logged)
 * - Uses ON CONFLICT to skip duplicates
 * - Processes to dtr_daily_summary after insert
 */
router.post('/push', pushAuth, async (req, res) => {
  try {
    const { punches = [], device_id, source_name } = req.body;
    const sourceFileName = source_name || device_id || 'zk-sync';

    if (!Array.isArray(punches) || punches.length === 0) {
      return res.status(400).json({
        error: 'No punches to push',
        inserted: 0,
        skipped_unmatched: 0,
        duplicates_skipped: 0,
      });
    }

    const uniqueBiometricIds = [...new Set(punches.map((p) => String(p.biometric_user_id || '').trim()).filter(Boolean))];
    if (uniqueBiometricIds.length === 0) {
      return res.status(400).json({ error: 'No valid biometric_user_id in punches' });
    }

    const userLookup = await pool.query(
      `SELECT id, biometric_user_id FROM users WHERE biometric_user_id = ANY($1::text[])`,
      [uniqueBiometricIds]
    );
    const biometricToUserId = new Map(userLookup.rows.map((r) => [String(r.biometric_user_id).trim(), r.id]));

    let inserted = 0;
    let duplicatesSkipped = 0;
    let skippedUnmatched = 0;
    const userIds = new Set();

    for (const p of punches) {
      const biometricUserId = String(p.biometric_user_id || '').trim();
      let loggedAt = p.logged_at;
      if (!biometricUserId) continue;

      if (loggedAt instanceof Date) {
        loggedAt = loggedAt.toISOString();
      } else if (typeof loggedAt !== 'string') {
        continue;
      }

      const userId = biometricToUserId.get(biometricUserId);
      if (!userId) {
        skippedUnmatched++;
        continue;
      }

      const rawLine = `${biometricUserId}\t${loggedAt}`;

      const result = await pool.query(
        `INSERT INTO biometric_attendance_logs
          (user_id, biometric_user_id, logged_at, raw_line, source_file_name)
         VALUES ($1::uuid, $2, $3::timestamptz, $4, $5)
         ON CONFLICT (biometric_user_id, logged_at) DO NOTHING
         RETURNING id`,
        [userId, biometricUserId, loggedAt, rawLine, sourceFileName]
      );

      if (result.rowCount > 0) {
        inserted++;
        userIds.add(userId);
      } else {
        duplicatesSkipped++;
      }
    }

    let summariesInserted = 0;
    let summariesUpdated = 0;
    if (userIds.size > 0) {
      const tz = process.env.HRMS_TIMEZONE || 'Asia/Manila';
      const scopeRes = await pool.query(
        `SELECT
           MIN((logged_at AT TIME ZONE $2)::date)::text AS min_date,
           MAX((logged_at AT TIME ZONE $2)::date)::text AS max_date
         FROM biometric_attendance_logs
         WHERE user_id = ANY($1::uuid[])`,
        [[...userIds], tz]
      );
      const dateFrom = scopeRes.rows[0]?.min_date?.slice(0, 10);
      const dateTo = scopeRes.rows[0]?.max_date?.slice(0, 10);
      if (dateFrom && dateTo) {
        const proc = await processBiometricLogsToSummary([...userIds], dateFrom, dateTo);
        summariesInserted = proc.inserted;
        summariesUpdated = proc.updated;
      }
    }

    res.json({
      inserted,
      skipped_unmatched: skippedUnmatched,
      duplicates_skipped: duplicatesSkipped,
      summaries_inserted: summariesInserted,
      summaries_updated: summariesUpdated,
    });
  } catch (err) {
    console.error('[biometric-attendance-logs push]', err);
    res.status(500).json({
      error: err.message || 'Failed to push biometric logs',
    });
  }
});

/**
 * POST /api/biometric-attendance-logs/import
 * Import matched biometric logs into biometric_attendance_logs, then process into dtr_daily_summary.
 * Body: { rows: [{ user_id, biometric_user_id, logged_at, raw_line, verify_code?, punch_code?, work_code? }], source_file_name }
 * Uses ON CONFLICT (biometric_user_id, logged_at) DO NOTHING to skip duplicates.
 * Admin only.
 */
router.post('/import', protect, requireAdmin, async (req, res) => {
  try {
    const { rows = [], source_file_name } = req.body;
    if (!Array.isArray(rows) || rows.length === 0) {
      return res.status(400).json({
        error: 'No rows to import',
        inserted: 0,
        duplicates_skipped: 0,
        summaries_inserted: 0,
        summaries_updated: 0,
      });
    }

    let inserted = 0;
    let duplicatesSkipped = 0;
    const userIds = new Set();
    let dateMin = null;
    let dateMax = null;

    for (const row of rows) {
      const userId = row.user_id;
      const biometricUserId = row.biometric_user_id;
      const loggedAt = row.logged_at;
      const rawLine = row.raw_line;

      if (!userId || !biometricUserId || !loggedAt || !rawLine) {
        continue;
      }

      const verifyCode = row.verify_code?.trim() || null;
      const punchCode = row.punch_code?.trim() || null;
      const workCode = row.work_code?.trim() || null;

      const result = await pool.query(
        `INSERT INTO biometric_attendance_logs
          (user_id, biometric_user_id, logged_at, verify_code, punch_code, work_code, raw_line, source_file_name)
         VALUES ($1::uuid, $2, $3::timestamptz, $4, $5, $6, $7, $8)
         ON CONFLICT (biometric_user_id, logged_at) DO NOTHING
         RETURNING id`,
        [userId, biometricUserId, loggedAt, verifyCode, punchCode, workCode, rawLine, source_file_name || null]
      );

      if (result.rowCount > 0) {
        inserted++;
      } else {
        duplicatesSkipped++;
      }

      userIds.add(userId);
      const d = toIsoDate(loggedAt);
      if (d) {
        if (!dateMin || d < dateMin) dateMin = d;
        if (!dateMax || d > dateMax) dateMax = d;
      }
    }

    let summariesInserted = 0;
    let summariesUpdated = 0;
    if (userIds.size > 0) {
      const tz = process.env.HRMS_TIMEZONE || 'Asia/Manila';
      const scopeRes = await pool.query(
        `SELECT
           MIN((logged_at AT TIME ZONE $2)::date)::text AS min_date,
           MAX((logged_at AT TIME ZONE $2)::date)::text AS max_date
         FROM biometric_attendance_logs
         WHERE user_id = ANY($1::uuid[])`,
        [[...userIds], tz]
      );
      const dateFrom = scopeRes.rows[0]?.min_date?.slice(0, 10);
      const dateTo = scopeRes.rows[0]?.max_date?.slice(0, 10);
      if (dateFrom && dateTo) {
        console.log('[biometric-attendance-logs import] Calling processBiometricLogsToSummary', {
          userIdCount: userIds.size,
          dateFrom,
          dateTo,
        });
        const proc = await processBiometricLogsToSummary([...userIds], dateFrom, dateTo);
        summariesInserted = proc.inserted;
        summariesUpdated = proc.updated;
      } else {
        console.log('[biometric-attendance-logs import] Skipping processing: no date range from DB');
      }
    }

    res.json({
      inserted,
      duplicates_skipped: duplicatesSkipped,
      summaries_inserted: summariesInserted,
      summaries_updated: summariesUpdated,
    });
  } catch (err) {
    console.error('[biometric-attendance-logs import]', err);
    res.status(500).json({
      error: err.message || 'Failed to import biometric logs',
    });
  }
});

/**
 * POST /api/biometric-attendance-logs/process
 * Reprocess existing biometric_attendance_logs into dtr_daily_summary.
 * Body: optional { date_from: 'YYYY-MM-DD', date_to: 'YYYY-MM-DD' }
 * If omitted, processes all biometric logs.
 * Admin only.
 */
router.post('/process', protect, requireAdmin, async (req, res) => {
  try {
    const { date_from, date_to } = req.body || {};
    let dateFrom = date_from && typeof date_from === 'string' ? date_from.trim() : null;
    let dateTo = date_to && typeof date_to === 'string' ? date_to.trim() : null;

    const tz = process.env.HRMS_TIMEZONE || 'Asia/Manila';
    const scopeRes = await pool.query(
      `SELECT
         array_agg(DISTINCT user_id) AS user_ids,
         MIN((logged_at AT TIME ZONE $1)::date)::text AS min_date,
         MAX((logged_at AT TIME ZONE $1)::date)::text AS max_date
       FROM biometric_attendance_logs`,
      [tz]
    );
    const row = scopeRes.rows[0];
    const allUserIds = row?.user_ids?.filter(Boolean) || [];
    const dbMinStr = row?.min_date?.slice(0, 10) || null;
    const dbMaxStr = row?.max_date?.slice(0, 10) || null;

    if (allUserIds.length === 0) {
      return res.json({
        message: 'No biometric logs found',
        summaries_inserted: 0,
        summaries_updated: 0,
      });
    }

    if (!dateFrom) dateFrom = dbMinStr;
    if (!dateTo) dateTo = dbMaxStr;
    if (!dateFrom || !dateTo) {
      return res.status(400).json({ error: 'Could not determine date range from biometric logs' });
    }

    const cleanupRes = await pool.query(
      `DELETE FROM dtr_daily_summary
       WHERE source = 'system'
         AND (
           (time_in IS NOT NULL AND (time_in AT TIME ZONE $1)::date <> attendance_date)
           OR (time_out IS NOT NULL AND (time_out AT TIME ZONE $1)::date <> attendance_date)
         )
       RETURNING id`,
      [tz]
    );
    const cleanedCount = cleanupRes.rowCount || 0;
    if (cleanedCount > 0) {
      console.log('[biometric-attendance-logs process] Cleaned', cleanedCount, 'mismatched system rows');
    }

    const proc = await processBiometricLogsToSummary(allUserIds, dateFrom, dateTo);
    res.json({
      message: 'Processing complete',
      mismatched_rows_cleaned: cleanedCount,
      summaries_inserted: proc.inserted,
      summaries_updated: proc.updated,
    });
  } catch (err) {
    console.error('[biometric-attendance-logs process]', err);
    res.status(500).json({
      error: err.message || 'Failed to process biometric logs',
    });
  }
});

module.exports = router;
