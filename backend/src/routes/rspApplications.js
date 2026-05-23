const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const { pool } = require('../config/db');
const {
  assertPositionAcceptingApplications,
} = require('../utils/jobVacancySlots');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const { resolveLocalRspAttachment, RSP_SUBDIR } = require('../utils/rspLocalAttachment');
const { sendSmtpMail, isSmtpConfigured } = require('../utils/smtpMail');
const {
  notifyNewRecruitmentApplication,
  isEmailJsConfiguredForHireEmail,
  sendHireCredentialsEmailJs,
} = require('../utils/emailJsMail');
const { verifyRspEmailVerificationToken } = require('../utils/rspEmailVerifyToken');
const rspEmailVerificationPublicRoutes = require('./rspEmailVerificationPublic');

const router = express.Router();

function rspStep1RequiresEmailOtp() {
  return rspEmailVerificationPublicRoutes.rspEmailOtpEnrollmentActive?.() === true;
}
const protect = [authMiddleware, requireAdmin];

/** BEI needs HR scores for every narrative answer before final pass/fail. */
function beiGradingComplete(answersJson) {
  if (!answersJson || typeof answersJson !== 'object') return true;
  const bei = answersJson.bei;
  if (!bei || typeof bei !== 'object') return true;
  const answers = bei.answers;
  if (!Array.isArray(answers) || answers.length === 0) return true;
  const scores = bei.scores;
  if (!Array.isArray(scores) || scores.length !== answers.length) return false;
  for (const s of scores) {
    if (s == null || String(s).trim() === '') return false;
    const v = Number(s);
    if (Number.isNaN(v)) return false;
  }
  return true;
}

/** @type {Record<string, { pathCol: string, nameCol: string }>} */
const RSP_DOC_KIND_COLUMNS = {
  application_letter: {
    pathCol: 'doc_application_letter_path',
    nameCol: 'doc_application_letter_name',
  },
  resume: { pathCol: 'doc_resume_path', nameCol: 'doc_resume_name' },
  tor: { pathCol: 'doc_tor_path', nameCol: 'doc_tor_name' },
  eligibility_trainings: {
    pathCol: 'doc_eligibility_trainings_path',
    nameCol: 'doc_eligibility_trainings_name',
  },
};

function parseRspDocKind(value) {
  if (value == null || typeof value !== 'string') return null;
  const k = value.trim();
  return Object.prototype.hasOwnProperty.call(RSP_DOC_KIND_COLUMNS, k)
    ? k
    : null;
}

const RSP_APPLICATION_ROW_SELECT = `
  id, full_name, first_name, middle_name, last_name, suffix, sex,
  email, phone, resume_notes, position_applied_for,
  attachment_path, attachment_name,
  doc_application_letter_path, doc_application_letter_name,
  doc_resume_path, doc_resume_name,
  doc_tor_path, doc_tor_name,
  doc_eligibility_trainings_path, doc_eligibility_trainings_name,
  status, final_interview_at, final_interview_passed, hired_user_id,
  hr_account_setup_done,
  created_at, updated_at
`.replace(/\s+/g, ' ');

const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');
const rspAttachmentsRoot = path.join(UPLOAD_DIR, RSP_SUBDIR);
if (!fs.existsSync(rspAttachmentsRoot)) {
  fs.mkdirSync(rspAttachmentsRoot, { recursive: true });
}

const rspUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      const { applicationId } = req.params;
      const dir = path.join(rspAttachmentsRoot, applicationId);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const base = path
        .basename(file.originalname || 'file')
        .replace(/[^\w.\- ()]/g, '_')
        .slice(0, 180);
      const safeBase = base || `file_${Date.now()}`;
      const kind = parseRspDocKind(req.query?.kind);
      if (kind) {
        cb(null, `${kind}_${Date.now()}_${safeBase}`);
      } else {
        cb(null, safeBase);
      }
    },
  }),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = /\.pdf$/i.test(file.originalname || '');
    cb(null, ok);
  },
});

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

  await pool.query(`
    ALTER TABLE public.recruitment_applications
      ADD COLUMN IF NOT EXISTS doc_application_letter_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_application_letter_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_resume_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_resume_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_tor_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_tor_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_name TEXT,
      ADD COLUMN IF NOT EXISTS final_interview_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS final_interview_passed BOOLEAN,
      ADD COLUMN IF NOT EXISTS hired_user_id UUID,
      ADD COLUMN IF NOT EXISTS hr_account_setup_done BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS position_applied_for TEXT,
      ADD COLUMN IF NOT EXISTS first_name TEXT,
      ADD COLUMN IF NOT EXISTS middle_name TEXT,
      ADD COLUMN IF NOT EXISTS last_name TEXT,
      ADD COLUMN IF NOT EXISTS suffix TEXT,
      ADD COLUMN IF NOT EXISTS sex TEXT;
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_recruitment_applications_hired_user'
      ) THEN
        ALTER TABLE public.recruitment_applications
          ADD CONSTRAINT fk_recruitment_applications_hired_user
          FOREIGN KEY (hired_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
      END IF;
    EXCEPTION
      WHEN undefined_table THEN NULL;
    END $$;
  `);
}

// POST /api/rsp/applications
// Public create: applicants submit their basic info + documents.
router.post('/', async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const {
      firstName,
      middleName,
      lastName,
      suffix,
      sex,
      fullName, // legacy
      email,
      phone,
      resumeNotes,
      positionAppliedFor,
      status = 'submitted',
    } = req.body || {};

    const optStr = (v) =>
      typeof v === 'string' && v.trim().length ? v.trim() : null;

    const fn = optStr(firstName);
    const mn = optStr(middleName);
    const ln = optStr(lastName);
    const sx = optStr(sex);
    const suf = optStr(suffix);

    const legacyFull = optStr(fullName);
    const computedFull =
      [fn, mn, ln].filter(Boolean).join(' ') + (suf ? ` ${suf}` : '');
    const finalFullName = (computedFull.trim().length ? computedFull.trim() : legacyFull) || '';

    if (!finalFullName) {
      return res.status(400).json({
        error: 'firstName and lastName are required (or legacy fullName).',
        code: 'NAME_REQUIRED',
      });
    }
    if (!email || typeof email !== 'string') {
      return res.status(400).json({ error: 'email is required' });
    }

    const normalizedEmail = email.trim().toLowerCase();

    if (rspStep1RequiresEmailOtp()) {
      const token = req.body?.emailVerificationToken;
      if (!token || typeof token !== 'string' || !token.trim()) {
        return res.status(403).json({
          error:
            'Verify your email before submitting. Tap “Send code”, then enter the code sent to your inbox.',
          code: 'EMAIL_NOT_VERIFIED',
        });
      }
      if (!verifyRspEmailVerificationToken(token.trim(), normalizedEmail)) {
        return res.status(403).json({
          error:
            'Email verification expired or does not match this address. Send a new code and verify again.',
          code: 'EMAIL_VERIFY_TOKEN_INVALID',
        });
      }
    }

    let position =
      positionAppliedFor == null
        ? null
        : String(positionAppliedFor).trim().slice(0, 500);
    if (position === '') position = null;

    if (position) {
      const cap = await assertPositionAcceptingApplications(position);
      if (!cap.ok) {
        return res.status(cap.status).json({
          error: cap.error,
          code: cap.code,
        });
      }
    }

    const result = await pool.query(
      `
      INSERT INTO public.recruitment_applications
        (full_name, first_name, middle_name, last_name, suffix, sex,
         email, phone, resume_notes, position_applied_for, status, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, $6,
         $7, $8, $9, $10, $11, now(), now())
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [
        finalFullName,
        fn,
        mn,
        ln,
        suf,
        sx,
        normalizedEmail,
        phone ?? null,
        resumeNotes ?? null,
        position,
        status,
      ]
    );

    const application = result.rows[0];
    void (async () => {
      try {
        await notifyNewRecruitmentApplication(application);
      } catch (e) {
        console.error('[rspApplications EmailJS]', e?.message || e);
      }
    })();

    return res.json({ ok: true, application });
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
      SELECT ${RSP_APPLICATION_ROW_SELECT}
      FROM public.recruitment_applications
      WHERE email = $1
      ORDER BY created_at DESC
      LIMIT 1
      `,
      [email.trim().toLowerCase()]
    );

    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'Application not found' });

    const examRes = await pool.query(
      `
      SELECT id, application_id, score_percent, passed, submitted_at, answers_json
      FROM public.recruitment_exam_results
      WHERE application_id = $1
      LIMIT 1
      `,
      [row.id]
    );
    const raw = examRes.rows[0] ?? null;
    let examResult = raw;
    if (raw) {
      const complete = beiGradingComplete(raw.answers_json);
      // Legacy rows may be marked passed before BEI scoring was enforced.
      const beiCompleteForUi = complete || raw.passed === true;
      examResult = {
        id: raw.id,
        application_id: raw.application_id,
        score_percent: raw.score_percent,
        passed: raw.passed,
        submitted_at: raw.submitted_at,
        bei_grading_complete: beiCompleteForUi,
      };
    }

    return res.json({ ok: true, application: row, examResult });
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
      SELECT ${RSP_APPLICATION_ROW_SELECT}
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

// PUT /api/rsp/applications/:applicationId/basic-info
// Admin: correct name, email, or phone on the application record.
router.put('/:applicationId/basic-info', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { fullName, email, phone } = req.body || {};
    const fn = typeof fullName === 'string' ? fullName.trim() : '';
    const em = typeof email === 'string' ? email.trim().toLowerCase() : '';
    const ph =
      phone == null || phone === ''
        ? null
        : String(phone).trim() || null;
    if (!fn) {
      return res.status(400).json({ error: 'fullName is required' });
    }
    if (!em) {
      return res.status(400).json({ error: 'email is required' });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET full_name = $1, email = $2, phone = $3, updated_at = now()
      WHERE id = $4
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [fn, em, ph, applicationId],
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT basic-info]', err);
    return res.status(500).json({
      error: 'Failed to update application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/final-interview
// Admin: schedule or clear final interview datetime for an applicant (e.g. after they passed the exam).
router.put('/:applicationId/final-interview', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { finalInterviewAt } = req.body || {};

    let param = null;
    if (finalInterviewAt === null || finalInterviewAt === undefined || finalInterviewAt === '') {
      param = null;
    } else if (typeof finalInterviewAt === 'string') {
      const d = new Date(finalInterviewAt);
      if (Number.isNaN(d.getTime())) {
        return res.status(400).json({ error: 'finalInterviewAt must be a valid ISO 8601 datetime or null' });
      }
      param = d.toISOString();
    } else {
      return res.status(400).json({ error: 'finalInterviewAt must be an ISO string or null' });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET final_interview_at = $1::timestamptz, updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [param, applicationId],
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT final-interview]', err);
    return res.status(500).json({
      error: 'Failed to update final interview',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/final-interview-outcome
// Admin: record whether the applicant passed the in-person final interview (null = not recorded yet).
router.put('/:applicationId/final-interview-outcome', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const body = req.body || {};
    if (!Object.prototype.hasOwnProperty.call(body, 'passed')) {
      return res.status(400).json({ error: 'passed is required (true, false, or null)' });
    }
    const { passed } = body;
    let value = null;
    if (passed === null) {
      value = null;
    } else if (typeof passed === 'boolean') {
      value = passed;
    } else {
      return res.status(400).json({ error: 'passed must be true, false, or null' });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET final_interview_passed = $1, updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [value, applicationId],
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT final-interview-outcome]', err);
    return res.status(500).json({
      error: 'Failed to update final interview outcome',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/hr-account-setup-monitoring
// Admin: Step 8 applicant messaging only (independent of employee user record / hired link).
router.put('/:applicationId/hr-account-setup-monitoring', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { done } = req.body || {};
    if (typeof done !== 'boolean') {
      return res.status(400).json({ error: 'done (boolean) is required' });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET hr_account_setup_done = $1, updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [done, applicationId],
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT hr-account-setup-monitoring]', err);
    return res.status(500).json({
      error: 'Failed to update account setup monitoring',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/hired-link
// Admin: after creating a users row via POST /api/employees, link it to this application and set status registered.
router.put('/:applicationId/hired-link', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { userId } = req.body || {};
    if (!userId || typeof userId !== 'string') {
      return res.status(400).json({ error: 'userId is required' });
    }

    const appQ = await pool.query(
      `SELECT id, email FROM public.recruitment_applications WHERE id = $1`,
      [applicationId],
    );
    const appRow = appQ.rows[0];
    if (!appRow) return res.status(404).json({ error: 'Application not found' });

    const userQ = await pool.query(
      `SELECT id, email FROM public.users WHERE id = $1`,
      [userId],
    );
    const userRow = userQ.rows[0];
    if (!userRow) return res.status(404).json({ error: 'User not found' });

    const appEmail = String(appRow.email || '').trim().toLowerCase();
    const userEmail = String(userRow.email || '').trim().toLowerCase();
    if (!appEmail || appEmail !== userEmail) {
      return res.status(400).json({
        error: 'Employee email must match the applicant email on this record',
      });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET hired_user_id = $1::uuid,
          status = 'registered',
          updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [userId, applicationId],
    );
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT hired-link]', err);
    return res.status(500).json({
      error: 'Failed to link hired user',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// POST /api/rsp/applications/:applicationId/send-hire-email
// Admin: sends congratulations + login details (EmailJS hire template, or SMTP fallback).
router.post('/:applicationId/send-hire-email', protect, async (req, res) => {
  try {
    const useEmailJs = isEmailJsConfiguredForHireEmail();
    if (!useEmailJs && !isSmtpConfigured()) {
      return res.status(503).json({
        error: 'Email is not configured on the server',
        details:
          'Set EMAILJS_SERVICE_ID, EMAILJS_PUBLIC_KEY, and EMAILJS_TEMPLATE_HIRE_CREDENTIALS_ID; or set SMTP_HOST, SMTP_USER, SMTP_PASS, and SMTP_FROM in the API .env file.',
      });
    }
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { username, password } = req.body || {};
    const u = typeof username === 'string' ? username.trim() : '';
    const p = typeof password === 'string' ? password : '';
    if (!u) {
      return res.status(400).json({ error: 'username is required' });
    }
    if (!p) {
      return res.status(400).json({ error: 'password is required' });
    }

    const appQ = await pool.query(
      `
      SELECT full_name, email, final_interview_passed, hr_account_setup_done
      FROM public.recruitment_applications
      WHERE id = $1
      `,
      [applicationId],
    );
    const row = appQ.rows[0];
    if (!row) {
      return res.status(404).json({ error: 'Application not found' });
    }
    if (row.final_interview_passed !== true) {
      return res.status(400).json({
        error: 'Applicant must be marked as passed the final interview before sending this email',
      });
    }

    const to = String(row.email || '').trim();
    if (!to) {
      return res.status(400).json({ error: 'Applicant has no email on file' });
    }

    const name =
      String(row.full_name || '').trim() || 'Applicant';
    const accountDone = row.hr_account_setup_done === true;
    const accountNote = accountDone
      ? 'Your employee account is ready. Please sign in to the HRMS and change your password after your first login if you are prompted to do so.'
      : 'If you cannot sign in yet, we may still be finishing your access in the system. Please reply to this email and we will assist you.';

    if (useEmailJs) {
      await sendHireCredentialsEmailJs({
        to,
        applicantName: name,
        username: u,
        password: p,
        accountNote,
      });
    } else {
      const subject = 'Congratulations — LGU Plaridel employment';
      const text =
        `Dear ${name},\n\n` +
        'Congratulations! We are pleased to inform you that you have passed the final interview and are hired by LGU Plaridel.\n\n' +
        'Your login details:\n' +
        `Username: ${u}\n` +
        `Password: ${p}\n\n` +
        `${accountNote}\n\n` +
        'Best regards,\n' +
        'Human Resources\n' +
        'LGU Plaridel';

      await sendSmtpMail({ to, subject, text });
    }
    return res.json({
      ok: true,
      message: 'Email sent',
      to,
      via: useEmailJs ? 'emailjs' : 'smtp',
    });
  } catch (err) {
    console.error('[rspApplications POST send-hire-email]', err);
    const msg = err?.message ? String(err.message) : String(err);
    return res.status(500).json({
      error: 'Failed to send email',
      details: msg,
    });
  }
});

// POST /api/rsp/applications/:applicationId/attachment-file
// Public (applicant): save file under uploads/rsp-attachments/{id}/...
// Query updateDb=0 to only store the file and return path (multi-upload helper).
router.post(
  '/:applicationId/attachment-file',
  rspUpload.single('file'),
  async (req, res) => {
    try {
      await ensureRspApplicationsTables();
      const { applicationId } = req.params;
      const updateDb =
        req.query.updateDb !== '0' && req.query.updateDb !== 'false';

      if (!req.file) {
        return res.status(400).json({ error: 'file is required (multipart)' });
      }

      const exists = await pool.query(
        'SELECT id FROM public.recruitment_applications WHERE id = $1',
        [applicationId],
      );
      if (!exists.rows[0]) {
        try {
          fs.unlinkSync(req.file.path);
        } catch (_) {
          /* ignore */
        }
        return res.status(404).json({ error: 'Application not found' });
      }

      const relPath = `${applicationId}/${req.file.filename}`;
      const origName = req.file.originalname || req.file.filename;
      const docKind = parseRspDocKind(req.query?.kind);

      if (updateDb) {
        if (docKind) {
          const { pathCol, nameCol } = RSP_DOC_KIND_COLUMNS[docKind];
          await pool.query(
            `
            UPDATE public.recruitment_applications
            SET "${pathCol}" = $1,
                "${nameCol}" = $2,
                updated_at = now()
            WHERE id = $3
            `,
            [relPath, origName, applicationId],
          );
        } else {
          await pool.query(
            `
            UPDATE public.recruitment_applications
            SET attachment_path = $1,
                attachment_name = $2,
                updated_at = now()
            WHERE id = $3
            `,
            [relPath, origName, applicationId],
          );
        }
      }

      return res.json({
        ok: true,
        path: relPath,
        fileName: origName,
        updateDb,
      });
    } catch (err) {
      if (req.file?.path) {
        try {
          fs.unlinkSync(req.file.path);
        } catch (_) {
          /* ignore */
        }
      }
      console.error('[rspApplications POST attachment-file]', err);
      return res.status(500).json({
        error: 'Failed to store attachment',
        details: err?.message ? String(err.message) : String(err),
      });
    }
  },
);

// DELETE /api/rsp/applications/attachment-file
// Admin: remove a file from local disk (path must match an application in DB).
router.delete('/attachment-file', ...protect, async (req, res) => {
  try {
    const objectPath =
      req.body?.path ?? req.query.path ?? req.query.objectPath ?? null;
    if (!objectPath || typeof objectPath !== 'string') {
      return res.status(400).json({ error: 'path is required' });
    }
    const trimmed = String(objectPath).trim();
    const allowed = await isAttachmentPathAllowedInDb(trimmed);
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const abs = resolveLocalRspAttachment(UPLOAD_DIR, trimmed);
    if (!abs || !fs.existsSync(abs)) {
      return res.status(404).json({ error: 'Local file not found' });
    }
    fs.unlinkSync(abs);
    const t = trimmed;
    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET
        attachment_path = CASE WHEN btrim(COALESCE(attachment_path, '')) = btrim($1::text) THEN NULL ELSE attachment_path END,
        attachment_name = CASE WHEN btrim(COALESCE(attachment_path, '')) = btrim($1::text) THEN NULL ELSE attachment_name END,
        doc_application_letter_path = CASE WHEN btrim(COALESCE(doc_application_letter_path, '')) = btrim($1::text) THEN NULL ELSE doc_application_letter_path END,
        doc_application_letter_name = CASE WHEN btrim(COALESCE(doc_application_letter_path, '')) = btrim($1::text) THEN NULL ELSE doc_application_letter_name END,
        doc_resume_path = CASE WHEN btrim(COALESCE(doc_resume_path, '')) = btrim($1::text) THEN NULL ELSE doc_resume_path END,
        doc_resume_name = CASE WHEN btrim(COALESCE(doc_resume_path, '')) = btrim($1::text) THEN NULL ELSE doc_resume_name END,
        doc_tor_path = CASE WHEN btrim(COALESCE(doc_tor_path, '')) = btrim($1::text) THEN NULL ELSE doc_tor_path END,
        doc_tor_name = CASE WHEN btrim(COALESCE(doc_tor_path, '')) = btrim($1::text) THEN NULL ELSE doc_tor_name END,
        doc_eligibility_trainings_path = CASE WHEN btrim(COALESCE(doc_eligibility_trainings_path, '')) = btrim($1::text) THEN NULL ELSE doc_eligibility_trainings_path END,
        doc_eligibility_trainings_name = CASE WHEN btrim(COALESCE(doc_eligibility_trainings_path, '')) = btrim($1::text) THEN NULL ELSE doc_eligibility_trainings_name END,
        updated_at = now()
      WHERE btrim(COALESCE(attachment_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_application_letter_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_resume_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_tor_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_eligibility_trainings_path, '')) = btrim($1::text)
      `,
      [t],
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error('[rspApplications DELETE attachment-file]', err);
    return res.status(500).json({
      error: 'Failed to delete attachment file',
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
    const { path, fileName, docKind: docKindRaw } = req.body || {};
    if (!path || typeof path !== 'string') {
      return res.status(400).json({ error: 'path is required' });
    }
    if (!fileName || typeof fileName !== 'string') {
      return res.status(400).json({ error: 'fileName is required' });
    }
    const docKind = parseRspDocKind(docKindRaw);
    if (docKind) {
      const { pathCol, nameCol } = RSP_DOC_KIND_COLUMNS[docKind];
      await pool.query(
        `
        UPDATE public.recruitment_applications
        SET "${pathCol}" = $1,
            "${nameCol}" = $2,
            updated_at = now()
        WHERE id = $3
        `,
        [path, fileName, applicationId],
      );
    } else {
      await pool.query(
        `
        UPDATE public.recruitment_applications
        SET attachment_path = $1,
            attachment_name = $2,
            updated_at = now()
        WHERE id = $3
        `,
        [path, fileName, applicationId],
      );
    }
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
    const { path, fileName, docKind: docKindRaw } = req.body || {};
    if (!path || typeof path !== 'string' || !fileName || typeof fileName !== 'string') {
      return res.status(400).json({ error: 'path and fileName are required' });
    }
    const docKind = parseRspDocKind(docKindRaw);
    let result;
    if (docKind) {
      const { pathCol, nameCol } = RSP_DOC_KIND_COLUMNS[docKind];
      result = await pool.query(
        `
        UPDATE public.recruitment_applications
        SET "${pathCol}" = $1,
            "${nameCol}" = $2,
            updated_at = now()
        WHERE id = $3
          AND ("${pathCol}" IS NULL OR btrim("${pathCol}"::text) = '')
        `,
        [path, fileName, applicationId],
      );
    } else {
      result = await pool.query(
        `
        UPDATE public.recruitment_applications
        SET attachment_path = $1,
            attachment_name = $2,
            updated_at = now()
        WHERE id = $3 AND attachment_path IS NULL
        `,
        [path, fileName, applicationId],
      );
    }
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

    const beiComplete = beiGradingComplete(answersJson);
    const effectivePassed = beiComplete ? !!passed : false;
    const appStatus = beiComplete ? (effectivePassed ? 'passed' : 'failed') : 'exam_taken';

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
      [applicationId, score, effectivePassed, answersJson ?? null]
    );

    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET status = $1, updated_at = now()
      WHERE id = $2
      `,
      [appStatus, applicationId]
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

// PUT /api/rsp/applications/exam-results/:applicationId
// Admin: partial update of answers_json / score / passed (does not change application status).
router.put('/exam-results/:applicationId', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const {
      answers_json,
      score_percent,
      passed,
      sync_application_status,
    } = req.body || {};
    const sets = [];
    const params = [];
    let i = 1;
    if (answers_json !== undefined) {
      sets.push(`answers_json = $${i++}`);
      params.push(answers_json);
    }
    if (score_percent !== undefined) {
      sets.push(`score_percent = $${i++}`);
      params.push(Number(score_percent));
    }
    if (passed !== undefined) {
      sets.push(`passed = $${i++}`);
      params.push(!!passed);
    }
    if (sets.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    sets.push('updated_at = now()');
    params.push(applicationId);
    const result = await pool.query(
      `UPDATE public.recruitment_exam_results SET ${sets.join(', ')}
       WHERE application_id = $${i}
       RETURNING id`,
      params
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Exam result not found for this application' });
    }
    if (sync_application_status && passed !== undefined) {
      await pool.query(
        `
        UPDATE public.recruitment_applications
        SET status = $1, updated_at = now()
        WHERE id = $2
        `,
        [passed ? 'passed' : 'failed', applicationId]
      );
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error('[rspApplications PUT exam-results]', err);
    return res.status(500).json({
      error: 'Failed to update exam result',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// DELETE /api/rsp/applications/:applicationId
// Deletes the applicant row and its exam result rows.
//
// Orphan files under uploads/rsp-attachments may remain until removed manually.
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

    const appDir = path.join(rspAttachmentsRoot, applicationId);
    if (fs.existsSync(appDir)) {
      try {
        fs.rmSync(appDir, { recursive: true, force: true });
      } catch (err) {
        console.warn('[rspApplications DELETE] local attachments cleanup', err);
      }
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

