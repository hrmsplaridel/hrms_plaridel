const crypto = require('crypto');
const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrSupervisor } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

const RESERVED_TYPES = new Set(['bei', 'general', 'math', 'general_info']);
const FORMATS = new Set(['open_ended', 'multiple_choice']);

async function ensureCustomExamsTable() {
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_custom_exams (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      exam_type TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      format TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_hidden_exams (
      exam_type TEXT PRIMARY KEY,
      hidden_at TIMESTAMPTZ DEFAULT now()
    );
  `);
}

function mapRow(row) {
  return {
    id: row.id,
    examType: row.exam_type,
    name: row.name,
    format: row.format,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function slugifyName(name) {
  const base = String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 36);
  const suffix = crypto.randomBytes(4).toString('hex');
  const stem = base.length > 0 ? base : 'exam';
  return `custom_${stem}_${suffix}`;
}

router.get('/', protect, requireAdminOrSupervisor, async (_req, res) => {
  try {
    await ensureCustomExamsTable();
    const result = await pool.query(
      `SELECT id, exam_type, name, format, created_at, updated_at
       FROM public.recruitment_custom_exams
       ORDER BY created_at ASC`
    );
    const hidden = await pool.query(
      `SELECT exam_type FROM public.recruitment_hidden_exams ORDER BY exam_type`
    );
    res.json({
      exams: result.rows.map(mapRow),
      hiddenBuiltin: hidden.rows.map((r) => String(r.exam_type)),
    });
  } catch (err) {
    console.error('[rspCustomExams GET]', err);
    res.status(500).json({
      error: 'Failed to fetch custom exams',
      details: err?.message ?? String(err),
    });
  }
});

router.post('/', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    await ensureCustomExamsTable();
    const name = String(req.body?.name || '').trim();
    const format = String(req.body?.format || '').trim();
    if (!name) {
      return res.status(400).json({ error: 'Exam name is required' });
    }
    if (name.length > 120) {
      return res.status(400).json({ error: 'Exam name is too long (max 120 characters)' });
    }
    if (!FORMATS.has(format)) {
      return res.status(400).json({
        error: 'Invalid format. Use open_ended or multiple_choice.',
      });
    }

    let examType = slugifyName(name);
    for (let i = 0; i < 5 && RESERVED_TYPES.has(examType); i += 1) {
      examType = slugifyName(name);
    }

    const result = await pool.query(
      `INSERT INTO public.recruitment_custom_exams (exam_type, name, format)
       VALUES ($1, $2, $3)
       RETURNING id, exam_type, name, format, created_at, updated_at`,
      [examType, name, format]
    );
    res.status(201).json({ exam: mapRow(result.rows[0]) });
  } catch (err) {
    console.error('[rspCustomExams POST]', err);
    res.status(500).json({
      error: 'Failed to create exam',
      details: err?.message ?? String(err),
    });
  }
});

router.patch('/:id', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    await ensureCustomExamsTable();
    const { id } = req.params;
    const name = String(req.body?.name || '').trim();
    if (!name) {
      return res.status(400).json({ error: 'Exam name is required' });
    }
    if (name.length > 120) {
      return res.status(400).json({ error: 'Exam name is too long (max 120 characters)' });
    }
    const result = await pool.query(
      `UPDATE public.recruitment_custom_exams
       SET name = $1, updated_at = now()
       WHERE id = $2
       RETURNING id, exam_type, name, format, created_at, updated_at`,
      [name, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Exam not found' });
    }
    res.json({ exam: mapRow(result.rows[0]) });
  } catch (err) {
    console.error('[rspCustomExams PATCH]', err);
    res.status(500).json({
      error: 'Failed to update exam',
      details: err?.message ?? String(err),
    });
  }
});

router.post('/hide', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    await ensureCustomExamsTable();
    const examType = String(req.body?.examType || '').trim();
    if (!RESERVED_TYPES.has(examType)) {
      return res.status(400).json({
        error: 'Only built-in exams can be hidden this way.',
      });
    }
    await pool.query(
      `INSERT INTO public.recruitment_hidden_exams (exam_type)
       VALUES ($1)
       ON CONFLICT (exam_type) DO NOTHING`,
      [examType]
    );
    await pool.query(
      `DELETE FROM public.recruitment_exam_questions WHERE exam_type = $1`,
      [examType]
    );
    await pool.query(
      `DELETE FROM public.recruitment_exam_time_limits WHERE exam_type = $1`,
      [examType]
    );
    res.json({ ok: true, examType });
  } catch (err) {
    console.error('[rspCustomExams HIDE]', err);
    res.status(500).json({
      error: 'Failed to delete exam',
      details: err?.message ?? String(err),
    });
  }
});

router.delete('/:id', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    await ensureCustomExamsTable();
    const { id } = req.params;
    const existing = await pool.query(
      `SELECT exam_type FROM public.recruitment_custom_exams WHERE id = $1`,
      [id]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Exam not found' });
    }
    const examType = existing.rows[0].exam_type;
    await pool.query(`DELETE FROM public.recruitment_exam_questions WHERE exam_type = $1`, [
      examType,
    ]);
    await pool.query(`DELETE FROM public.recruitment_exam_time_limits WHERE exam_type = $1`, [
      examType,
    ]);
    await pool.query(`DELETE FROM public.recruitment_custom_exams WHERE id = $1`, [id]);
    res.json({ ok: true });
  } catch (err) {
    console.error('[rspCustomExams DELETE]', err);
    res.status(500).json({
      error: 'Failed to delete exam',
      details: err?.message ?? String(err),
    });
  }
});

module.exports = router;
