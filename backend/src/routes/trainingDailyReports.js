const express = require('express');
const jwt = require('jsonwebtoken');
const trainingNotifications = require('../services/trainingNotifications');
const { pool } = require('../config/db');
const { ensureTrainingDailyReportColumns } = require('../utils/trainingDailyReportSchema');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { requireLdAccessIfAdmin } = require('../middleware/ldAccess');
const {
  TRAINING_DAILY_TITLE_MAX,
  TRAINING_DAILY_DESCRIPTION_MAX,
  cleanBoundedText,
} = require('../utils/inputValidation');

const router = express.Router();
const protect = [authMiddleware];
const adminDailyReports = [
  authMiddleware,
  requireAdmin,
  requireLdAccessIfAdmin('daily_reports_allowed'),
];

// Helper to map a DB row to API DTO.
function mapReportRow(row) {
  if (!row) return null;
  const attachmentToken = row.attachment_id && process.env.JWT_SECRET
    ? jwt.sign(
        { typ: 'training_attachment', attachmentId: String(row.attachment_id) },
        process.env.JWT_SECRET,
        { expiresIn: '15m' },
      )
    : null;
  return {
    id: row.id,
    employee_id: row.employee_id,
    employee_name: row.employee_name,
    title: row.title,
    description: row.description,
    submitted_at: row.submitted_at,
    status: row.status,
    attachment_id: row.attachment_id,
    attachment_name: row.attachment_name,
    attachment_type: row.attachment_type,
    attachment_path: row.attachment_path,
    attachment_token: attachmentToken,
    seen_by_admin: row.seen_by_admin,
    seen_at: row.seen_at,
    reviewed_by: row.reviewed_by,
    deleted_at: row.deleted_at || null,
  };
}

/**
 * POST /api/training-daily-reports
 * Employee submits a daily training report.
 * Body: { title, description, attachment_path?, attachment_name?, attachment_type? }
 */
router.post('/', protect, async (req, res) => {
  try {
    const { title, description, attachment_path, attachment_name, attachment_type } =
      req.body || {};

    if (!title || typeof title !== 'string' || !title.trim()) {
      return res.status(400).json({ error: 'title is required' });
    }
    const cleanTitle = cleanBoundedText(title, TRAINING_DAILY_TITLE_MAX);
    if (!cleanTitle) {
      return res.status(400).json({ error: 'title is required' });
    }
    if (title.trim().length > TRAINING_DAILY_TITLE_MAX) {
      return res.status(400).json({
        error: `title must be at most ${TRAINING_DAILY_TITLE_MAX} characters`,
        code: 'TITLE_TOO_LONG',
      });
    }
    let cleanDescription = null;
    if (description != null && description !== '') {
      if (typeof description !== 'string') {
        return res.status(400).json({ error: 'description must be a string' });
      }
      if (description.trim().length > TRAINING_DAILY_DESCRIPTION_MAX) {
        return res.status(400).json({
          error: `description must be at most ${TRAINING_DAILY_DESCRIPTION_MAX} characters`,
          code: 'DESCRIPTION_TOO_LONG',
        });
      }
      cleanDescription = cleanBoundedText(description, TRAINING_DAILY_DESCRIPTION_MAX) || null;
    }
    if (
      attachment_path != null &&
      !/^training-reports\/[0-9a-f-]{36}\.(?:jpg|jpeg|png|pdf)$/i.test(String(attachment_path))
    ) {
      return res.status(400).json({ error: 'Invalid training report attachment path' });
    }

    const result = await pool.query(
      `INSERT INTO training_daily_reports
       (employee_id, title, description, attachment_path, attachment_name, attachment_type)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, employee_id, title, description, submitted_at, status,
                 attachment_path, attachment_name, attachment_type,
                 seen_by_admin, seen_at, reviewed_by`,
      [
        req.user.id,
        cleanTitle,
        cleanDescription,
        attachment_path || null,
        attachment_name || null,
        attachment_type || null,
      ]
    );

    const row = result.rows[0];

    // Optionally create an attachment record if we have a file.
    let attachmentId = null;
    if (row.attachment_path) {
      const attachResult = await pool.query(
        `INSERT INTO training_report_attachments
         (report_id, file_path, file_name, mime_type, uploaded_by)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id`,
        [
          row.id,
          row.attachment_path,
          row.attachment_name,
          row.attachment_type,
          req.user.id,
        ]
      );
      attachmentId = attachResult.rows[0].id;
    }

    try {
      const nameRes = await pool.query(
        `SELECT full_name, email FROM users WHERE id = $1`,
        [req.user.id]
      );
      const u = nameRes.rows[0];
      await trainingNotifications.notifyReportSubmitted(pool, {
        reportId: row.id,
        employeeName: u?.full_name || u?.email,
        title: row.title,
      });
    } catch (notifyErr) {
      console.error('[trainingDailyReports notify]', notifyErr?.message || notifyErr);
    }

    res.status(201).json({
      ...mapReportRow({
        ...row,
        employee_name: null,
        attachment_id: attachmentId,
      }),
    });
  } catch (err) {
    console.error('[trainingDailyReports POST]', err);
    res.status(500).json({ error: 'Failed to submit training daily report' });
  }
});

/**
 * GET /api/training-daily-reports/mine
 * List reports for the logged-in employee.
 * Optional query: status, fromDate, toDate (YYYY-MM-DD).
 */
router.get('/mine', protect, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const { status, fromDate, toDate } = req.query;
    const conditions = ['r.employee_id = $1', 'r.deleted_at IS NULL'];
    const params = [req.user.id];
    let i = 2;

    if (status && status !== 'All') {
      conditions.push(`r.status = $${i++}`);
      params.push(status.toLowerCase());
    }

    if (fromDate) {
      conditions.push(`r.submitted_at::date >= $${i++}::date`);
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push(`r.submitted_at::date <= $${i++}::date`);
      params.push(toDate);
    }

    const where = `WHERE ${conditions.join(' AND ')}`;

    const result = await pool.query(
      `SELECT
         r.id,
         r.employee_id,
         r.title,
         r.description,
         r.submitted_at,
         r.status,
         r.attachment_path,
         r.attachment_name,
         r.attachment_type,
         r.seen_by_admin,
         r.seen_at,
         r.reviewed_by,
         a.id AS attachment_id
       FROM training_daily_reports r
       LEFT JOIN LATERAL (
         SELECT id, file_path
         FROM training_report_attachments
         WHERE report_id = r.id
         ORDER BY created_at DESC
         LIMIT 1
       ) a ON TRUE
       ${where}
       ORDER BY r.submitted_at DESC`,
      params
    );

    res.json(result.rows.map((r) => mapReportRow(r)));
  } catch (err) {
    console.error('[trainingDailyReports GET /mine]', err);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

/**
 * GET /api/training-daily-reports
 * Admin: list all reports with employee names.
 * Query: search (employee name or title), fromDate, toDate, status.
 */
router.get('/', ...adminDailyReports, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const { search, fromDate, toDate, status } = req.query;
    const conditions = ['r.deleted_at IS NULL'];
    const params = [];
    let i = 1;

    if (search) {
      conditions.push(`(u.full_name ILIKE $${i} OR r.title ILIKE $${i})`);
      params.push(`%${search}%`);
      i += 1;
    }
    if (status && status !== 'All') {
      conditions.push(`r.status = $${i++}`);
      params.push(status.toLowerCase());
    }
    if (fromDate) {
      conditions.push(`r.submitted_at::date >= $${i++}::date`);
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push(`r.submitted_at::date <= $${i++}::date`);
      params.push(toDate);
    }

    const where = `WHERE ${conditions.join(' AND ')}`;

    const result = await pool.query(
      `SELECT
         r.id,
         r.employee_id,
         u.full_name AS employee_name,
         r.title,
         r.description,
         r.submitted_at,
         r.status,
         r.attachment_path,
         r.attachment_name,
         r.attachment_type,
         r.seen_by_admin,
         r.seen_at,
         r.reviewed_by,
         a.id AS attachment_id
       FROM training_daily_reports r
       JOIN users u ON u.id = r.employee_id
       LEFT JOIN LATERAL (
         SELECT id, file_path
         FROM training_report_attachments
         WHERE report_id = r.id
         ORDER BY created_at DESC
         LIMIT 1
       ) a ON TRUE
       ${where}
       ORDER BY r.submitted_at DESC, u.full_name`,
      params
    );

    res.json(result.rows.map((r) => mapReportRow(r)));
  } catch (err) {
    console.error('[trainingDailyReports GET]', err);
    res.status(500).json({ error: 'Failed to fetch training daily reports' });
  }
});

const reportSelect = `
  SELECT
    r.id,
    r.employee_id,
    u.full_name AS employee_name,
    r.title,
    r.description,
    r.submitted_at,
    r.status,
    r.attachment_path,
    r.attachment_name,
    r.attachment_type,
    r.seen_by_admin,
    r.seen_at,
    r.reviewed_by,
    r.deleted_at,
    a.id AS attachment_id
  FROM training_daily_reports r
  JOIN users u ON u.id = r.employee_id
  LEFT JOIN LATERAL (
    SELECT id
    FROM training_report_attachments
    WHERE report_id = r.id
    ORDER BY created_at DESC
    LIMIT 1
  ) a ON TRUE
`;

/**
 * GET /api/training-daily-reports/recycle-bin
 * Admin: reports moved out of the active list.
 */
router.get('/recycle-bin', ...adminDailyReports, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const result = await pool.query(
      `${reportSelect}
       WHERE r.deleted_at IS NOT NULL
       ORDER BY r.deleted_at DESC`,
    );
    res.json(result.rows.map((r) => mapReportRow(r)));
  } catch (err) {
    console.error('[trainingDailyReports GET recycle-bin]', err);
    res.status(500).json({ error: 'Failed to list the recycle bin' });
  }
});

/**
 * POST /api/training-daily-reports/:id/restore
 */
router.post('/:id/restore', ...adminDailyReports, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const { id } = req.params;
    const result = await pool.query(
      `UPDATE training_daily_reports
       SET deleted_at = NULL, updated_at = now()
       WHERE id = $1 AND deleted_at IS NOT NULL
       RETURNING id`,
      [id],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Report not found in the recycle bin' });
    }
    const loaded = await pool.query(
      `${reportSelect} WHERE r.id = $1`,
      [id],
    );
    res.json(mapReportRow(loaded.rows[0]));
  } catch (err) {
    console.error('[trainingDailyReports POST restore]', err);
    res.status(500).json({ error: 'Failed to restore training daily report' });
  }
});

/**
 * PATCH /api/training-daily-reports/:id/seen
 * Admin marks a report as "seen".
 */
router.patch('/:id/seen', ...adminDailyReports, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const { id } = req.params;

    const result = await pool.query(
      `UPDATE training_daily_reports
       SET status = CASE
             WHEN status IN ('reviewed','approved','needs_revision') THEN status
             ELSE 'seen'
           END,
           seen_by_admin = $1,
           seen_at = now(),
           updated_at = now()
       WHERE id = $2 AND deleted_at IS NULL
       RETURNING *`,
      [req.user.id, id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Report not found' });
    }

    const row = result.rows[0];
    res.json(
      mapReportRow({
        ...row,
        employee_name: null,
        attachment_id: null,
      })
    );
  } catch (err) {
    console.error('[trainingDailyReports PATCH /seen]', err);
    res.status(500).json({ error: 'Failed to mark report as seen' });
  }
});

/**
 * DELETE /api/training-daily-reports/:id
 * Without ?permanent=1, moves the report to the recycle bin.
 * With ?permanent=1, removes the report and cascaded attachment rows.
 */
router.delete('/:id', ...adminDailyReports, async (req, res) => {
  try {
    await ensureTrainingDailyReportColumns();
    const { id } = req.params;
    const permanent = ['1', 'true'].includes(String(req.query.permanent || '').toLowerCase());
    if (!permanent) {
      const recycled = await pool.query(
        `UPDATE training_daily_reports
         SET deleted_at = now(), updated_at = now()
         WHERE id = $1 AND deleted_at IS NULL
         RETURNING id`,
        [id],
      );
      if (recycled.rowCount === 0) {
        return res.status(404).json({ error: 'Report not found' });
      }
      return res.json({ ok: true, recycled: true });
    }
    const result = await pool.query(
      `DELETE FROM training_daily_reports WHERE id = $1 RETURNING id`,
      [id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Report not found' });
    }
    res.status(204).send();
  } catch (err) {
    console.error('[trainingDailyReports DELETE]', err);
    res.status(500).json({ error: 'Failed to delete training daily report' });
  }
});

module.exports = router;

