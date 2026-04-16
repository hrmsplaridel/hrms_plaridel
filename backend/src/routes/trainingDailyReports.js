const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

// Helper to map a DB row to API DTO.
function mapReportRow(row) {
  if (!row) return null;
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
    seen_by_admin: row.seen_by_admin,
    seen_at: row.seen_at,
    reviewed_by: row.reviewed_by,
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

    const result = await pool.query(
      `INSERT INTO training_daily_reports
       (employee_id, title, description, attachment_path, attachment_name, attachment_type)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, employee_id, title, description, submitted_at, status,
                 attachment_path, attachment_name, attachment_type,
                 seen_by_admin, seen_at, reviewed_by`,
      [
        req.user.id,
        title.trim(),
        description?.trim() || null,
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
    const { status, fromDate, toDate } = req.query;
    const conditions = ['r.employee_id = $1'];
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
router.get('/', protect, requireAdmin, async (req, res) => {
  try {
    const { search, fromDate, toDate, status } = req.query;
    const conditions = ['1=1'];
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

/**
 * PATCH /api/training-daily-reports/:id/seen
 * Admin marks a report as "seen".
 */
router.patch('/:id/seen', protect, requireAdmin, async (req, res) => {
  try {
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
       WHERE id = $2
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

module.exports = router;

