const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware, requireAdmin];

async function ensureRspApplicationsTables() {
  // Defensive: allow delete to work even if init-schema-rsp.sql wasn't run yet.
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_applications (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      full_name TEXT NOT NULL,
      email TEXT NOT NULL,
      phone TEXT,
      resume_notes TEXT,
      attachment_path TEXT,
      attachment_name TEXT,
      status TEXT NOT NULL DEFAULT 'submitted'
        CHECK (
          status IN (
            'submitted',
            'document_approved',
            'document_declined',
            'exam_taken',
            'passed',
            'failed',
            'registered'
          )
        ),
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_exam_results (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      application_id UUID NOT NULL REFERENCES public.recruitment_applications(id) ON DELETE CASCADE,
      score_percent NUMERIC(5,2) NOT NULL,
      passed BOOLEAN NOT NULL,
      answers_json JSONB,
      submitted_at TIMESTAMPTZ DEFAULT now(),
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  // Ensure one exam result row per application.
  // Some Postgres versions may not support "ADD CONSTRAINT IF NOT EXISTS".
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_recruitment_exam_results_application'
      ) THEN
        ALTER TABLE public.recruitment_exam_results
          ADD CONSTRAINT uq_recruitment_exam_results_application
          UNIQUE (application_id);
      END IF;
    END $$;
  `);
}

// POST /api/rsp/applications
// Public create: applicants submit their basic info + documents.
router.post('/', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const {
      fullName,
      email,
      phone,
      resumeNotes,
      status = 'submitted',
    } = req.body || {};

    if (!fullName || typeof fullName !== 'string') {
      return res.status(400).json({ error: 'fullName is required' });
    }
    if (!email || typeof email !== 'string') {
      return res.status(400).json({ error: 'email is required' });
    }

    const normalizedEmail = email.trim().toLowerCase();

    const result = await pool.query(
      `
      INSERT INTO public.recruitment_applications
        (full_name, email, phone, resume_notes, status, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, now(), now())
      RETURNING id, full_name, email, phone, resume_notes, attachment_path, attachment_name, status, created_at, updated_at
      `,
      [fullName.trim(), normalizedEmail, phone ?? null, resumeNotes ?? null, status]
    );

    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications POST /]', err);
    return res.status(500).json({
      error: 'Failed to create application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// GET /api/rsp/applications/by-email?email=...
// Public lookup for applicants to continue their flow.
router.get('/by-email', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const email = req.query.email;
    if (!email || typeof email !== 'string') {
      return res.status(400).json({ error: 'email query param is required' });
    }

    const result = await pool.query(
      `
      SELECT id, full_name, email, phone, resume_notes, attachment_path, attachment_name, status, created_at, updated_at
      FROM public.recruitment_applications
      WHERE email = $1
      ORDER BY created_at DESC
      LIMIT 1
      `,
      [email.trim().toLowerCase()]
    );

    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'Application not found' });
    return res.json({ ok: true, application: row });
  } catch (err) {
    console.error('[rspApplications GET /by-email]', err);
    return res.status(500).json({
      error: 'Failed to fetch application by email',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// GET /api/rsp/applications
// Admin list of applicants.
router.get('/', protect, async (_req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `
      SELECT id, full_name, email, phone, resume_notes, attachment_path, attachment_name, status, created_at, updated_at
      FROM public.recruitment_applications
      ORDER BY created_at DESC
      `
    );
    return res.json({ ok: true, applications: result.rows });
  } catch (err) {
    console.error('[rspApplications GET /]', err);
    return res.status(500).json({
      error: 'Failed to list applications',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/status
// Admin status updates (approve/decline/failed/passed).
router.put('/:applicationId/status', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { status } = req.body || {};
    if (!status || typeof status !== 'string') {
      return res.status(400).json({ error: 'status is required' });
    }
    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET status = $1, updated_at = now()
      WHERE id = $2
      `,
      [status, applicationId]
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error('[rspApplications PUT status]', err);
    return res.status(500).json({
      error: 'Failed to update application status',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/attachment
// Public for applicants: store Supabase Storage attachment path/name.
router.put('/:applicationId/attachment', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { path, fileName } = req.body || {};
    if (!path || typeof path !== 'string') {
      return res.status(400).json({ error: 'path is required' });
    }
    if (!fileName || typeof fileName !== 'string') {
      return res.status(400).json({ error: 'fileName is required' });
    }
    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET attachment_path = $1,
          attachment_name = $2,
          updated_at = now()
      WHERE id = $3
      `,
      [path, fileName, applicationId]
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error('[rspApplications PUT attachment]', err);
    return res.status(500).json({
      error: 'Failed to update attachment',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/attachment-if-missing
// Admin/public: only set attachment fields when attachment_path is currently NULL.
router.put('/:applicationId/attachment-if-missing', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { path, fileName } = req.body || {};
    if (!path || typeof path !== 'string' || !fileName || typeof fileName !== 'string') {
      return res.status(400).json({ error: 'path and fileName are required' });
    }
    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET attachment_path = $1,
          attachment_name = $2,
          updated_at = now()
      WHERE id = $3 AND attachment_path IS NULL
      `,
      [path, fileName, applicationId]
    );
    return res.json({ ok: true, updated: (result.rowCount ?? 0) > 0 });
  } catch (err) {
    console.error('[rspApplications PUT attachment-if-missing]', err);
    return res.status(500).json({
      error: 'Failed to update attachment-if-missing',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// POST /api/rsp/exam-results
// Public: applicant submits exam results + answers_json.
router.post('/exam-results', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId, scorePercent, passed, answersJson } = req.body || {};
    if (!applicationId) return res.status(400).json({ error: 'applicationId is required' });
    if (typeof passed !== 'boolean') return res.status(400).json({ error: 'passed is required (boolean)' });
    if (scorePercent === undefined || scorePercent === null) return res.status(400).json({ error: 'scorePercent is required' });

    const score = Number(scorePercent);
    if (Number.isNaN(score)) return res.status(400).json({ error: 'scorePercent must be numeric' });

    await pool.query(
      `
      INSERT INTO public.recruitment_exam_results (application_id, score_percent, passed, answers_json, submitted_at, created_at, updated_at)
      VALUES ($1, $2, $3, $4, now(), now(), now())
      ON CONFLICT (application_id)
      DO UPDATE SET
        score_percent = EXCLUDED.score_percent,
        passed = EXCLUDED.passed,
        answers_json = EXCLUDED.answers_json,
        updated_at = now(),
        submitted_at = now()
      `,
      [applicationId, score, passed, answersJson ?? null]
    );

    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET status = $1, updated_at = now()
      WHERE id = $2
      `,
      [passed ? 'passed' : 'failed', applicationId]
    );

    return res.json({ ok: true });
  } catch (err) {
    console.error('[rspApplications POST exam-results]', err);
    return res.status(500).json({
      error: 'Failed to submit exam results',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// GET /api/rsp/exam-results
// Admin list of exam results.
router.get('/exam-results', protect, async (_req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `
      SELECT id, application_id, score_percent, passed, answers_json, submitted_at, created_at, updated_at
      FROM public.recruitment_exam_results
      `
    );
    return res.json({ ok: true, examResults: result.rows });
  } catch (err) {
    console.error('[rspApplications GET exam-results]', err);
    return res.status(500).json({
      error: 'Failed to list exam results',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// DELETE /api/rsp/applications/:applicationId
// Deletes the applicant row and its exam result rows.
//
// Note: This does NOT delete Supabase Storage objects (bucket orphan cleanup is optional).
router.delete('/:applicationId', protect, async (req, res) => {
  try {
    const { applicationId } = req.params;
    if (!applicationId) {
      return res.status(400).json({ error: 'applicationId is required' });
    }

    await ensureRspApplicationsTables();

    // Delete exam results first to avoid FK issues.
    await pool.query(
      'DELETE FROM public.recruitment_exam_results WHERE application_id = $1',
      [applicationId]
    );

    // Delete application row.
    const result = await pool.query(
      'DELETE FROM public.recruitment_applications WHERE id = $1',
      [applicationId]
    );

    const deleted = result.rowCount ?? 0;
    if (deleted === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }

    res.json({ ok: true, deleted });
  } catch (err) {
    console.error('[rspApplications DELETE]', err);
    res.status(500).json({
      error: 'Failed to delete application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

module.exports = router;

