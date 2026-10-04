const express = require('express');
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrSupervisor } = require('../middleware/rbac');
const {
  sanitizeExamImagePath,
  sanitizeExamImageCaption,
  normalizeOptionImages,
  imagePathsFromRow,
} = require('../utils/examQuestionImages');

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');

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
  // Optional images/diagrams (nullable, so existing text-only rows are untouched).
  await pool.query(`
    ALTER TABLE public.recruitment_exam_questions
      ADD COLUMN IF NOT EXISTS question_image_path TEXT;
  `);
  await pool.query(`
    ALTER TABLE public.recruitment_exam_questions
      ADD COLUMN IF NOT EXISTS question_image_caption TEXT;
  `);
  await pool.query(`
    ALTER TABLE public.recruitment_exam_questions
      ADD COLUMN IF NOT EXISTS option_images_json JSONB;
  `);
}

/** Best-effort removal of image files no longer referenced by any question. */
async function deleteUnreferencedExamImages(candidatePaths) {
  for (const p of candidatePaths) {
    try {
      const { rows } = await pool.query(
        `SELECT 1 FROM public.recruitment_exam_questions
         WHERE question_image_path = $1 OR option_images_json @> $2::jsonb
         LIMIT 1`,
        [p, JSON.stringify([p])]
      );
      if (rows.length > 0) continue;
      const root = path.resolve(UPLOAD_DIR);
      const abs = path.resolve(root, p);
      if (!abs.startsWith(root + path.sep)) continue;
      await fs.promises.unlink(abs).catch(() => {});
    } catch (err) {
      console.warn('[rspExamQuestions image cleanup]', err?.message ?? err);
    }
  }
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

    // Each question can be either:
    //  - string (question_text)
    //  - object {
    //      question_text, options, correct,
    //      question_image?, question_image_caption?, option_images?
    //    }
    // A question needs text OR an image. `option_images` is parallel to `options`;
    // `options[i]` may be '' when choice i is image-only. `correct` stays an index.
    const rows = questions.map((q, idx) => {
      if (typeof q === 'string') {
        return {
          exam_type: examType,
          sort_order: idx + 1,
          question_text: q,
          options_json: null,
          correct_index: null,
          question_image_path: null,
          question_image_caption: null,
          option_images_json: null,
        };
      }

      const questionText = typeof q?.question_text === 'string' ? q.question_text : '';
      const options = Array.isArray(q?.options) ? q.options.map(String) : [];
      const correct = Number.isInteger(q?.correct) ? q.correct : (q?.correct != null ? parseInt(q.correct, 10) : null);
      const questionImage = sanitizeExamImagePath(q?.question_image);

      return {
        exam_type: examType,
        sort_order: idx + 1,
        question_text: questionText,
        options_json: options,
        correct_index: typeof correct === 'number' && !Number.isNaN(correct) ? correct : null,
        question_image_path: questionImage,
        question_image_caption: questionImage
          ? sanitizeExamImageCaption(q?.question_image_caption)
          : null,
        option_images_json: normalizeOptionImages(q?.option_images, options.length),
      };
    }).filter(
      (r) =>
        (r.question_text && String(r.question_text).trim().length > 0) ||
        r.question_image_path
    );

    const client = await pool.connect();
    let previousImagePaths = [];
    try {
      await client.query('BEGIN');

      const previous = await client.query(
        `SELECT question_image_path, option_images_json
         FROM public.recruitment_exam_questions WHERE exam_type = $1`,
        [examType]
      );
      previousImagePaths = previous.rows.flatMap(imagePathsFromRow);

      // Replace: delete then insert in order.
      await client.query(
        `DELETE FROM public.recruitment_exam_questions WHERE exam_type = $1`,
        [examType]
      );

      for (const r of rows) {
        await client.query(
          `INSERT INTO public.recruitment_exam_questions
            (exam_type, sort_order, question_text, options_json, correct_index,
             question_image_path, question_image_caption, option_images_json,
             created_at, updated_at)
           VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $8::jsonb, now(), now())`,
          [
            r.exam_type,
            r.sort_order,
            String(r.question_text),
            r.options_json ? JSON.stringify(r.options_json) : JSON.stringify([]),
            r.correct_index,
            r.question_image_path,
            r.question_image_caption,
            r.option_images_json ? JSON.stringify(r.option_images_json) : null,
          ]
        );
      }

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK').catch(() => {});
      throw txErr;
    } finally {
      client.release();
    }

    const keptPaths = new Set(rows.flatMap(imagePathsFromRow));
    const removed = [...new Set(previousImagePaths)].filter((p) => !keptPaths.has(p));
    if (removed.length > 0) {
      deleteUnreferencedExamImages(removed).catch(() => {});
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
      `SELECT sort_order, question_text, options_json, correct_index,
              question_image_path, question_image_caption, option_images_json
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
        question_image_path: r.question_image_path ?? null,
        question_image_caption: r.question_image_caption ?? null,
        option_images_json: r.option_images_json ?? null,
      })),
    });
  } catch (err) {
    console.error('[rspExamQuestions GET]', err);
    res.status(500).json({ error: 'Failed to fetch exam questions', details: err?.message ?? String(err) });
  }
});

module.exports = router;

