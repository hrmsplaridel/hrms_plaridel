const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrSupervisor } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

const ALLOWED_TYPES = new Set(['general', 'math', 'general_info']);
const MAX_SECONDS = 24 * 60 * 60; // 24 hours

const DEFAULT_SECONDS = {
  general: 45 * 60,
  math: 45 * 60,
  general_info: 10 * 60,
};

async function ensureTable() {
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_exam_time_limits (
      exam_type TEXT PRIMARY KEY,
      time_limit_seconds INT NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  for (const [examType, sec] of Object.entries(DEFAULT_SECONDS)) {
    await pool.query(
      `INSERT INTO public.recruitment_exam_time_limits (exam_type, time_limit_seconds)
       VALUES ($1, $2)
       ON CONFLICT (exam_type) DO NOTHING`,
      [examType, sec]
    );
  }
}

function normalizeSeconds(v) {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'string' ? parseInt(v, 10) : Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 0 || n > MAX_SECONDS) return null;
  return n;
}

// Public: applicants need limits without auth.
router.get('/', async (_req, res) => {
  try {
    await ensureTable();
    const result = await pool.query(
      `SELECT exam_type, time_limit_seconds
       FROM public.recruitment_exam_time_limits
       WHERE exam_type = ANY($1::text[])`,
      [Array.from(ALLOWED_TYPES)]
    );
    const limits = { ...DEFAULT_SECONDS };
    for (const row of result.rows) {
      if (ALLOWED_TYPES.has(row.exam_type)) {
        limits[row.exam_type] = Math.max(0, Math.min(MAX_SECONDS, Number(row.time_limit_seconds) || 0));
      }
    }
    res.json({ limits });
  } catch (err) {
    console.error('[rspExamTimeLimits GET]', err);
    res.status(500).json({ error: 'Failed to fetch exam time limits', details: err?.message ?? String(err) });
  }
});

// Admin: partial update { "general": 1800, "math": 0 } — seconds per exam; 0 = no time limit.
router.put('/', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    await ensureTable();
    const body = req.body || {};
    const updates = typeof body === 'object' && !Array.isArray(body) ? body : {};
    const keys = Object.keys(updates).filter((k) => ALLOWED_TYPES.has(k));
    if (keys.length === 0) {
      return res.status(400).json({ error: 'No valid exam types in body (general, math, general_info)' });
    }
    for (const k of keys) {
      const sec = normalizeSeconds(updates[k]);
      if (sec === null) {
        return res.status(400).json({
          error: `Invalid time_limit_seconds for ${k}: use integer 0–${MAX_SECONDS}`,
        });
      }
      await pool.query(
        `INSERT INTO public.recruitment_exam_time_limits (exam_type, time_limit_seconds, updated_at)
         VALUES ($1, $2, now())
         ON CONFLICT (exam_type) DO UPDATE SET
           time_limit_seconds = EXCLUDED.time_limit_seconds,
           updated_at = now()`,
        [k, sec]
      );
    }
    const result = await pool.query(
      `SELECT exam_type, time_limit_seconds
       FROM public.recruitment_exam_time_limits
       WHERE exam_type = ANY($1::text[])`,
      [Array.from(ALLOWED_TYPES)]
    );
    const limits = { ...DEFAULT_SECONDS };
    for (const row of result.rows) {
      if (ALLOWED_TYPES.has(row.exam_type)) {
        limits[row.exam_type] = Math.max(0, Math.min(MAX_SECONDS, Number(row.time_limit_seconds) || 0));
      }
    }
    res.json({ ok: true, limits });
  } catch (err) {
    console.error('[rspExamTimeLimits PUT]', err);
    res.status(500).json({ error: 'Failed to save exam time limits', details: err?.message ?? String(err) });
  }
});

module.exports = router;
