const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrSupervisor } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

async function ensureExamQuestionsTable() {
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.recruitment_exam_questions (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      exam_type TEXT NOT NULL,
      sort_order INT NOT NULL,
      question_text TEXT NOT NULL,
      options_json JSONB,
      correct_index INT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  // Defensive: ensure expected columns exist (in case an older schema ran).
  await pool.query(`
    ALTER TABLE public.recruitment_exam_questions
      ADD COLUMN IF NOT EXISTS options_json JSONB;
  `);
  await pool.query(`
    ALTER TABLE public.recruitment_exam_questions
      ADD COLUMN IF NOT EXISTS correct_index INT;
  `);
}

// Replace all recruitment exam questions for a given exam type.
// This is used by the Flutter RSP admin module to avoid Supabase RLS issues.
//
// BEI / short text questions:
//   PUT /api/rsp/exam-questions/bei
//   { "questions": ["q1", "q2"] }
//
// MCQ questions (general, math, general_info):
//   PUT /api/rsp/exam-questions/general
//   { "questions": [{ "question_text": "...", "options": ["A","B"], "correct": 1 }, ...] }
router.put('/:examType', protect, requireAdminOrSupervisor, async (req, res) => {
  try {
    const { examType } = req.params;
    const { questions } = req.body || {};

    await ensureExamQuestionsTable();

    if (!examType || typeof examType !== 'string') {
      return res.status(400).json({ error: 'Missing examType' });
    }
    if (!Array.isArray(questions)) {
      return res.status(400).json({ error: 'Missing questions array' });
    }

    // Replace: delete then insert in order.
    await pool.query(
      `DELETE FROM public.recruitment_exam_questions WHERE exam_type = $1`,
      [examType]
    );

    if (questions.length === 0) {
      return res.json({ ok: true, inserted: 0 });
    }

    // Insert rows.
    // Each question can be either:
    //  - string (question_text)
    //  - object { question_text, options, correct }
    const rows = questions.map((q, idx) => {
      if (typeof q === 'string') {
        return {
          exam_type: examType,
          sort_order: idx + 1,
          question_text: q,
          options_json: null,
          correct_index: null,
        };
      }

      const questionText = typeof q?.question_text === 'string' ? q.question_text : '';
      const options = Array.isArray(q?.options) ? q.options.map(String) : [];
      const correct = Number.isInteger(q?.correct) ? q.correct : (q?.correct != null ? parseInt(q.correct, 10) : null);

      return {
        exam_type: examType,
        sort_order: idx + 1,
        question_text: questionText,
        options_json: options,
        correct_index: typeof correct === 'number' && !Number.isNaN(correct) ? correct : null,
      };
    }).filter((r) => r.question_text && String(r.question_text).trim().length > 0);

    if (rows.length === 0) {
      return res.json({ ok: true, inserted: 0 });
    }

    // Bulk insert
    // Use parameterized query per row (keeps it simple/safe).
    for (const r of rows) {
      await pool.query(
        `INSERT INTO public.recruitment_exam_questions
          (exam_type, sort_order, question_text, options_json, correct_index, created_at, updated_at)
         VALUES ($1, $2, $3, $4::jsonb, $5, now(), now())`,
        [
          r.exam_type,
          r.sort_order,
          String(r.question_text),
          r.options_json ? JSON.stringify(r.options_json) : JSON.stringify([]),
          r.correct_index,
        ]
      );
    }

    return res.json({ ok: true, inserted: rows.length });
  } catch (err) {
    console.error('[rspExamQuestions PUT]', err);
    res.status(500).json({ error: 'Failed to save exam questions', details: err?.message ?? String(err) });
  }
});

// Public fetch of exam questions (so applicants can load questions without Supabase Auth).
// Returns a list of rows in sort_order order.
router.get('/:examType', async (req, res) => {
  try {
    const { examType } = req.params;
    if (!examType || typeof examType !== 'string') {
      return res.status(400).json({ error: 'Missing examType' });
    }

    await ensureExamQuestionsTable();

    const result = await pool.query(
      `SELECT sort_order, question_text, options_json, correct_index
       FROM public.recruitment_exam_questions
       WHERE exam_type = $1
       ORDER BY sort_order ASC`,
      [examType]
    );

    res.json({
      examType,
      questions: result.rows.map((r) => ({
        question_text: r.question_text,
        options_json: r.options_json,
        correct_index: r.correct_index,
      })),
    });
  } catch (err) {
    console.error('[rspExamQuestions GET]', err);
    res.status(500).json({ error: 'Failed to fetch exam questions', details: err?.message ?? String(err) });
  }
});

module.exports = router;

