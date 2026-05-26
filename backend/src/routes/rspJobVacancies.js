const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrSupervisor } = require('../middleware/rbac');
const {
  parseMaxApplicants,
  enrichVacanciesWithApplicationCounts,
} = require('../utils/jobVacancySlots');

const router = express.Router();
const protect = [authMiddleware];

// Ensure landing-page table exists (idempotent).
async function ensureTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS public.job_vacancy_announcement (
       id TEXT PRIMARY KEY DEFAULT 'default',
       has_vacancies BOOLEAN DEFAULT true,
       headline TEXT,
       body TEXT,
       vacancies JSONB DEFAULT '[]'::JSONB,
       updated_at TIMESTAMPTZ DEFAULT now()
     );
     INSERT INTO public.job_vacancy_announcement (id, has_vacancies, headline, body)
     VALUES ('default', true, NULL, NULL)
     ON CONFLICT (id) DO NOTHING;`
  );

  // Add missing columns if older schema was used.
  await pool.query(
    `ALTER TABLE public.job_vacancy_announcement
       ADD COLUMN IF NOT EXISTS vacancies JSONB DEFAULT '[]'::JSONB;`
  );
  await pool.query(
    `ALTER TABLE public.job_vacancy_announcement
       ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();`
  );
}

// GET /api/rsp/job-vacancies
// Public read so the landing page can show the hiring banner without login.
router.get('/', async (_req, res) => {
  try {
    await ensureTable();
    const result = await pool.query(
      `SELECT id, has_vacancies, headline, body, vacancies, updated_at
       FROM public.job_vacancy_announcement
       WHERE id = 'default'
       LIMIT 1`
    );
    const row = result.rows[0];
    if (!row) {
      return res.json({
        id: 'default',
        has_vacancies: true,
        headline: null,
        body: null,
        vacancies: [],
        updated_at: null,
      });
    }

    let vacancies = Array.isArray(row.vacancies) ? row.vacancies : [];
    if (
      vacancies.length === 0 &&
      (row.headline != null || row.body != null) &&
      (String(row.headline || '').trim() || String(row.body || '').trim())
    ) {
      vacancies = [{ headline: row.headline, body: row.body }];
    }
    vacancies = await enrichVacanciesWithApplicationCounts(vacancies);

    res.json({
      id: row.id,
      has_vacancies: row.has_vacancies,
      headline: row.headline,
      body: row.body,
      vacancies,
      updated_at: row.updated_at ? row.updated_at.toISOString() : null,
    });
  } catch (err) {
    console.error('[rspJobVacancies GET]', err);
    res.status(500).json({ error: 'Failed to fetch job vacancy announcement' });
  }
});

// PUT /api/rsp/job-vacancies
// Updates the single-row job vacancy announcement shown on the landing page.
// This avoids Supabase RLS issues because the backend writes directly to Postgres.
router.put('/', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    const {
      has_vacancies,
      headline,
      body,
      vacancies,
      // updated_at may be sent by the client; ignore it and use now()
    } = req.body || {};

    const normalizedHeadline =
      typeof headline === 'string' ? headline.trim() : null;
    const normalizedBody = typeof body === 'string' ? body.trim() : null;

    const list = Array.isArray(vacancies) ? vacancies : [];
    // Expected: [{ headline: '...', body: '...' }, ...]
    const optStr = (x) =>
      typeof x === 'string' && x.trim().length ? x.trim() : null;

    const normalizedVacancies = list
      .filter((v) => v && typeof v === 'object')
      .map((v) => {
        const max = parseMaxApplicants(v.max_applicants);
        const education = optStr(v.education);
        const experience = optStr(v.experience);
        const training = optStr(v.training);
        const closing_date = optStr(v.closing_date);
        return {
          headline:
            typeof v.headline === 'string' && v.headline.trim().length
              ? v.headline.trim()
              : null,
          body:
            typeof v.body === 'string' && v.body.trim().length
              ? v.body.trim()
              : null,
          ...(education != null ? { education } : {}),
          ...(experience != null ? { experience } : {}),
          ...(training != null ? { training } : {}),
          ...(closing_date != null ? { closing_date } : {}),
          ...(max != null ? { max_applicants: max } : {}),
        };
      });

    // Ensure landing-page table exists (idempotent).
    await ensureTable();

    const vacanciesCol = await pool.query(
      `SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'job_vacancy_announcement'
         AND column_name = 'vacancies'
       LIMIT 1`
    );

    const hasVacanciesValue = !!has_vacancies;

    if (vacanciesCol.rows.length > 0) {
      await pool.query(
        `INSERT INTO job_vacancy_announcement (id, has_vacancies, headline, body, vacancies)
         VALUES ('default', $1, $2, $3, $4::jsonb)
         ON CONFLICT (id) DO UPDATE SET
           has_vacancies = EXCLUDED.has_vacancies,
           headline = EXCLUDED.headline,
           body = EXCLUDED.body,
           vacancies = EXCLUDED.vacancies,
           updated_at = now()`,
        [
          hasVacanciesValue,
          normalizedHeadline,
          normalizedBody,
          JSON.stringify(normalizedVacancies),
        ]
      );
    } else {
      // Older schema: only headline/body + has_vacancies exist.
      await pool.query(
        `INSERT INTO job_vacancy_announcement (id, has_vacancies, headline, body)
         VALUES ('default', $1, $2, $3)
         ON CONFLICT (id) DO UPDATE SET
           has_vacancies = EXCLUDED.has_vacancies,
           headline = EXCLUDED.headline,
           body = EXCLUDED.body,
           updated_at = now()`,
        [hasVacanciesValue, normalizedHeadline, normalizedBody]
      );
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('[rspJobVacancies PUT]', err);
    res.status(500).json({
      error: 'Failed to update job vacancy announcement',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PATCH /api/rsp/job-vacancies/accepting
// Updates only has_vacancies (landing hiring on/off) without touching vacancy entries.
router.patch('/accepting', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    const { has_vacancies } = req.body || {};
    if (has_vacancies === undefined) {
      return res.status(400).json({ error: 'has_vacancies is required' });
    }

    await ensureTable();
    const hasVacanciesValue = !!has_vacancies;

    const updated = await pool.query(
      `UPDATE public.job_vacancy_announcement
       SET has_vacancies = $1, updated_at = now()
       WHERE id = 'default'
       RETURNING has_vacancies`,
      [hasVacanciesValue]
    );

    if (updated.rowCount === 0) {
      await pool.query(
        `INSERT INTO public.job_vacancy_announcement (id, has_vacancies, headline, body, vacancies)
         VALUES ('default', $1, NULL, NULL, '[]'::jsonb)`,
        [hasVacanciesValue]
      );
    }

    res.json({ ok: true, has_vacancies: hasVacanciesValue });
  } catch (err) {
    console.error('[rspJobVacancies PATCH accepting]', err);
    res.status(500).json({
      error: 'Failed to update hiring status',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

module.exports = router;

