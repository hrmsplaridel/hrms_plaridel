const express = require('express');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { pool } = require('../config/db');
const {
  assertPositionAcceptingApplications,
  assertApplicantMeetsVacancyAge,
} = require('../utils/jobVacancySlots');
const { todayInHrmsTimezone, isValidIsoCalendarDate } = require('../utils/dateRangeParser');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin, requireAdminOrHr } = require('../middleware/rbac');
const { isAttachmentPathAllowedInDb } = require('../utils/rspAttachmentPolicy');
const { resolveLocalRspAttachment, findLocalRspAttachment, RSP_SUBDIR } = require('../utils/rspLocalAttachment');
const { sendSmtpMail, isSmtpConfigured } = require('../utils/smtpMail');
const {
  isEmailJsConfiguredForHireEmail,
  sendHireCredentialsEmailJs,
  HIRE_CREDENTIALS_EMAIL_SUBJECT,
  HIRE_LOGIN_INSTRUCTIONS,
  buildHireCredentialsAccountNote,
  buildHireCredentialsPlainText,
} = require('../utils/emailJsMail');
const recruitmentNotifications = require('../services/recruitmentNotifications');
const { excludeMayorIntakeStubSql } = require('../utils/mayorIntakeStub');
const {
  verifyRspEmailVerificationToken,
  signRspApplicantAccessToken,
  verifyRspApplicantAccessToken,
} = require('../utils/rspEmailVerifyToken');
const rspEmailVerificationPublicRoutes = require('./rspEmailVerificationPublic');
const {
  publicApplicationCreateLimiter,
  publicApplicationUploadLimiter,
  publicApplicationResubmitLimiter,
  publicApplicationExamLimiter,
  publicLookupLimiter,
} = require('../middleware/rateLimiters');
const issuedForm = require('../services/rspIssuedForm');
const preDeliberation = require('../services/rspPreDeliberation');
const finalHiring = require('../services/rspFinalHiring');
const applicantNotices = require('../services/rspApplicantNotices');
const { broadcastAppEvent } = require('../websockets/appEvents');
const {
  validateRspApplicationCreate,
  parseScore0to100,
} = require('../utils/inputValidation');
const router = express.Router();
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function broadcastRspRecruitmentChanged(applicationId, action) {
  try {
    const payload = {
      applicationId: applicationId ? String(applicationId) : null,
      action,
    };
    broadcastAppEvent('rsp_applications_changed', payload);
    broadcastAppEvent('rsp_exam_results_changed', payload);
  } catch (err) {
    console.error('[rsp recruitment websocket]', err);
  }
}

router.use((req, res, next) => {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
    return next();
  }
  const originalJson = res.json.bind(res);
  res.json = function broadcastThenJson(body) {
    if (res.statusCode < 400) {
      const applicationId =
        req.params?.applicationId || req.body?.applicationId || null;
      broadcastRspRecruitmentChanged(
        applicationId,
        `${req.method} ${req.path}`,
      );
    }
    return originalJson(body);
  };
  next();
});

async function withRspTransaction(work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const outcome = await work(client);
    if (outcome && outcome.rollback) {
      await client.query('ROLLBACK');
    } else {
      await client.query('COMMIT');
    }
    return outcome;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }
}

function rspStep1RequiresEmailOtp() {
  return rspEmailVerificationPublicRoutes.rspEmailOtpEnrollmentActive?.() === true;
}

function applicantToken(req) {
  const authorization = req.get('authorization') || '';
  const bearer = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
  return (
    req.get('x-rsp-applicant-token') ||
    bearer ||
    req.body?.emailVerificationToken ||
    req.query?.emailVerificationToken ||
    ''
  );
}

async function requireApplicantProof(req, res, next) {
  try {
    const authorization = req.get('authorization') || '';
    if (authorization.startsWith('Bearer ') && process.env.JWT_SECRET) {
      try {
        const payload = jwt.verify(authorization.slice(7).trim(), process.env.JWT_SECRET);
        if (payload.typ !== 'refresh' && payload.role === 'admin') {
          return authMiddleware(req, res, () => requireAdmin(req, res, next));
        }
      } catch (_) {
        // It may instead be an applicant proof token; verify it below.
      }
    }
    const applicationId = req.params.applicationId || req.body?.applicationId;
    if (!UUID_RE.test(String(applicationId || ''))) {
      return res.status(400).json({ error: 'Invalid applicationId' });
    }
    const result = await pool.query(
      'SELECT email FROM public.recruitment_applications WHERE id = $1',
      [applicationId],
    );
    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'Application not found' });
    const proof = applicantToken(req);
    if (
      !verifyRspApplicantAccessToken(proof, applicationId, row.email) &&
      !verifyRspEmailVerificationToken(proof, row.email)
    ) {
      return res.status(403).json({
        error: 'Verified applicant access is required',
        code: 'APPLICANT_VERIFICATION_REQUIRED',
      });
    }
    next();
  } catch (err) {
    console.error('[rspApplications applicant proof]', err);
    return res.status(500).json({ error: 'Could not verify applicant access' });
  }
}
const {
  requireAnyRspAccessIfAdmin,
  requireAnyRspRecruitmentIfAdmin,
} = require('../middleware/rspAccess');
const protect = [authMiddleware, requireAdmin, requireAnyRspAccessIfAdmin];
// Required-form review follows the same Admin or HR operators who use the
// recruitment screen. It does not open the rest of the admin recruitment API.
// Admins need any Recruitment Management tab permission from Manage Access.
const recruitmentStaff = [
  authMiddleware,
  requireAdminOrHr,
  requireAnyRspRecruitmentIfAdmin,
];

/** BEI narrative scores for UI only — pass/fail uses MCQ (General/Math/Gen.info). */
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

/** @type {Record<string, { pathCol: string, nameCol: string, rejectReasonCol?: string }>} */
const RSP_DOC_KIND_COLUMNS = {
  application_letter: {
    pathCol: 'doc_application_letter_path',
    nameCol: 'doc_application_letter_name',
    rejectReasonCol: 'doc_application_letter_reject_reason',
  },
  resume: {
    pathCol: 'doc_resume_path',
    nameCol: 'doc_resume_name',
    rejectReasonCol: 'doc_resume_reject_reason',
  },
  tor: {
    pathCol: 'doc_tor_path',
    nameCol: 'doc_tor_name',
    rejectReasonCol: 'doc_tor_reject_reason',
  },
  eligibility_trainings: {
    pathCol: 'doc_eligibility_trainings_path',
    nameCol: 'doc_eligibility_trainings_name',
    rejectReasonCol: 'doc_eligibility_trainings_reject_reason',
  },
  medical_certificate: {
    pathCol: 'doc_medical_certificate_path',
    nameCol: 'doc_medical_certificate_name',
    rejectReasonCol: 'doc_medical_certificate_reject_reason',
  },
  drug_test_result: {
    pathCol: 'doc_drug_test_path',
    nameCol: 'doc_drug_test_name',
    rejectReasonCol: 'doc_drug_test_reject_reason',
  },
  nbi_clearance: {
    pathCol: 'doc_nbi_clearance_path',
    nameCol: 'doc_nbi_clearance_name',
    rejectReasonCol: 'doc_nbi_clearance_reject_reason',
  },
};

const INITIAL_APPLICATION_DOC_KINDS = new Set([
  'application_letter',
  'resume',
  'tor',
  'eligibility_trainings',
]);

const FINAL_REQUIREMENT_KINDS = new Set([
  'medical_certificate',
  'drug_test_result',
  'nbi_clearance',
]);

function parseRspDocKind(value) {
  if (value == null || typeof value !== 'string') return null;
  const k = value.trim();
  return Object.prototype.hasOwnProperty.call(RSP_DOC_KIND_COLUMNS, k)
    ? k
    : null;
}

const RSP_APPLICATION_ROW_SELECT = `
  id, applicant_number, full_name, first_name, middle_name, last_name, suffix, sex,
  course, address, age, to_char(date_of_birth, 'YYYY-MM-DD') AS date_of_birth, civil_status,
  email, phone, resume_notes, position_applied_for,
  attachment_path, attachment_name,
  doc_application_letter_path, doc_application_letter_name,
  doc_application_letter_reject_reason,
  doc_resume_path, doc_resume_name,
  doc_resume_reject_reason,
  doc_tor_path, doc_tor_name,
  doc_tor_reject_reason,
  doc_eligibility_trainings_path, doc_eligibility_trainings_name,
  doc_eligibility_trainings_reject_reason,
  doc_medical_certificate_path, doc_medical_certificate_name,
  doc_drug_test_path, doc_drug_test_name,
  doc_nbi_clearance_path, doc_nbi_clearance_name,
  doc_medical_certificate_reject_reason,
  doc_drug_test_reject_reason,
  doc_nbi_clearance_reject_reason,
  document_revision_used,
  final_requirements_revision_used,
  final_requirements_approved,
  orientation_at,
  orientation_attended,
  status, final_interview_at, final_interview_passed, hired_user_id,
  hr_account_setup_done, hire_credentials_email_sent_at,
  hire_login_username,
  step2_gate_required, required_form_type, required_form_status,
  required_form_entry_id, required_form_assigned_at, required_form_submitted_at,
  required_form_reviewed_at, required_form_review_comment,
  step4_gate_required, wes_status, wes_review_comment,
  applicants_profile_status, selection_lineup_status,
  step5_gate_required, tat_entry_id, tat_status,
  csc_approval_status,
  created_at, updated_at
`.replace(/\s+/g, ' ');

/** Never expose hire plaintext passwords to admin/applicant API clients. */
function redactHireSecrets(row) {
  if (!row || typeof row !== 'object') return row;
  const out = { ...row };
  delete out.hire_login_password;
  return out;
}

function redactHireSecretsMany(rows) {
  return (rows || []).map(redactHireSecrets);
}

/** Unambiguous alphabet (no 0/O/1/I) for human-readable applicant IDs. */
const APPLICANT_NUMBER_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** YYYY-MM-DD birth date, or an error. Vacancy rules decide the allowed age. */
function normalizeDateOfBirth(raw) {
  if (raw == null || raw === '') {
    const err = new Error('Date of birth is required.');
    err.statusCode = 400;
    throw err;
  }
  const s = String(raw).trim();
  if (!isValidIsoCalendarDate(s)) {
    const err = new Error('dateOfBirth must be a valid YYYY-MM-DD date');
    err.statusCode = 400;
    throw err;
  }
  const today = todayInHrmsTimezone();
  if (s > today) {
    const err = new Error('dateOfBirth cannot be in the future');
    err.statusCode = 400;
    throw err;
  }
  return s;
}

function generateApplicantNumberCandidate() {
  let body = '';
  for (let i = 0; i < 8; i += 1) {
    body += APPLICANT_NUMBER_ALPHABET[
      Math.floor(Math.random() * APPLICANT_NUMBER_ALPHABET.length)
    ];
  }
  return `PLR-${body}`;
}

async function allocateUniqueApplicantNumber(client = pool) {
  for (let attempt = 0; attempt < 24; attempt += 1) {
    const candidate = generateApplicantNumberCandidate();
    const exists = await client.query(
      `SELECT 1 FROM public.recruitment_applications WHERE applicant_number = $1 LIMIT 1`,
      [candidate],
    );
    if (exists.rows.length === 0) return candidate;
  }
  throw new Error('Unable to allocate a unique applicant number');
}

function normalizeApplicantNumber(raw) {
  if (raw == null) return '';
  return String(raw)
    .trim()
    .toUpperCase()
    .replace(/[\s_]+/g, '-')
    .replace(/[^A-Z0-9-]/g, '');
}
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

function rejectInvalidApplicationId(req, res, next) {
  if (!UUID_RE.test(String(req.params.applicationId || ''))) {
    return res.status(400).json({ error: 'Invalid applicationId' });
  }
  next();
}

function uploadedFileIsPdf(filePath) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'r');
    const signature = Buffer.alloc(5);
    return fs.readSync(fd, signature, 0, signature.length, 0) === 5 && signature.toString() === '%PDF-';
  } catch (_) {
    return false;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

async function ensureRspApplicationsTables() {
  // Defensive: allow delete to work even if init-schema.sql wasn't run yet.
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
            'registered',
            'endorsed',
            'rejected'
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
      ADD COLUMN IF NOT EXISTS doc_application_letter_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_resume_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_resume_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_resume_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_tor_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_tor_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_tor_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_eligibility_trainings_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_medical_certificate_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_medical_certificate_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_drug_test_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_drug_test_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_nbi_clearance_path TEXT,
      ADD COLUMN IF NOT EXISTS doc_nbi_clearance_name TEXT,
      ADD COLUMN IF NOT EXISTS doc_medical_certificate_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_drug_test_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS doc_nbi_clearance_reject_reason TEXT,
      ADD COLUMN IF NOT EXISTS document_revision_used BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS final_requirements_revision_used BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS final_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS orientation_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS orientation_attended BOOLEAN,
      ADD COLUMN IF NOT EXISTS final_interview_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS final_interview_passed BOOLEAN,
      ADD COLUMN IF NOT EXISTS hired_user_id UUID,
      ADD COLUMN IF NOT EXISTS hr_account_setup_done BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS hr_account_setup_linked_sync BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS hire_credentials_email_sent_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS hire_login_username TEXT,
      ADD COLUMN IF NOT EXISTS hire_login_password TEXT,
      ADD COLUMN IF NOT EXISTS position_applied_for TEXT,
      ADD COLUMN IF NOT EXISTS first_name TEXT,
      ADD COLUMN IF NOT EXISTS middle_name TEXT,
      ADD COLUMN IF NOT EXISTS last_name TEXT,
      ADD COLUMN IF NOT EXISTS suffix TEXT,
      ADD COLUMN IF NOT EXISTS sex TEXT,
      ADD COLUMN IF NOT EXISTS course TEXT,
      ADD COLUMN IF NOT EXISTS address TEXT,
      ADD COLUMN IF NOT EXISTS age TEXT,
      ADD COLUMN IF NOT EXISTS date_of_birth DATE,
      ADD COLUMN IF NOT EXISTS civil_status TEXT,
      ADD COLUMN IF NOT EXISTS applicant_number TEXT,
      ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
  `);

  // Backfill missing applicant numbers with unique random codes.
  {
    const missing = await pool.query(
      `SELECT id
       FROM public.recruitment_applications
       WHERE applicant_number IS NULL OR btrim(applicant_number) = ''`,
    );
    for (const row of missing.rows) {
      const number = await allocateUniqueApplicantNumber();
      await pool.query(
        `UPDATE public.recruitment_applications
         SET applicant_number = $2
         WHERE id = $1::uuid
           AND (applicant_number IS NULL OR btrim(applicant_number) = '')`,
        [row.id, number],
      );
    }
  }

  // Accounts already created before Step 8 was tied to account creation.
  // Marked once so a later manual "Not yet" is kept.
  await pool.query(`
    UPDATE public.recruitment_applications
    SET hr_account_setup_done = TRUE,
        hr_account_setup_linked_sync = TRUE,
        updated_at = now()
    WHERE hr_account_setup_linked_sync IS NOT TRUE
      AND (hired_user_id IS NOT NULL OR status = 'registered')
  `);

  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS uq_recruitment_applications_applicant_number
      ON public.recruitment_applications (applicant_number)
      WHERE applicant_number IS NOT NULL AND btrim(applicant_number) <> '';
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_recruitment_applications_applicant_number
      ON public.recruitment_applications (applicant_number);
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

  await issuedForm.assertIssuedFormSchema();
  await preDeliberation.assertPreDeliberationSchema();
  await finalHiring.assertFinalHiringSchema();
}

// POST /api/rsp/applications
// Public create: applicants submit their basic info + documents.
router.post('/', publicApplicationCreateLimiter, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const {
      dateOfBirth,
      resumeNotes,
      positionAppliedFor,
    } = req.body || {};

    const validated = validateRspApplicationCreate(req.body || {});
    if (!validated.ok) {
      return res.status(validated.status).json({
        error: validated.error,
        code: validated.code,
      });
    }

    const {
      firstName: fn,
      middleName: mn,
      lastName: ln,
      suffix: suf,
      sex: sx,
      course,
      address,
      civilStatus,
      email: normalizedEmail,
      phone,
      finalFullName,
    } = validated.data;

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

    const cap = await assertPositionAcceptingApplications(position);
    if (!cap.ok) {
      return res.status(cap.status).json({
        error: cap.error,
        code: cap.code,
      });
    }

    let birthDate;
    try {
      birthDate = normalizeDateOfBirth(dateOfBirth);
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    const ageCheck = await assertApplicantMeetsVacancyAge(position, birthDate);
    if (!ageCheck.ok) {
      return res.status(ageCheck.status).json({
        error: ageCheck.error,
        code: ageCheck.code,
      });
    }

    const applicantNumber = await allocateUniqueApplicantNumber();

    const result = await pool.query(
      `
      INSERT INTO public.recruitment_applications
        (applicant_number, full_name, first_name, middle_name, last_name, suffix, sex,
         course, address, age, date_of_birth, civil_status,
         email, phone, resume_notes, position_applied_for, status, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7,
         $8, $9, $10, $11::date, $12,
         $13, $14, $15, $16, $17, now(), now())
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [
        applicantNumber,
        finalFullName,
        fn,
        mn,
        ln,
        suf,
        sx,
        course,
        address,
        String(ageCheck.age),
        birthDate,
        civilStatus,
        normalizedEmail,
        phone,
        typeof resumeNotes === 'string' ? resumeNotes : null,
        position,
        'submitted',
      ]
    );

    const application = result.rows[0];
    void (async () => {
      try {
        await recruitmentNotifications.notifyNewApplication(pool, application);
      } catch (e) {
        console.error('[rspApplications in-app notify]', e?.message || e);
      }
    })();

    const applicantAccessToken = signRspApplicantAccessToken(application.id, normalizedEmail);
    return res.json({ ok: true, application, applicantAccessToken });
  } catch (err) {
    console.error('[rspApplications POST /]', err);
    return res.status(500).json({
      error: 'Failed to create application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

const PUBLIC_TRACKING_APPLICATION_SELECT = `
  id, applicant_number, full_name, email, position_applied_for, status,
  orientation_at, orientation_attended, final_interview_at,
  final_interview_passed, final_requirements_approved,
  hr_account_setup_done, hired_user_id,
  hire_credentials_email_sent_at,
  step2_gate_required, required_form_type, required_form_status,
  required_form_entry_id, required_form_assigned_at,
  required_form_submitted_at, required_form_reviewed_at,
  required_form_review_comment,
  step4_gate_required, wes_status, wes_review_comment,
  applicants_profile_status, selection_lineup_status,
  step5_gate_required, tat_status, csc_approval_status,
  doc_application_letter_path, doc_application_letter_name,
  doc_application_letter_reject_reason,
  doc_resume_path, doc_resume_name,
  doc_resume_reject_reason,
  doc_tor_path, doc_tor_name,
  doc_tor_reject_reason,
  doc_eligibility_trainings_path, doc_eligibility_trainings_name,
  doc_eligibility_trainings_reject_reason,
  doc_medical_certificate_path, doc_medical_certificate_name,
  doc_drug_test_path, doc_drug_test_name,
  doc_nbi_clearance_path, doc_nbi_clearance_name,
  doc_medical_certificate_reject_reason,
  doc_drug_test_reject_reason,
  doc_nbi_clearance_reject_reason,
  document_revision_used,
  final_requirements_revision_used,
  created_at, updated_at
`.replace(/\s+/g, ' ');

/** Status, exam summary, and continue token for email or Application ID lookup. */
async function publicTrackingPayload(row, logLabel) {
  const examRes = await pool.query(
    `
    SELECT id, application_id, score_percent, passed, submitted_at, answers_json
    FROM public.recruitment_exam_results
    WHERE application_id = $1
    LIMIT 1
    `,
    [row.id],
  );
  const raw = examRes.rows[0] ?? null;
  let examResult = raw;
  if (raw) {
    const complete = beiGradingComplete(raw.answers_json);
    // Truthful BEI grading flag only — pass/fail is MCQ-based and independent.
    examResult = {
      id: raw.id,
      application_id: raw.application_id,
      score_percent: raw.score_percent,
      passed: raw.passed,
      submitted_at: raw.submitted_at,
      bei_grading_complete: complete,
    };
  }

  let applicantAccessToken = null;
  try {
    applicantAccessToken = signRspApplicantAccessToken(
      row.id,
      String(row.email || '').trim().toLowerCase(),
    );
  } catch (tokenErr) {
    console.error(logLabel, tokenErr);
  }

  const application = redactHireSecrets({ ...row });
  delete application.hire_login_username;

  return {
    ok: true,
    application,
    examResult,
    ...(applicantAccessToken ? { applicantAccessToken } : {}),
  };
}

// GET /api/rsp/applications/by-email?email=...
// Public lookup for applicants to continue their flow.
router.get('/by-email', publicLookupLimiter, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const email = req.query.email;
    if (!email || typeof email !== 'string') {
      return res.status(400).json({ error: 'email query param is required' });
    }
    const result = await pool.query(
      `
      SELECT ${PUBLIC_TRACKING_APPLICATION_SELECT}
      FROM public.recruitment_applications
      WHERE email = $1
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 1
      `,
      [email.trim().toLowerCase()]
    );

    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'Application not found' });

    return res.json(
      await publicTrackingPayload(row, '[rspApplications GET /by-email] applicant token'),
    );
  } catch (err) {
    console.error('[rspApplications GET /by-email]', err);
    return res.status(500).json({
      error: 'Failed to fetch application by email',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// GET /api/rsp/applications/by-applicant-number?number=PLR-XXXXXXXX
// Same tracking payload as by-email, keyed by the Application ID on the form.
router.get('/by-applicant-number', publicLookupLimiter, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const number = normalizeApplicantNumber(req.query.number ?? req.query.id);
    if (!number) {
      return res.status(400).json({
        error: 'number query param is required (e.g. PLR-AB12CD34)',
      });
    }

    const result = await pool.query(
      `
      SELECT ${PUBLIC_TRACKING_APPLICATION_SELECT}
      FROM public.recruitment_applications
      WHERE upper(applicant_number) = $1
        AND deleted_at IS NULL
      LIMIT 1
      `,
      [number],
    );

    const row = result.rows[0];
    if (!row) return res.status(404).json({ error: 'Applicant ID not found' });

    return res.json(
      await publicTrackingPayload(
        row,
        '[rspApplications GET /by-applicant-number] applicant token',
      ),
    );
  } catch (err) {
    console.error('[rspApplications GET /by-applicant-number]', err);
    return res.status(500).json({
      error: 'Failed to look up applicant ID',
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
      WHERE ${excludeMayorIntakeStubSql()}
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      `
    );
    return res.json({
      ok: true,
      applications: redactHireSecretsMany(result.rows),
    });
  } catch (err) {
    console.error('[rspApplications GET /]', err);
    return res.status(500).json({
      error: 'Failed to list applications',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

router.get('/recycle-bin', protect, async (_req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `
      SELECT ${RSP_APPLICATION_ROW_SELECT}
      FROM public.recruitment_applications
      WHERE deleted_at IS NOT NULL
      ORDER BY deleted_at DESC
      `,
    );
    return res.json({
      ok: true,
      applications: redactHireSecretsMany(result.rows),
    });
  } catch (err) {
    console.error('[rspApplications GET /recycle-bin]', err);
    return res.status(500).json({
      error: 'Failed to list recycled applications',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// Active recruitment rows HR may attach to a Turn-Around Time form.
// Declined, failed, and rejected applications stay out. Selection does not
// change status or CSC approval; those rules remain on their own endpoints.
const TAT_SELECTABLE_STATUSES = [
  'submitted',
  'document_approved',
  'exam_taken',
  'passed',
  'registered',
];

router.get('/tat-applicant-choices', protect, async (_req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `
      SELECT id, applicant_number, full_name, position_applied_for, status, final_interview_at
      FROM public.recruitment_applications
      WHERE ${excludeMayorIntakeStubSql()}
        AND deleted_at IS NULL
        AND status = ANY($1::text[])
      ORDER BY full_name ASC, applicant_number ASC
      `,
      [TAT_SELECTABLE_STATUSES],
    );
    return res.json({ ok: true, applications: result.rows });
  } catch (err) {
    console.error('[rspApplications GET /tat-applicant-choices]', err);
    return res.status(500).json({
      error: 'Failed to list applicants',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// Statuses owned by the RSP pipeline; `endorsed` / `rejected` belong to the Mayor module.
const RSP_ADMIN_STATUSES = new Set([
  'submitted',
  'document_approved',
  'document_declined',
  'exam_taken',
  'passed',
  'failed',
  'registered',
]);

// PUT /api/rsp/applications/:applicationId/status
// Admin status updates (approve/decline/failed/passed).
router.put('/:applicationId/status', protect, async (req, res) => {
  try {
    const { applicationId } = req.params;
    const { status } = req.body || {};
    if (!status || typeof status !== 'string') {
      return res.status(400).json({ error: 'status is required' });
    }
    if (!RSP_ADMIN_STATUSES.has(status)) {
      return res.status(400).json({ error: 'Unsupported application status' });
    }
    await ensureRspApplicationsTables();
    const outcome = await withRspTransaction(async (client) => {
      const current = await client.query(
        `SELECT status, email, full_name, applicant_number, position_applied_for
         FROM public.recruitment_applications
         WHERE id = $1
         FOR UPDATE`,
        [applicationId],
      );
      if ((current.rowCount ?? 0) === 0) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      const previousStatus = current.rows[0].status;
      const enableGate =
        status === 'document_approved' &&
        issuedForm.shouldEnableIssuedFormGate(previousStatus);
      const result = await client.query(
        `
        UPDATE public.recruitment_applications
        SET status = $1,
            updated_at = now(),
            step2_gate_required = CASE WHEN $3::boolean THEN TRUE ELSE step2_gate_required END,
            required_form_status = CASE
              WHEN $3::boolean THEN COALESCE(required_form_status, 'waiting_for_hr_form')
              ELSE required_form_status
            END
        WHERE id = $2
        `,
        [status, applicationId, enableGate],
      );
      if ((result.rowCount ?? 0) === 0) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      return {
        status: 200,
        body: { ok: true },
        notice: {
          applicationId,
          previousStatus,
          nextStatus: status,
          applicant: current.rows[0],
        },
      };
    });
    if (outcome.notice) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyDocumentDecision(outcome.notice),
      );
    }
    return res.status(outcome.status).json(outcome.body);
  } catch (err) {
    console.error('[rspApplications PUT status]', err);
    return res.status(500).json({
      error: 'Failed to update application status',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

function issuedFormPayload(result) {
  return {
    ok: true,
    assignment: result.assignment,
    entry: result.entry || null,
    created: result.created === true,
    duplicate: result.duplicate === true,
  };
}

router.get('/:applicationId/required-form', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.getRequiredForm(req.params.applicationId);
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications GET required-form]');
  }
});

router.post('/:applicationId/required-form/assign', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.assignRequiredForm({
      applicationId: req.params.applicationId,
      formType: req.body?.formType,
      actorId: req.user?.id,
    });
    if (result.applicantNotice === true) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyActionRequired({
          applicationId: req.params.applicationId,
          formKey: result.assignment?.formType,
          mode: 'assign',
        }),
      );
    }
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/assign]');
  }
});

router.post('/:applicationId/required-form/undo', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.undoRequiredFormAssignment({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
    });
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/undo]');
  }
});

router.post('/:applicationId/required-form/approve', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.approveRequiredForm({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
    });
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/approve]');
  }
});

router.post('/:applicationId/required-form/fail', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.failRequiredForm({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
      comment: req.body?.comment,
    });
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/fail]');
  }
});

router.post('/:applicationId/required-form/revision', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.requestFormRevision({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
      comment: req.body?.comment,
    });
    if (result.applicantNotice === true) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyActionRequired({
          applicationId: req.params.applicationId,
          formKey: result.assignment?.formType,
          mode: 'revision',
          comment: result.assignment?.reviewComment,
        }),
      );
    }
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/revision]');
  }
});

router.get('/:applicationId/required-form/mine', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.getRequiredForm(req.params.applicationId);
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications GET required-form/mine]');
  }
});

router.put('/:applicationId/required-form/draft', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.saveApplicantDraft({
      applicationId: req.params.applicationId,
      body: req.body || {},
    });
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications PUT required-form/draft]');
  }
});

router.post('/:applicationId/required-form/submit', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await issuedForm.submitApplicantForm({
      applicationId: req.params.applicationId,
      body: req.body || {},
    });
    return res.json(issuedFormPayload(result));
  } catch (err) {
    return issuedForm.sendIssuedFormError(res, err, '[rspApplications POST required-form/submit]');
  }
});

function preDeliberationPayload(result, { includeHrForms }) {
  return {
    ok: true,
    tracking: result.tracking,
    wes: result.wes || null,
    ...(includeHrForms
      ? { profile: result.profile || null, lineup: result.lineup || null }
      : {}),
    created: result.created === true,
    duplicate: result.duplicate === true,
  };
}

router.get('/:applicationId/pre-deliberation', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.getPreDeliberation(req.params.applicationId, {
      includeHrForms: true,
    });
    return res.json(preDeliberationPayload(result, { includeHrForms: true }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications GET pre-deliberation]');
  }
});

router.post('/:applicationId/work-experience/assign', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.assignWorkExperience({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
    });
    if (result.applicantNotice === true) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyActionRequired({
          applicationId: req.params.applicationId,
          formKey: 'wes',
          mode: 'assign',
        }),
      );
    }
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST work-experience/assign]');
  }
});

router.post('/:applicationId/work-experience/approve', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.reviewWes({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
      approve: true,
    });
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST work-experience/approve]');
  }
});

router.post('/:applicationId/work-experience/revision', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.reviewWes({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
      approve: false,
      comment: req.body?.comment,
    });
    if (result.applicantNotice === true) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyActionRequired({
          applicationId: req.params.applicationId,
          formKey: 'wes',
          mode: 'revision',
          comment: result.tracking?.wesReviewComment,
        }),
      );
    }
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST work-experience/revision]');
  }
});

router.post('/:applicationId/applicants-profile/open', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.openHrForm({
      applicationId: req.params.applicationId,
      kind: 'profile',
      actorId: req.user?.id,
    });
    return res.json({ ok: true, tracking: result.tracking, entry: result.entry, created: result.created === true });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST applicants-profile/open]');
  }
});

router.post('/:applicationId/applicants-profile/complete', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.completeHrForm({
      applicationId: req.params.applicationId,
      kind: 'profile',
      actorId: req.user?.id,
    });
    return res.json({ ok: true, tracking: result.tracking, duplicate: result.duplicate === true });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST applicants-profile/complete]');
  }
});

router.post('/:applicationId/selection-lineup/open', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.openHrForm({
      applicationId: req.params.applicationId,
      kind: 'lineup',
      actorId: req.user?.id,
    });
    return res.json({ ok: true, tracking: result.tracking, entry: result.entry, created: result.created === true });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST selection-lineup/open]');
  }
});

router.post('/:applicationId/selection-lineup/complete', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.completeHrForm({
      applicationId: req.params.applicationId,
      kind: 'lineup',
      actorId: req.user?.id,
    });
    return res.json({ ok: true, tracking: result.tracking, duplicate: result.duplicate === true });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST selection-lineup/complete]');
  }
});

function rejectInvalidEntryId(req, res, next) {
  if (!UUID_RE.test(String(req.params.entryId || ''))) {
    return res.status(400).json({ error: 'Invalid form id' });
  }
  next();
}

async function completeSharedForm(req, res, kind) {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.completeSharedHrForm({
      kind,
      entryId: req.params.entryId,
      actorId: req.user?.id,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, `[rspApplications POST hr-forms ${kind} complete]`);
  }
}

async function readSharedFormCompletion(req, res, kind) {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.sharedHrFormCompletion({
      kind,
      entryId: req.params.entryId,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, `[rspApplications GET hr-forms ${kind} completion]`);
  }
}

router.get('/hr-forms/applicants-profile/:entryId/completion', recruitmentStaff, rejectInvalidEntryId, (req, res) => readSharedFormCompletion(req, res, 'profile'));
router.post('/hr-forms/applicants-profile/:entryId/complete', recruitmentStaff, rejectInvalidEntryId, (req, res) => completeSharedForm(req, res, 'profile'));
router.get('/hr-forms/selection-lineup/:entryId/completion', recruitmentStaff, rejectInvalidEntryId, (req, res) => readSharedFormCompletion(req, res, 'lineup'));
router.post('/hr-forms/selection-lineup/:entryId/complete', recruitmentStaff, rejectInvalidEntryId, (req, res) => completeSharedForm(req, res, 'lineup'));

router.get('/final-hiring/sources', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `SELECT a.id, a.full_name, a.position_applied_for, a.final_interview_at,
              e.submitted_at AS exam_submitted_at, e.passed AS exam_passed
       FROM public.recruitment_applications a
       LEFT JOIN public.recruitment_exam_results e ON e.application_id = a.id
       WHERE a.deleted_at IS NULL
         AND a.step5_gate_required = TRUE
         AND a.final_interview_passed = TRUE
       ORDER BY a.full_name`,
    );
    return res.json({ ok: true, applications: result.rows });
  } catch (err) {
    return finalHiring.sendFinalHiringError(res, err, '[rspApplications GET final-hiring/sources]');
  }
});

router.get('/hr-forms/turn-around-time/:entryId/completion', recruitmentStaff, rejectInvalidEntryId, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await finalHiring.tatCompletion({ entryId: req.params.entryId });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return finalHiring.sendFinalHiringError(res, err, '[rspApplications GET turn-around-time completion]');
  }
});

router.post('/hr-forms/turn-around-time/:entryId/complete', recruitmentStaff, rejectInvalidEntryId, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await finalHiring.completeTurnAroundTime({
      entryId: req.params.entryId,
      actorId: req.user?.id,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return finalHiring.sendFinalHiringError(res, err, '[rspApplications POST turn-around-time complete]');
  }
});

router.get('/:applicationId/work-experience/mine', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.getPreDeliberation(req.params.applicationId, {
      includeHrForms: false,
    });
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications GET work-experience/mine]');
  }
});

router.put('/:applicationId/work-experience/draft', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.saveApplicantWes({
      applicationId: req.params.applicationId,
      body: req.body || {},
      submit: false,
    });
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications PUT work-experience/draft]');
  }
});

router.post('/:applicationId/work-experience/submit', requireApplicantProof, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const result = await preDeliberation.saveApplicantWes({
      applicationId: req.params.applicationId,
      body: req.body || {},
      submit: true,
    });
    return res.json(preDeliberationPayload(result, { includeHrForms: false }));
  } catch (err) {
    return preDeliberation.sendPreDeliberationError(res, err, '[rspApplications POST work-experience/submit]');
  }
});

// POST /api/rsp/applications/:applicationId/documents/:kind/reject
// Admin: reject one Step 1 PDF so the applicant only re-uploads that file.
router.post(
  '/:applicationId/documents/:kind/reject',
  ...protect,
  rejectInvalidApplicationId,
  async (req, res) => {
    try {
      await ensureRspApplicationsTables();
      const { applicationId, kind: kindRaw } = req.params;
      const docKind = parseRspDocKind(kindRaw);
      if (!docKind || !INITIAL_APPLICATION_DOC_KINDS.has(docKind)) {
        return res.status(400).json({
          error:
            'kind must be application_letter, resume, tor, or eligibility_trainings',
        });
      }
      const reasonRaw =
        typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
      const reason =
        reasonRaw.slice(0, 500) ||
        'HR requested a new upload for this document.';
      const { pathCol, nameCol, rejectReasonCol } =
        RSP_DOC_KIND_COLUMNS[docKind];
      if (!rejectReasonCol) {
        return res.status(500).json({ error: 'Reject reason column missing' });
      }

      const outcome = await withRspTransaction(async (client) => {
        const check = await client.query(
          `
          SELECT id, status, email, full_name, applicant_number, position_applied_for,
                 document_revision_used,
                 "${pathCol}" AS file_path, "${nameCol}" AS file_name
          FROM public.recruitment_applications
          WHERE id = $1
          FOR UPDATE
          `,
          [applicationId],
        );
        if (!check.rows[0]) {
          return { rollback: true, status: 404, body: { error: 'Application not found' } };
        }
        const row = check.rows[0];
        const status = String(row.status || '').toLowerCase();
        if (status !== 'submitted' && status !== 'document_declined') {
          return {
            rollback: true,
            status: 409,
            body: {
              error:
                'Documents can only be rejected while the application is under document review.',
              code: 'DOCUMENT_REJECT_NOT_ALLOWED',
            },
          };
        }
        // One revision round: after the applicant resubmits, HR may only approve or fail.
        if (status === 'submitted' && row.document_revision_used === true) {
          return {
            rollback: true,
            status: 409,
            body: {
              error:
                'This applicant already used their one document revision. Approve the documents or mark Did not pass.',
              code: 'DOCUMENT_REVISION_ALREADY_USED',
            },
          };
        }
        if (!row.file_path || String(row.file_path).trim() === '') {
          return {
            rollback: true,
            status: 400,
            body: { error: 'No uploaded file to reject for this document.' },
          };
        }

        const objectPath = String(row.file_path).trim();
        const displayName = row.file_name || path.basename(objectPath);
        const abs =
          findLocalRspAttachment(UPLOAD_DIR, objectPath, displayName) ||
          resolveLocalRspAttachment(UPLOAD_DIR, objectPath);
        if (abs && fs.existsSync(abs)) {
          try {
            fs.unlinkSync(abs);
          } catch (e) {
            console.warn('[rspApplications reject step1 doc] unlink', e?.message);
          }
        }

        const result = await client.query(
          `
          UPDATE public.recruitment_applications
          SET "${pathCol}" = NULL,
              "${nameCol}" = NULL,
              "${rejectReasonCol}" = $1,
              status = 'document_declined',
              updated_at = now()
          WHERE id = $2
          RETURNING ${RSP_APPLICATION_ROW_SELECT}
          `,
          [reason, applicationId],
        );
        return {
          status: 200,
          body: { ok: true, application: result.rows[0] },
          notice: {
            applicationId,
            previousStatus: row.status,
            nextStatus: 'document_declined',
            applicant: row,
          },
        };
      });
      if (outcome.notice) {
        await applicantNotices.safeNotify(() =>
          applicantNotices.notifyDocumentDecision(outcome.notice),
        );
      }
      return res.status(outcome.status).json(outcome.body);
    } catch (err) {
      console.error('[rspApplications POST documents reject]', err);
      return res.status(500).json({
        error: 'Failed to reject document',
        details: err?.message ? String(err.message) : String(err),
      });
    }
  },
);

// POST /api/rsp/applications/:applicationId/resubmit-documents
// Applicant: after HR rejected one or more Step 1 documents, return to review.
// Only rejected slots must be re-uploaded; kept documents stay on file.
router.post(
  '/:applicationId/resubmit-documents',
  rejectInvalidApplicationId,
  requireApplicantProof,
  publicApplicationResubmitLimiter,
  async (req, res) => {
    try {
      await ensureRspApplicationsTables();
      const { applicationId } = req.params;
      const existing = await pool.query(
        `
        SELECT status,
               doc_application_letter_path,
               doc_resume_path,
               doc_tor_path,
               doc_eligibility_trainings_path
        FROM public.recruitment_applications
        WHERE id = $1
        `,
        [applicationId],
      );
      const row = existing.rows[0];
      if (!row) {
        return res.status(404).json({ error: 'Application not found' });
      }
      if (row.status !== 'document_declined') {
        return res.status(409).json({
          error: 'Documents can only be resubmitted after HR has declined them.',
          code: 'RESUBMIT_NOT_ALLOWED',
        });
      }
      const missing = [
        row.doc_application_letter_path,
        row.doc_resume_path,
        row.doc_tor_path,
        row.doc_eligibility_trainings_path,
      ].some((p) => !p || !String(p).trim());
      if (missing) {
        return res.status(400).json({
          error:
            'Re-upload each rejected document before resubmitting. Documents that were not rejected can stay as they are.',
        });
      }
      const result = await pool.query(
        `
        UPDATE public.recruitment_applications
        SET status = 'submitted',
            document_revision_used = TRUE,
            doc_application_letter_reject_reason = NULL,
            doc_resume_reject_reason = NULL,
            doc_tor_reject_reason = NULL,
            doc_eligibility_trainings_reject_reason = NULL,
            updated_at = now()
        WHERE id = $1 AND status = 'document_declined'
        `,
        [applicationId],
      );
      if ((result.rowCount ?? 0) === 0) {
        return res.status(409).json({
          error: 'Documents can only be resubmitted after HR has declined them.',
          code: 'RESUBMIT_NOT_ALLOWED',
        });
      }
      return res.json({ ok: true, status: 'submitted' });
    } catch (err) {
      console.error('[rspApplications POST resubmit-documents]', err);
      return res.status(500).json({
        error: 'Failed to resubmit documents',
        details: err?.message ? String(err.message) : String(err),
      });
    }
  },
);

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

    const outcome = await withRspTransaction(async (client) => {
      const current = await client.query(
        `SELECT final_interview_at, final_interview_passed, email, full_name, applicant_number,
                position_applied_for, step4_gate_required, wes_status, applicants_profile_status,
                selection_lineup_status
         FROM public.recruitment_applications
         WHERE id = $1
         FOR UPDATE`,
        [applicationId],
      );
      if ((current.rowCount ?? 0) === 0) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      if (
        param == null &&
        (current.rows[0].final_interview_passed === true ||
          current.rows[0].final_interview_passed === false)
      ) {
        return {
          rollback: true,
          status: 409,
          body: {
            error:
              'Clear the deliberation result before removing the schedule. The appointment is used on the Turn-Around Time form.',
            code: 'DELIBERATION_SCHEDULE_LOCKED_BY_OUTCOME',
          },
        };
      }
      if (param != null) {
        const missing = preDeliberation.missingPrerequisites(current.rows[0]);
        if (missing.length > 0) {
          return {
            rollback: true,
            status: 409,
            body: {
              error: 'Pre-deliberation requirements are incomplete.',
              code: 'PRE_DELIBERATION_REQUIREMENTS_INCOMPLETE',
              missing,
            },
          };
        }
      }
      const result = await client.query(
        `
        UPDATE public.recruitment_applications
        SET final_interview_at = $1::timestamptz, updated_at = now()
        WHERE id = $2
        RETURNING ${RSP_APPLICATION_ROW_SELECT}
        `,
        [param, applicationId],
      );
      if ((result.rowCount ?? 0) === 0) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      return {
        status: 200,
        body: { ok: true, application: result.rows[0] },
        notice: {
          applicationId,
          eventName: 'Deliberation',
          previousAt: current.rows[0].final_interview_at,
          nextAt: param,
          applicant: current.rows[0],
        },
      };
    });
    if (outcome.notice) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyScheduleNotice(outcome.notice),
      );
    }
    return res.status(outcome.status).json(outcome.body);
  } catch (err) {
    console.error('[rspApplications PUT final-interview]', err);
    return res.status(500).json({
      error: 'Failed to update final interview',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/orientation
// Admin: schedule or clear orientation datetime (after final requirements are approved).
router.put('/:applicationId/orientation', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { orientationAt } = req.body || {};

    let param = null;
    if (orientationAt === null || orientationAt === undefined || orientationAt === '') {
      param = null;
    } else if (typeof orientationAt === 'string') {
      const d = new Date(orientationAt);
      if (Number.isNaN(d.getTime())) {
        return res.status(400).json({
          error: 'orientationAt must be a valid ISO 8601 datetime or null',
        });
      }
      param = d.toISOString();
    } else {
      return res.status(400).json({ error: 'orientationAt must be an ISO string or null' });
    }

    const outcome = await withRspTransaction(async (client) => {
      const check = await client.query(
        `
        SELECT final_requirements_approved, orientation_at, email, full_name,
               applicant_number, position_applied_for
        FROM public.recruitment_applications
        WHERE id = $1
        FOR UPDATE
        `,
        [applicationId],
      );
      if (!check.rows[0]) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      if (check.rows[0].final_requirements_approved !== true) {
        return {
          rollback: true,
          status: 400,
          body: {
            error: 'Final requirements must be approved before scheduling orientation',
          },
        };
      }
      const result = await client.query(
        `
        UPDATE public.recruitment_applications
        SET orientation_at = $1::timestamptz, updated_at = now()
        WHERE id = $2
        RETURNING ${RSP_APPLICATION_ROW_SELECT}
        `,
        [param, applicationId],
      );
      if ((result.rowCount ?? 0) === 0) {
        return { rollback: true, status: 404, body: { error: 'Application not found' } };
      }
      return {
        status: 200,
        body: { ok: true, application: result.rows[0] },
        notice: {
          applicationId,
          eventName: 'Orientation',
          previousAt: check.rows[0].orientation_at,
          nextAt: param,
          applicant: check.rows[0],
        },
      };
    });
    if (outcome.notice) {
      await applicantNotices.safeNotify(() =>
        applicantNotices.notifyScheduleNotice(outcome.notice),
      );
    }
    return res.status(outcome.status).json(outcome.body);
  } catch (err) {
    console.error('[rspApplications PUT orientation]', err);
    return res.status(500).json({
      error: 'Failed to update orientation schedule',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

// PUT /api/rsp/applications/:applicationId/orientation-attendance
// Admin: record orientation attendance (null = pending, true = attended, false = no-show).
router.put('/:applicationId/orientation-attendance', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const body = req.body || {};
    if (!Object.prototype.hasOwnProperty.call(body, 'attended')) {
      return res.status(400).json({
        error: 'attended is required (true, false, or null)',
      });
    }
    const { attended } = body;
    let value = null;
    if (attended === null) {
      value = null;
    } else if (typeof attended === 'boolean') {
      value = attended;
    } else {
      return res.status(400).json({
        error: 'attended must be true, false, or null',
      });
    }

    const check = await pool.query(
      `
      SELECT final_requirements_approved
      FROM public.recruitment_applications
      WHERE id = $1
      `,
      [applicationId],
    );
    if (!check.rows[0]) {
      return res.status(404).json({ error: 'Application not found' });
    }
    if (check.rows[0].final_requirements_approved !== true) {
      return res.status(400).json({
        error: 'Final requirements must be approved before recording orientation attendance',
      });
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET orientation_attended = $1, updated_at = now()
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
    console.error('[rspApplications PUT orientation-attendance]', err);
    return res.status(500).json({
      error: 'Failed to update orientation attendance',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

router.post('/:applicationId/csc-approval', recruitmentStaff, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const raw = req.body && (req.body.status ?? req.body.decision);
    const status = raw == null || String(raw).trim() === ''
      ? 'approved'
      : String(raw).trim();
    const result = await finalHiring.setCscApprovalStatus({
      applicationId: req.params.applicationId,
      actorId: req.user?.id,
      status,
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return finalHiring.sendFinalHiringError(res, err, '[rspApplications POST csc-approval]');
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

    const current = await pool.query(
      `SELECT step5_gate_required, final_interview_passed, final_interview_at,
              final_requirements_approved, hired_user_id, hr_account_setup_done,
              orientation_at, status, doc_medical_certificate_path, doc_drug_test_path,
              doc_nbi_clearance_path
       FROM public.recruitment_applications
       WHERE id = $1`,
      [applicationId],
    );
    if ((current.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    if (finalHiring.deliberationOutcomeRequiresSchedule(current.rows[0], value)) {
      return res.status(409).json({
        error:
          'Schedule deliberation first. The appointment is required before recording pass/fail and is used on the Turn-Around Time form.',
        code: 'DELIBERATION_SCHEDULE_REQUIRED',
      });
    }
    const enableGate = finalHiring.shouldEnableStep5Gate(current.rows[0], value === true);
    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET final_interview_passed = $1,
          updated_at = now(),
          step5_gate_required = CASE WHEN $3::boolean THEN TRUE ELSE step5_gate_required END,
          tat_status = CASE
            WHEN $3::boolean THEN COALESCE(tat_status, 'waiting')
            ELSE tat_status
          END
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [value, applicationId, enableGate],
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

// POST /api/rsp/applications/:applicationId/final-requirements/:kind/reject
// Admin: reject one final-requirement PDF so the applicant must re-upload it.
router.post(
  '/:applicationId/final-requirements/:kind/reject',
  ...protect,
  async (req, res) => {
    try {
      await ensureRspApplicationsTables();
      const { applicationId, kind: kindRaw } = req.params;
      const docKind = parseRspDocKind(kindRaw);
      if (!docKind || !FINAL_REQUIREMENT_KINDS.has(docKind)) {
        return res.status(400).json({
          error:
            'kind must be medical_certificate, drug_test_result, or nbi_clearance',
        });
      }

      const reasonRaw =
        typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
      const reason =
        reasonRaw.slice(0, 500) ||
        'HR requested a new upload for this requirement.';

      const { pathCol, nameCol, rejectReasonCol } =
        RSP_DOC_KIND_COLUMNS[docKind];

      const outcome = await withRspTransaction(async (client) => {
        const check = await client.query(
          `
          SELECT
            id,
            hired_user_id,
            status,
            email,
            full_name,
            applicant_number,
            position_applied_for,
            final_requirements_revision_used,
            doc_medical_certificate_path,
            doc_drug_test_path,
            doc_nbi_clearance_path,
            doc_medical_certificate_reject_reason,
            doc_drug_test_reject_reason,
            doc_nbi_clearance_reject_reason,
            "${pathCol}" AS file_path,
            "${nameCol}" AS file_name
          FROM public.recruitment_applications
          WHERE id = $1
          FOR UPDATE
          `,
          [applicationId],
        );
        if (!check.rows[0]) {
          return { rollback: true, status: 404, body: { error: 'Application not found' } };
        }
        const row = check.rows[0];
        const hired =
          (row.hired_user_id && String(row.hired_user_id).trim() !== '') ||
          String(row.status || '').toLowerCase() === 'registered';
        if (hired) {
          return {
            rollback: true,
            status: 400,
            body: {
              error:
                'Cannot reject final requirements after the applicant is already hired.',
            },
          };
        }
        if (!row.file_path || String(row.file_path).trim() === '') {
          return {
            rollback: true,
            status: 400,
            body: { error: 'No uploaded file to reject for this requirement.' },
          };
        }

        // One revision round: after all files are restored, only approve or permanent fail.
        const revisionUsed = row.final_requirements_revision_used === true;
        const openRevision =
          [
            row.doc_medical_certificate_reject_reason,
            row.doc_drug_test_reject_reason,
            row.doc_nbi_clearance_reject_reason,
          ].some((r) => r != null && String(r).trim() !== '') ||
          [
            row.doc_medical_certificate_path,
            row.doc_drug_test_path,
            row.doc_nbi_clearance_path,
          ].some((p) => p == null || String(p).trim() === '');
        // After a completed revision (flag set + all docs present again), block a new round.
        // Still allow rejecting additional docs while an open revision is in progress.
        if (revisionUsed && !openRevision) {
          return {
            rollback: true,
            status: 409,
            body: {
              error:
                'This applicant already used their one final-requirements revision. Mark approved or Not approved.',
              code: 'FINAL_REQUIREMENTS_REVISION_ALREADY_USED',
            },
          };
        }

        const objectPath = String(row.file_path).trim();
        const displayName = row.file_name || path.basename(objectPath);
        const abs =
          findLocalRspAttachment(UPLOAD_DIR, objectPath, displayName) ||
          resolveLocalRspAttachment(UPLOAD_DIR, objectPath);
        if (abs && fs.existsSync(abs)) {
          try {
            fs.unlinkSync(abs);
          } catch (e) {
            console.warn('[rspApplications reject final-req] unlink', e?.message);
          }
        }

        const result = await client.query(
          `
          UPDATE public.recruitment_applications
          SET "${pathCol}" = NULL,
              "${nameCol}" = NULL,
              "${rejectReasonCol}" = $1,
              final_requirements_approved = FALSE,
              final_requirements_revision_used = TRUE,
              updated_at = now()
          WHERE id = $2
          RETURNING ${RSP_APPLICATION_ROW_SELECT}
          `,
          [reason, applicationId],
        );
        return {
          status: 200,
          body: { ok: true, application: result.rows[0] },
          notice: {
            applicationId,
            documentKind: docKind,
            reason,
            applicant: row,
          },
        };
      });
      if (outcome.notice) {
        await applicantNotices.safeNotify(() =>
          applicantNotices.notifyFinalRequirementReturned(outcome.notice),
        );
      }
      return res.status(outcome.status).json(outcome.body);
    } catch (err) {
      console.error('[rspApplications POST final-requirements reject]', err);
      return res.status(500).json({
        error: 'Failed to reject final requirement',
        details: err?.message ? String(err.message) : String(err),
      });
    }
  },
);

// POST /api/rsp/applications/:applicationId/final-requirements/not-approved
// Admin: permanently reject the application at final requirements (no resubmit / no hire).
router.post(
  '/:applicationId/final-requirements/not-approved',
  ...protect,
  rejectInvalidApplicationId,
  async (req, res) => {
    try {
      await ensureRspApplicationsTables();
      const { applicationId } = req.params;
      const reasonRaw =
        typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
      const reason = reasonRaw.slice(0, 500);

      const outcome = await withRspTransaction(async (client) => {
        const check = await client.query(
          `
          SELECT id, status, email, full_name, applicant_number, position_applied_for,
                 final_interview_passed, final_requirements_approved, hired_user_id
          FROM public.recruitment_applications
          WHERE id = $1
          FOR UPDATE
          `,
          [applicationId],
        );
        if (!check.rows[0]) {
          return {
            rollback: true,
            status: 404,
            body: { error: 'Application not found' },
          };
        }
        const row = check.rows[0];
        const hired =
          (row.hired_user_id && String(row.hired_user_id).trim() !== '') ||
          String(row.status || '').toLowerCase() === 'registered';
        if (hired) {
          return {
            rollback: true,
            status: 400,
            body: {
              error:
                'Cannot reject final requirements after the applicant is already hired.',
            },
          };
        }
        if (row.final_interview_passed !== true) {
          return {
            rollback: true,
            status: 400,
            body: {
              error:
                'Only applicants who passed deliberation can be marked not approved at final requirements.',
            },
          };
        }
        if (String(row.status || '').toLowerCase() === 'failed') {
          const existing = await client.query(
            `SELECT ${RSP_APPLICATION_ROW_SELECT}
             FROM public.recruitment_applications
             WHERE id = $1`,
            [applicationId],
          );
          return {
            status: 200,
            body: {
              ok: true,
              application: existing.rows[0],
              alreadyRejected: true,
            },
          };
        }

        const result = await client.query(
          `
          UPDATE public.recruitment_applications
          SET status = 'failed',
              final_requirements_approved = FALSE,
              orientation_at = NULL,
              orientation_attended = NULL,
              updated_at = now()
          WHERE id = $1
          RETURNING ${RSP_APPLICATION_ROW_SELECT}
          `,
          [applicationId],
        );
        return {
          status: 200,
          body: { ok: true, application: result.rows[0] },
          notice: {
            applicationId,
            applicant: row,
            reason,
          },
        };
      });

      if (outcome.notice) {
        await applicantNotices.safeNotify(() =>
          applicantNotices.notifyFinalRequirementsNotApproved(outcome.notice),
        );
      }
      return res.status(outcome.status).json(outcome.body);
    } catch (err) {
      console.error('[rspApplications POST final-requirements not-approved]', err);
      return res.status(500).json({
        error: 'Failed to mark final requirements not approved',
        details: err?.message ? String(err.message) : String(err),
      });
    }
  },
);

// PUT /api/rsp/applications/:applicationId/final-requirements-approval
// Admin: mark all final requirements (medical, drug test, NBI) as approved.
router.put('/:applicationId/final-requirements-approval', protect, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId } = req.params;
    const { approved } = req.body || {};
    if (typeof approved !== 'boolean') {
      return res.status(400).json({ error: 'approved is required (true or false)' });
    }

    const check = await pool.query(
      `
      SELECT
        doc_medical_certificate_path,
        doc_drug_test_path,
        doc_nbi_clearance_path,
        final_interview_passed,
        status,
        hired_user_id
      FROM public.recruitment_applications
      WHERE id = $1
      `,
      [applicationId],
    );
    if (!check.rows[0]) {
      return res.status(404).json({ error: 'Application not found' });
    }
    const row = check.rows[0];
    const hired =
      (row.hired_user_id && String(row.hired_user_id).trim() !== '') ||
      String(row.status || '').toLowerCase() === 'registered';
    if (hired) {
      return res.status(400).json({
        error: 'Cannot change final requirements after the applicant is hired.',
      });
    }
    if (String(row.status || '').toLowerCase() === 'failed') {
      return res.status(409).json({
        error:
          'This application was marked not approved and cannot be approved.',
        code: 'FINAL_REQUIREMENTS_NOT_APPROVED',
      });
    }
    if (approved === true) {
      const hiringGate = await pool.query(
        `SELECT step5_gate_required, tat_status, csc_approval_status
         FROM public.recruitment_applications
         WHERE id = $1`,
        [applicationId],
      );
      const missing = finalHiring.missingFinalHiringPrerequisites(hiringGate.rows[0]);
      if (missing.length > 0) {
        return res.status(409).json({
          error: 'Final Hiring preparation is incomplete.',
          code: 'FINAL_HIRING_GATE_INCOMPLETE',
          missing,
        });
      }
    }
    if (row.final_interview_passed !== true) {
      return res.status(400).json({
        error: 'Applicant must pass deliberation before final requirements can be approved.',
      });
    }
    if (approved) {
      const missing = [];
      if (!row.doc_medical_certificate_path) missing.push('medical certificate');
      if (!row.doc_drug_test_path) missing.push('drug test result');
      if (!row.doc_nbi_clearance_path) missing.push('NBI clearance');
      if (missing.length > 0) {
        return res.status(400).json({
          error: `Missing required documents: ${missing.join(', ')}.`,
        });
      }
    }

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET final_requirements_approved = $1, updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [approved, applicationId],
    );
    return res.json({ ok: true, application: result.rows[0] });
  } catch (err) {
    console.error('[rspApplications PUT final-requirements-approval]', err);
    return res.status(500).json({
      error: 'Failed to update final requirements approval',
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
    const { userId, loginUsername } = req.body || {};
    if (!userId || typeof userId !== 'string') {
      return res.status(400).json({ error: 'userId is required' });
    }

    const appQ = await pool.query(
      `
      SELECT id, email, final_requirements_approved
      FROM public.recruitment_applications
      WHERE id = $1
      `,
      [applicationId],
    );
    const appRow = appQ.rows[0];
    if (!appRow) return res.status(404).json({ error: 'Application not found' });
    if (appRow.final_requirements_approved !== true) {
      return res.status(400).json({
        error: 'Applicant final requirements must be approved before linking an employee account',
      });
    }

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

    const usernameToStore =
      typeof loginUsername === 'string' && loginUsername.trim()
        ? loginUsername.trim().toLowerCase()
        : userEmail;
    // Never persist plaintext hire passwords for admin clients to read later.
    // Credentials are emailed only via send-credentials (server-generated).

    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET hired_user_id = $1::uuid,
          status = 'registered',
          hr_account_setup_done = TRUE,
          hr_account_setup_linked_sync = TRUE,
          hire_login_username = COALESCE($3, hire_login_username),
          hire_login_password = NULL,
          hire_credentials_email_sent_at = NULL,
          updated_at = now()
      WHERE id = $2
      RETURNING ${RSP_APPLICATION_ROW_SELECT}
      `,
      [userId, applicationId, usernameToStore],
    );
    return res.json({
      ok: true,
      application: redactHireSecrets(result.rows[0]),
    });
  } catch (err) {
    console.error('[rspApplications PUT hired-link]', err);
    return res.status(500).json({
      error: 'Failed to link hired user',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

function generateHireTemporaryPassword(length = 12) {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '!@#$%';
  const all = lower + upper + numbers + symbols;
  const chars = [
    lower[crypto.randomInt(lower.length)],
    upper[crypto.randomInt(upper.length)],
    numbers[crypto.randomInt(numbers.length)],
    symbols[crypto.randomInt(symbols.length)],
  ];
  while (chars.length < length) {
    chars.push(all[crypto.randomInt(all.length)]);
  }
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

// POST /api/rsp/applications/:applicationId/send-credentials
// Admin/HR: creates a new login password and emails it. The password is not returned.
router.post('/:applicationId/send-credentials', recruitmentStaff, async (req, res) => {
  let hiredUserId = null;
  let previousHash = null;
  let passwordHash = null;
  let passwordUpdated = false;
  let credentialsSent = false;
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
    const appQ = await pool.query(
      `
      SELECT full_name, email, hired_user_id, hr_account_setup_done, status
      FROM public.recruitment_applications
      WHERE id = $1
      `,
      [applicationId],
    );
    const row = appQ.rows[0];
    if (!row) {
      return res.status(404).json({ error: 'Application not found' });
    }
    hiredUserId = row.hired_user_id;
    if (!hiredUserId) {
      return res.status(400).json({
        error: 'Create the employee account before sending login credentials',
      });
    }

    const to = String(row.email || '').trim();
    if (!to) {
      return res.status(400).json({ error: 'Applicant has no email on file' });
    }

    const userQ = await pool.query(
      `SELECT id, email, password_hash FROM public.users WHERE id = $1::uuid`,
      [hiredUserId],
    );
    const userRow = userQ.rows[0];
    if (!userRow) {
      return res.status(400).json({
        error: 'The linked employee account no longer exists',
      });
    }

    const username = String(userRow.email || to).trim().toLowerCase();
    const password = generateHireTemporaryPassword();
    passwordHash = await bcrypt.hash(password, 10);
    previousHash = userRow.password_hash || null;

    const changed = await pool.query(
      `UPDATE public.users SET password_hash = $1, auth_version = auth_version + 1,
         updated_at = now() WHERE id = $2::uuid AND password_hash = $3 RETURNING id`,
      [passwordHash, hiredUserId, previousHash],
    );
    if (!changed.rowCount) {
      return res.status(409).json({ error: 'The employee account changed. Refresh before sending credentials again.' });
    }
    passwordUpdated = true;

    const name = String(row.full_name || '').trim() || 'Applicant';
    const accountNote = buildHireCredentialsAccountNote(
      row.hr_account_setup_done === true,
    );
    if (useEmailJs) {
      await sendHireCredentialsEmailJs({
        to,
        applicantName: name,
        username,
        password,
        accountNote,
        loginInstructions: HIRE_LOGIN_INSTRUCTIONS,
      });
    } else {
      await sendSmtpMail({
        to,
        subject: HIRE_CREDENTIALS_EMAIL_SUBJECT,
        text: buildHireCredentialsPlainText({
          applicantName: name,
          username,
          password,
          accountNote,
        }),
      });
    }

    credentialsSent = true;
    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET hire_credentials_email_sent_at = now(),
          hire_login_username = $2,
          hire_login_password = NULL,
          updated_at = now()
      WHERE id = $1
      `,
      [applicationId, username],
    );

    return res.json({
      ok: true,
      message: 'Email sent',
      to,
      via: useEmailJs ? 'emailjs' : 'smtp',
      hire_credentials_email_sent_at: new Date().toISOString(),
    });
  } catch (err) {
    if (!credentialsSent && passwordUpdated && hiredUserId && previousHash) {
      try {
        await pool.query(
          `UPDATE public.users SET password_hash = $1, auth_version = auth_version + 1,
             updated_at = now() WHERE id = $2::uuid AND password_hash = $3`,
          [previousHash, hiredUserId, passwordHash],
        );
      } catch (restoreErr) {
        console.error('[rspApplications POST send-credentials] password restore failed', restoreErr);
      }
    }
    console.error('[rspApplications POST send-credentials]', err);
    const msg = err?.message ? String(err.message) : String(err);
    return res.status(500).json({
      error: credentialsSent ? 'Email sent, but its delivery status could not be saved' : 'Failed to send email',
      details: msg,
    });
  }
});

// POST /api/rsp/applications/:applicationId/send-hire-email
// Admin: sends congratulations + a server-generated password (never returned to admin).
router.post('/:applicationId/send-hire-email', protect, async (req, res) => {
  let hiredUserId = null;
  let previousHash = null;
  let passwordHash = null;
  let passwordUpdated = false;
  let credentialsSent = false;
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

    const appQ = await pool.query(
      `
      SELECT full_name, email, final_interview_passed, final_requirements_approved, hr_account_setup_done,
             hired_user_id, hire_login_username
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
    if (row.final_requirements_approved !== true) {
      return res.status(400).json({
        error: 'Applicant final requirements must be approved before sending hire credentials',
      });
    }
    hiredUserId = row.hired_user_id;
    if (!hiredUserId) {
      return res.status(400).json({
        error: 'Create the employee account before sending login credentials',
      });
    }

    const to = String(row.email || '').trim();
    if (!to) {
      return res.status(400).json({ error: 'Applicant has no email on file' });
    }

    const userQ = await pool.query(
      `SELECT id, email, password_hash FROM public.users WHERE id = $1::uuid`,
      [hiredUserId],
    );
    const userRow = userQ.rows[0];
    if (!userRow) {
      return res.status(400).json({
        error: 'The linked employee account no longer exists',
      });
    }

    // Ignore any client-supplied password — only the applicant email receives it.
    const username =
      String(row.hire_login_username || userRow.email || to).trim().toLowerCase();
    const password = generateHireTemporaryPassword();
    passwordHash = await bcrypt.hash(password, 10);
    previousHash = userRow.password_hash || null;

    const changed = await pool.query(
      `UPDATE public.users SET password_hash = $1, auth_version = auth_version + 1,
         updated_at = now() WHERE id = $2::uuid AND password_hash = $3 RETURNING id`,
      [passwordHash, hiredUserId, previousHash],
    );
    if (!changed.rowCount) {
      return res.status(409).json({
        error: 'The employee account changed. Refresh before sending credentials again.',
      });
    }
    passwordUpdated = true;

    const name = String(row.full_name || '').trim() || 'Applicant';
    const accountNote = buildHireCredentialsAccountNote(
      row.hr_account_setup_done === true,
    );

    if (useEmailJs) {
      await sendHireCredentialsEmailJs({
        to,
        applicantName: name,
        username,
        password,
        accountNote,
        loginInstructions: HIRE_LOGIN_INSTRUCTIONS,
      });
    } else {
      await sendSmtpMail({
        to,
        subject: HIRE_CREDENTIALS_EMAIL_SUBJECT,
        text: buildHireCredentialsPlainText({
          applicantName: name,
          username,
          password,
          accountNote,
        }),
      });
    }

    credentialsSent = true;
    await pool.query(
      `
      UPDATE public.recruitment_applications
      SET hire_credentials_email_sent_at = now(),
          hire_login_username = $2,
          hire_login_password = NULL,
          updated_at = now()
      WHERE id = $1
      `,
      [applicationId, username],
    );

    return res.json({
      ok: true,
      message: 'Email sent',
      to,
      via: useEmailJs ? 'emailjs' : 'smtp',
      hire_credentials_email_sent_at: new Date().toISOString(),
    });
  } catch (err) {
    if (!credentialsSent && passwordUpdated && hiredUserId && previousHash) {
      try {
        await pool.query(
          `UPDATE public.users SET password_hash = $1, auth_version = auth_version + 1,
             updated_at = now() WHERE id = $2::uuid AND password_hash = $3`,
          [previousHash, hiredUserId, passwordHash],
        );
      } catch (restoreErr) {
        console.error('[rspApplications POST send-hire-email] password restore failed', restoreErr);
      }
    }
    console.error('[rspApplications POST send-hire-email]', err);
    const msg = err?.message ? String(err.message) : String(err);
    return res.status(500).json({
      error: credentialsSent
        ? 'Email sent, but its delivery status could not be saved'
        : 'Failed to send email',
      details: msg,
    });
  }
});

// POST /api/rsp/applications/:applicationId/attachment-file
// Public (applicant): save file under uploads/rsp-attachments/{id}/...
// Query updateDb=0 to only store the file and return path (multi-upload helper).
router.post(
  '/:applicationId/attachment-file',
  rejectInvalidApplicationId,
  requireApplicantProof,
  publicApplicationUploadLimiter,
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
      if (!uploadedFileIsPdf(req.file.path)) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Uploaded file is not a valid PDF' });
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
        if (docKind && FINAL_REQUIREMENT_KINDS.has(docKind)) {
          const hiringGate = await pool.query(
            `SELECT step5_gate_required, tat_status, csc_approval_status,
                    status, final_interview_passed, hired_user_id
             FROM public.recruitment_applications
             WHERE id = $1`,
            [applicationId],
          );
          const gateRow = hiringGate.rows[0] || {};
          const hired =
            (gateRow.hired_user_id && String(gateRow.hired_user_id).trim() !== '') ||
            String(gateRow.status || '').toLowerCase() === 'registered';
          if (hired || String(gateRow.status || '').toLowerCase() === 'failed') {
            try {
              fs.unlinkSync(req.file.path);
            } catch (_) {
              /* ignore */
            }
            return res.status(409).json({
              error:
                'Final requirements can no longer be submitted for this application.',
              code: 'FINAL_REQUIREMENTS_CLOSED',
            });
          }
          const missing = finalHiring.missingFinalHiringPrerequisites(gateRow);
          if (missing.length > 0) {
            try {
              fs.unlinkSync(req.file.path);
            } catch (_) {
              /* ignore */
            }
            return res.status(409).json({
              error: 'CSC approval is required before final requirements can be submitted.',
              code: 'FINAL_HIRING_GATE_INCOMPLETE',
              missing,
            });
          }
        }
        if (docKind) {
          const { pathCol, nameCol, rejectReasonCol } =
            RSP_DOC_KIND_COLUMNS[docKind];
          const clearReject = rejectReasonCol
            ? `, "${rejectReasonCol}" = NULL`
            : '';
          await pool.query(
            `
            UPDATE public.recruitment_applications
            SET "${pathCol}" = $1,
                "${nameCol}" = $2
                ${clearReject},
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
        doc_medical_certificate_path = CASE WHEN btrim(COALESCE(doc_medical_certificate_path, '')) = btrim($1::text) THEN NULL ELSE doc_medical_certificate_path END,
        doc_medical_certificate_name = CASE WHEN btrim(COALESCE(doc_medical_certificate_path, '')) = btrim($1::text) THEN NULL ELSE doc_medical_certificate_name END,
        doc_drug_test_path = CASE WHEN btrim(COALESCE(doc_drug_test_path, '')) = btrim($1::text) THEN NULL ELSE doc_drug_test_path END,
        doc_drug_test_name = CASE WHEN btrim(COALESCE(doc_drug_test_path, '')) = btrim($1::text) THEN NULL ELSE doc_drug_test_name END,
        doc_nbi_clearance_path = CASE WHEN btrim(COALESCE(doc_nbi_clearance_path, '')) = btrim($1::text) THEN NULL ELSE doc_nbi_clearance_path END,
        doc_nbi_clearance_name = CASE WHEN btrim(COALESCE(doc_nbi_clearance_path, '')) = btrim($1::text) THEN NULL ELSE doc_nbi_clearance_name END,
        final_requirements_approved = CASE
          WHEN btrim(COALESCE(doc_medical_certificate_path, '')) = btrim($1::text)
            OR btrim(COALESCE(doc_drug_test_path, '')) = btrim($1::text)
            OR btrim(COALESCE(doc_nbi_clearance_path, '')) = btrim($1::text)
          THEN FALSE
          ELSE final_requirements_approved
        END,
        updated_at = now()
      WHERE btrim(COALESCE(attachment_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_application_letter_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_resume_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_tor_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_eligibility_trainings_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_medical_certificate_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_drug_test_path, '')) = btrim($1::text)
         OR btrim(COALESCE(doc_nbi_clearance_path, '')) = btrim($1::text)
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
router.put('/:applicationId/attachment', rejectInvalidApplicationId, requireApplicantProof, async (req, res) => {
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
router.put('/:applicationId/attachment-if-missing', ...protect, async (req, res) => {
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
router.post('/exam-results', requireApplicantProof, publicApplicationExamLimiter, async (req, res) => {
  try {
    await ensureRspApplicationsTables();
    const { applicationId, scorePercent, passed, answersJson } = req.body || {};
    if (!applicationId) return res.status(400).json({ error: 'applicationId is required' });
    if (typeof passed !== 'boolean') return res.status(400).json({ error: 'passed is required (boolean)' });
    if (scorePercent === undefined || scorePercent === null) {
      return res.status(400).json({ error: 'scorePercent is required' });
    }
    const scored = parseScore0to100(scorePercent);
    if (!scored.ok) {
      return res.status(400).json({ error: scored.error, code: scored.code });
    }
    const score = scored.value;

    const gate = await pool.query(
      `SELECT step2_gate_required, required_form_status
       FROM public.recruitment_applications
       WHERE id = $1`,
      [applicationId],
    );
    if ((gate.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application not found' });
    }
    if (issuedForm.assessmentBlocked(gate.rows[0])) {
      return res.status(409).json({
        error: 'HR must approve the assigned form before Assessment.',
        code: 'FORM_APPROVAL_REQUIRED',
      });
    }

    // Pass/fail is based on MCQ overall from the client (General+Math+Gen.info,
    // 20/25). BEI remains gradeable separately and does not gate status.
    const effectivePassed = !!passed;
    const appStatus = effectivePassed ? 'passed' : 'failed';

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

    await preDeliberation.recordAssessmentOutcome(applicationId, appStatus);

    // Return the saved gate and exam state together. The applicant can render
    // Step 4 without depending on a second, separately rate-limited lookup.
    const application = await pool.query(
      `SELECT ${PUBLIC_TRACKING_APPLICATION_SELECT}
       FROM public.recruitment_applications
       WHERE id = $1 AND deleted_at IS NULL`,
      [applicationId],
    );
    if (!application.rows[0]) {
      return res.status(404).json({ error: 'Application not found' });
    }
    return res.json({
      ok: true,
      ...await publicTrackingPayload(application.rows[0], '[rspApplications POST exam-results] applicant token'),
    });
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
      const scored = parseScore0to100(score_percent);
      if (!scored.ok) {
        return res.status(400).json({ error: scored.error, code: scored.code });
      }
      sets.push(`score_percent = $${i++}`);
      params.push(scored.value);
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
      await preDeliberation.recordAssessmentOutcome(
        applicationId,
        passed ? 'passed' : 'failed',
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
// Without ?permanent=1, moves the applicant to the recycle bin.
// ?permanent=1 deletes the row, exam results, and uploaded files.
router.post('/:applicationId/restore', protect, async (req, res) => {
  try {
    const { applicationId } = req.params;
    if (!applicationId) {
      return res.status(400).json({ error: 'applicationId is required' });
    }
    await ensureRspApplicationsTables();
    const result = await pool.query(
      `
      UPDATE public.recruitment_applications
      SET deleted_at = NULL, updated_at = now()
      WHERE id = $1 AND deleted_at IS NOT NULL
      RETURNING id
      `,
      [applicationId],
    );
    if ((result.rowCount ?? 0) === 0) {
      return res.status(404).json({ error: 'Application is not in the recycle bin' });
    }
    return res.json({ ok: true, restored: true });
  } catch (err) {
    console.error('[rspApplications POST restore]', err);
    return res.status(500).json({
      error: 'Failed to restore application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

router.delete('/:applicationId', protect, async (req, res) => {
  try {
    const { applicationId } = req.params;
    const permanent = req.query.permanent === '1' || req.query.permanent === 'true';
    if (!applicationId) {
      return res.status(400).json({ error: 'applicationId is required' });
    }

    await ensureRspApplicationsTables();

    if (!permanent) {
      const recycled = await pool.query(
        `
        UPDATE public.recruitment_applications
        SET deleted_at = now(), updated_at = now()
        WHERE id = $1 AND deleted_at IS NULL
        RETURNING id
        `,
        [applicationId],
      );
      if ((recycled.rowCount ?? 0) === 0) {
        return res.status(404).json({ error: 'Application not found' });
      }
      return res.json({ ok: true, recycled: true });
    }

    // Everything the applicant did (exam results, mayor endorsement request,
    // scheduling, final requirements, uploaded document references) is removed
    // together in one transaction, so a failure never leaves partial data.
    // Scheduling / orientation / final requirements / hire flags live on the
    // application row itself and are removed with it.
    const docCols = Object.values(RSP_DOC_KIND_COLUMNS).map((c) => c.pathCol);
    const outcome = await withRspTransaction(async (client) => {
      const found = await client.query(
        `SELECT id, ${docCols.map((c) => `"${c}"`).join(', ')}
           FROM public.recruitment_applications
          WHERE id = $1
          FOR UPDATE`,
        [applicationId]
      );
      if (!found.rows[0]) return { rollback: true, deleted: 0 };

      await client.query(
        'DELETE FROM public.recruitment_exam_results WHERE application_id = $1',
        [applicationId]
      );

      // Mayor endorsements are independent of RSP. Do not delete them here.
      // CASCADE FK removal is migration M3; until then, avoid explicit mayor deletes.
      // After M3, orphaned legacy application_id values remain as non-authoritative metadata.

      const result = await client.query(
        'DELETE FROM public.recruitment_applications WHERE id = $1',
        [applicationId]
      );
      return {
        deleted: result.rowCount ?? 0,
        row: found.rows[0],
      };
    });

    if (!outcome.deleted) {
      return res.status(404).json({ error: 'Application not found' });
    }

    // Remove uploaded files only after the database delete has committed.
    const appDir = path.join(rspAttachmentsRoot, applicationId);
    if (fs.existsSync(appDir)) {
      try {
        fs.rmSync(appDir, { recursive: true, force: true });
      } catch (err) {
        console.warn('[rspApplications DELETE] local attachments cleanup', err);
      }
    }
    // Files referenced by the row but stored outside the per-application folder.
    for (const col of docCols) {
      const objectPath = String(outcome.row?.[col] || '').trim();
      if (!objectPath) continue;
      try {
        const abs = resolveLocalRspAttachment(UPLOAD_DIR, objectPath);
        if (abs && fs.existsSync(abs)) fs.unlinkSync(abs);
      } catch (err) {
        console.warn('[rspApplications DELETE] file cleanup', err?.message);
      }
    }

    res.json({ ok: true, deleted: outcome.deleted });
  } catch (err) {
    console.error('[rspApplications DELETE]', err);
    res.status(500).json({
      error: 'Failed to delete application',
      details: err?.message ? String(err.message) : String(err),
    });
  }
});

module.exports = router;

