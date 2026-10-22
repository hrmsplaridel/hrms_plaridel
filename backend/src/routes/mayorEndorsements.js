const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const {
  requireMayor,
  requireMayorOfficeStaff,
  requireMayorEndorsementAccess,
  requireAdminOrHr,
} = require('../middleware/rbac');
const {
  insertNotification,
  insertNotificationForUsers,
} = require('../services/notificationService');
const {
  buildApplicantFullName,
  buildReferenceNumber,
  getMayorIsolationCapabilities,
} = require('../utils/mayorEndorsementIsolation');
const {
  normalizeMeetingRequestStatus,
  canStaffSubmitMeetingRequest,
  canMayorDecideMeeting,
  canStaffRecordAttendance,
  canMayorEndorse,
} = require('../services/mayorMeetingWorkflow');
const {
  ensureIsTestColumn,
  fetchDashboardMetrics,
  fetchEndorsementReport,
  officialScopeSql,
} = require('../services/mayorEndorsementStats');
const { manilaDateSql } = require('../utils/mayorEndorsementIsolation');

const router = express.Router();
/** Municipal Mayor — final endorsement decisions. */
const mayorDecisionOnly = [authMiddleware, requireMayor];
/** Mayor's Office Staff — intake and operational processing. */
const staffOpsOnly = [authMiddleware, requireMayorOfficeStaff];
/** Mayor or Staff — shared read access. */
const endorsementAccess = [authMiddleware, requireMayorEndorsementAccess];
/** Seed helper remains admin/HR. */
const seedAccountOnly = [authMiddleware, requireAdminOrHr];

/** Dedupes concurrent schema bootstrap so ADD CONSTRAINT does not race. */
let _ensureMayorTablesPromise = null;

const VALID_PRIORITIES = new Set(['low', 'normal', 'high', 'urgent']);
const VALID_STATUSES = new Set(['pending', 'mayor_approved', 'endorsed', 'rejected']);
const VALID_MEETING_REQUEST_STATUSES = new Set([
  'none',
  'submitted',
  'approved',
  'reschedule_requested',
  'declined',
]);
/** Intake + legacy RA fallback. Includes applicant_full_name only when M1 column exists. */
function applicantNameSql(caps = {}) {
  const parts = [];
  if (caps.hasApplicantFullName) {
    parts.push(`NULLIF(TRIM(mer.applicant_full_name), '')`);
  }
  parts.push(`NULLIF(
    TRIM(
      CONCAT_WS(
        ' ',
        mer.intake_form->>'first_name',
        mer.intake_form->>'middle_name_or_initial',
        mer.intake_form->>'last_name'
      )
    ),
    ''
  )`);
  parts.push('ra.full_name');
  return `COALESCE(${parts.join(',\n  ')})`;
}

/** Safe without M1 columns (intake + optional LEFT JOIN ra). */
const APPLICANT_NAME_SQL = `
COALESCE(
  NULLIF(
    TRIM(
      CONCAT_WS(
        ' ',
        mer.intake_form->>'first_name',
        mer.intake_form->>'middle_name_or_initial',
        mer.intake_form->>'last_name'
      )
    ),
    ''
  ),
  ra.full_name
)`;
/** All intake keys persisted on the form (optional fields may be empty). */
const INTAKE_FORM_FIELDS = [
  'last_name',
  'first_name',
  'middle_name_or_initial',
  'address',
  'course',
  'school_address',
  'position_applying_for',
  'current_work_designation',
  'agency_company',
  'no_of_service',
  'current_work_address',
  'prc_csc_no',
  'rank_and_code',
];

/** Required for Staff intake submit — identity + education only. */
const REQUIRED_INTAKE_FIELDS = [
  'last_name',
  'first_name',
  'address',
  'course',
  'school_address',
];

function normalizePriority(value) {
  const v = String(value || '').trim().toLowerCase();
  return VALID_PRIORITIES.has(v) ? v : 'normal';
}

function normalizeStatus(value, fallback = 'pending') {
  const v = String(value || '').trim().toLowerCase();
  return VALID_STATUSES.has(v) ? v : fallback;
}

function parseDateOnly(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

function parsePositiveInt(value, fallback, max) {
  const n = parseInt(String(value || ''), 10);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(n, max);
}

function buildEndorsementLetter({
  applicantName,
  referenceNumber = null,
  applicationId = null,
  destinationOffice,
  remarks,
  approvalDate,
  mayorName,
}) {
  const approvedDateText = approvalDate
    ? new Date(approvalDate).toLocaleString('en-PH', {
      timeZone: 'Asia/Manila',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
    : '';
  const safeRemarks = (remarks || '').trim();
  const referenceLine = referenceNumber
    ? `Reference No.: ${referenceNumber}`
    : `Legacy Application ID: ${applicationId || 'N/A'}`;
  return [
    'REPUBLIC OF THE PHILIPPINES',
    'MUNICIPALITY OF PLARIDEL',
    '',
    'OFFICE OF THE MUNICIPAL MAYOR',
    '',
    'ENDORSEMENT LETTER',
    '',
    `Applicant: ${applicantName || 'N/A'}`,
    referenceLine,
    `Destination Office: ${destinationOffice || 'N/A'}`,
    `Approval Date: ${approvedDateText || 'N/A'}`,
    '',
    'This is to formally endorse the above-named applicant to the indicated municipal office for appropriate action.',
    '',
    `Remarks / Instructions: ${safeRemarks || 'None provided.'}`,
    '',
    `Approved by: ${mayorName || 'Municipal Mayor'}`,
  ].join('\n');
}

async function logEndorsementActivity(client, {
  requestId,
  applicationId,
  actorId,
  action,
  remarks = null,
  metadata = null,
}) {
  await client.query(
    `INSERT INTO mayor_endorsement_activity_logs
      (request_id, application_id, actor_id, action, remarks, metadata)
     VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::jsonb)`,
    [
      requestId,
      applicationId || null,
      actorId || null,
      action,
      remarks,
      metadata ? JSON.stringify(metadata) : JSON.stringify({}),
    ],
  );

  // Generic audit trail keyed to the Mayor endorsement request (not RSP).
  await client.query(
    `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
     VALUES ($1::uuid, $2, 'mayor_endorsement_request', $3::uuid, $4)`,
    [actorId || null, action, requestId || null, remarks || null],
  );
}

async function notifyActiveMayors(db, payload) {
  const rows = await db.query(
    `SELECT id FROM users WHERE role = 'mayor' AND is_active = true`,
  );
  const ids = rows.rows.map((r) => r.id).filter(Boolean);
  if (!ids.length) return;
  await insertNotificationForUsers(db, ids, {
    ...payload,
    referenceType: 'mayor_endorsement_request',
  });
}

async function notifyMayorOfficeStaff(db, {
  requestId,
  submittedBy = null,
  excludeUserId = null,
  ...payload
}) {
  const rows = await db.query(
    `SELECT id FROM users
     WHERE role = 'mayor_office_staff' AND is_active = true`,
  );
  const ids = new Set(rows.rows.map((r) => r.id).filter(Boolean));
  if (submittedBy) ids.add(submittedBy);
  if (excludeUserId) ids.delete(excludeUserId);
  const list = [...ids];
  if (!list.length) return;
  await insertNotificationForUsers(db, list, {
    ...payload,
    referenceType: 'mayor_endorsement_request',
    referenceId: requestId,
  });
}

const MEETING_FIELD_SELECT = `
  mer.meeting_request_status,
  mer.meeting_proposed_at,
  mer.meeting_purpose,
  mer.meeting_decision,
  mer.meeting_decided_at,
  mer.meeting_decided_by,
  mer.meeting_decision_remarks,
  mer.meeting_reschedule_proposed_at`;

async function ensureMayorEndorsementTables() {
  if (_ensureMayorTablesPromise) return _ensureMayorTablesPromise;

  _ensureMayorTablesPromise = (async () => {
    try {
      await pool.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";');

      // Greenfield bootstrap: no FK to recruitment_applications (hard isolation).
      // Existing DBs keep their schema until explicit M1–M3 migrations are applied.
      await pool.query(`
    CREATE TABLE IF NOT EXISTS public.mayor_endorsement_requests (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      application_id UUID,
      reference_number TEXT,
      applicant_full_name TEXT,
      requested_office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
      requested_office_name TEXT,
      destination_office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
      destination_office_name TEXT,
      priority TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
      intake_form JSONB NOT NULL DEFAULT '{}'::JSONB,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'mayor_approved', 'endorsed', 'rejected')),
      staff_notes TEXT,
      mayor_remarks TEXT,
      rejection_reason TEXT,
      endorsement_letter TEXT,
      submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      approved_at TIMESTAMPTZ,
      approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      office_form_approved_at TIMESTAMPTZ,
      office_form_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      endorsed_at TIMESTAMPTZ,
      rejected_at TIMESTAMPTZ,
      rejected_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      meeting_request_status TEXT NOT NULL DEFAULT 'none',
      meeting_proposed_at TIMESTAMPTZ,
      meeting_purpose TEXT,
      meeting_decision TEXT,
      meeting_decided_at TIMESTAMPTZ,
      meeting_decided_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      meeting_decision_remarks TEXT,
      meeting_reschedule_proposed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);

      await pool.query(`
    CREATE TABLE IF NOT EXISTS public.mayor_endorsement_activity_logs (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      request_id UUID NOT NULL REFERENCES public.mayor_endorsement_requests(id) ON DELETE CASCADE,
      application_id UUID,
      actor_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
      action TEXT NOT NULL,
      remarks TEXT,
      metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);

      // Never recreate a CASCADE FK to recruitment_applications on existing DBs.
      // Decoupling is performed only by migration M3.

      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS intake_form JSONB NOT NULL DEFAULT '{}'::JSONB;
  `);

      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS office_form_approved_at TIMESTAMPTZ;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS office_form_approved_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS submitted_by_name TEXT;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS appointment_at TIMESTAMPTZ;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS appointment_status TEXT NOT NULL DEFAULT 'none';
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS appointment_notes TEXT;
  `);
      await pool.query(`
    ALTER TABLE public.mayor_endorsement_requests
      ADD COLUMN IF NOT EXISTS no_show_count INT NOT NULL DEFAULT 0;
  `);
      await pool.query(`
    UPDATE public.mayor_endorsement_requests mer
       SET submitted_by = mal.actor_id,
           submitted_by_name = COALESCE(mer.submitted_by_name, u.full_name)
      FROM (
        SELECT DISTINCT ON (request_id) request_id, actor_id
        FROM public.mayor_endorsement_activity_logs
        WHERE action = 'request_submitted'
        ORDER BY request_id, created_at ASC
      ) mal
      LEFT JOIN public.users u ON u.id = mal.actor_id
     WHERE mer.submitted_by IS NULL
       AND mal.request_id = mer.id;
  `);

      // Allow two-step endorsement statuses on existing DBs (idempotent).
      await pool.query(`
    DO $$
    DECLARE
      c RECORD;
      hasDesired BOOLEAN;
    BEGIN
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'mayor_endorsement_requests'
          AND con.conname = 'mayor_endorsement_requests_status_check'
          AND pg_get_constraintdef(con.oid) ILIKE '%mayor_approved%'
      ) INTO hasDesired;

      IF hasDesired THEN
        RETURN;
      END IF;

      FOR c IN
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'mayor_endorsement_requests'
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) ILIKE '%status%'
      LOOP
        EXECUTE format(
          'ALTER TABLE public.mayor_endorsement_requests DROP CONSTRAINT IF EXISTS %I',
          c.conname
        );
      END LOOP;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'mayor_endorsement_requests'
          AND con.conname = 'mayor_endorsement_requests_status_check'
      ) THEN
        ALTER TABLE public.mayor_endorsement_requests
          ADD CONSTRAINT mayor_endorsement_requests_status_check
          CHECK (status IN ('pending', 'mayor_approved', 'endorsed', 'rejected'));
      END IF;
    END $$;
  `);

      await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_status
      ON public.mayor_endorsement_requests(status);
    CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_submitted
      ON public.mayor_endorsement_requests(submitted_at DESC);
    CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_requests_priority
      ON public.mayor_endorsement_requests(priority);
    CREATE INDEX IF NOT EXISTS idx_mayor_endorsement_activity_request_created
      ON public.mayor_endorsement_activity_logs(request_id, created_at DESC);
  `);

  // Ensure recruitment status allows endorsement outcomes.
      await pool.query(`
    DO $$
    DECLARE
      c RECORD;
      hasDesired BOOLEAN;
    BEGIN
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'recruitment_applications'
          AND con.conname = 'recruitment_applications_status_check'
          AND pg_get_constraintdef(con.oid) ILIKE '%endorsed%'
      ) INTO hasDesired;

      IF hasDesired THEN
        RETURN;
      END IF;

      FOR c IN
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'recruitment_applications'
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) ILIKE '%status%'
      LOOP
        EXECUTE format(
          'ALTER TABLE public.recruitment_applications DROP CONSTRAINT IF EXISTS %I',
          c.conname
        );
      END LOOP;

      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'recruitment_applications'
          AND con.conname = 'recruitment_applications_status_check'
      ) THEN
        ALTER TABLE public.recruitment_applications
          ADD CONSTRAINT recruitment_applications_status_check
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
          );
      END IF;
    END $$;
  `);

      // Phase 4 — mark known disposable validation rows; never delete.
      await ensureIsTestColumn(pool);
    } catch (err) {
      _ensureMayorTablesPromise = null;
      throw err;
    }
  })();

  return _ensureMayorTablesPromise;
}

function sanitizeIntakeForm(input) {
  const src = input && typeof input === 'object' ? input : {};
  const out = {};
  for (const key of INTAKE_FORM_FIELDS) {
    const v = src[key];
    out[key] = typeof v === 'string' ? v.trim() : '';
  }
  return out;
}

function validateIntakeForm(form) {
  const missing = REQUIRED_INTAKE_FIELDS.filter((k) => !(form[k] || '').trim());
  return { valid: missing.length === 0, missing };
}

async function listEndorsements({
  search = '',
  office = '',
  status = '',
  priority = '',
  meetingRequestStatus = '',
  fromDate = null,
  toDate = null,
  limit = 20,
  offset = 0,
  historyOnly = false,
  includeTest = false,
}) {
  await ensureIsTestColumn(pool);
  const caps = await getMayorIsolationCapabilities(pool);
  const nameSql = applicantNameSql(caps);
  const where = [];
  const params = [];
  let i = 1;

  where.push(officialScopeSql('mer', includeTest));

  if (historyOnly) {
    where.push(`mer.status IN ('endorsed', 'rejected')`);
  }

  if (search && String(search).trim()) {
    const refClause = caps.hasReferenceNumber
      ? `OR COALESCE(mer.reference_number, '') ILIKE $${i}`
      : '';
    where.push(`(
      COALESCE(ra.full_name, '') ILIKE $${i}
      OR COALESCE(ra.id::text, '') ILIKE $${i}
      OR COALESCE(ra.position_applied_for, '') ILIKE $${i}
      OR COALESCE(${nameSql}, '') ILIKE $${i}
      OR COALESCE(mer.submitted_by_name, submitter.full_name, '') ILIKE $${i}
      OR COALESCE(mer.id::text, '') ILIKE $${i}
      ${refClause}
    )`);
    params.push(`%${String(search).trim()}%`);
    i += 1;
  }

  if (office && String(office).trim()) {
    where.push(`(
      COALESCE(mer.requested_office_name, '') ILIKE $${i}
      OR COALESCE(mer.destination_office_name, '') ILIKE $${i}
      OR COALESCE(req_off.name, '') ILIKE $${i}
      OR COALESCE(dest_off.name, '') ILIKE $${i}
    )`);
    params.push(`%${String(office).trim()}%`);
    i += 1;
  }

  const normalizedStatus = normalizeStatus(status, '');
  if (normalizedStatus) {
    // History only contains endorsed/rejected — ignore incompatible request filters.
    if (!historyOnly || normalizedStatus === 'endorsed' || normalizedStatus === 'rejected') {
      where.push(`mer.status = $${i}`);
      params.push(normalizedStatus);
      i += 1;
    }
  }

  const normalizedPriority = normalizePriority(priority);
  if (priority && String(priority).trim()) {
    where.push(`mer.priority = $${i}`);
    params.push(normalizedPriority);
    i += 1;
  }

  const mrsFilter = String(meetingRequestStatus || '').trim().toLowerCase();
  if (mrsFilter && VALID_MEETING_REQUEST_STATUSES.has(mrsFilter) && caps.hasMeetingRequestStatus) {
    where.push(`mer.meeting_request_status = $${i}`);
    params.push(mrsFilter);
    i += 1;
  }

  if (fromDate) {
    if (historyOnly) {
      where.push(`(${manilaDateSql(
        `COALESCE(mer.endorsed_at, mer.office_form_approved_at, mer.approved_at, mer.rejected_at, mer.submitted_at)`,
      )} >= $${i}::date)`);
    } else {
      where.push(`${manilaDateSql('mer.submitted_at')} >= $${i}::date`);
    }
    params.push(fromDate);
    i += 1;
  }
  if (toDate) {
    // toDate is already exclusive next-day from route parsers that add 24h;
    // for Manila date compares, prefer date-only exclusive bound.
    const toBound =
      toDate instanceof Date ? toDate.toISOString().slice(0, 10) : toDate;
    if (historyOnly) {
      where.push(`(${manilaDateSql(
        `COALESCE(mer.endorsed_at, mer.office_form_approved_at, mer.approved_at, mer.rejected_at, mer.submitted_at)`,
      )} < $${i}::date)`);
    } else {
      where.push(`${manilaDateSql('mer.submitted_at')} < $${i}::date`);
    }
    params.push(toBound);
    i += 1;
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const refSelect = caps.hasReferenceNumber ? 'mer.reference_number,' : 'NULL::text AS reference_number,';
  const meetingSelect = caps.hasMeetingRequestStatus
    ? `${MEETING_FIELD_SELECT},`
    : `NULL::text AS meeting_request_status,
      NULL::timestamptz AS meeting_proposed_at,
      NULL::text AS meeting_purpose,
      NULL::text AS meeting_decision,
      NULL::timestamptz AS meeting_decided_at,
      NULL::uuid AS meeting_decided_by,
      NULL::text AS meeting_decision_remarks,
      NULL::timestamptz AS meeting_reschedule_proposed_at,`;
  const countSql = `
    SELECT COUNT(*)::int AS total
    FROM mayor_endorsement_requests mer
    LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
    LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
    LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
    LEFT JOIN users submitter ON submitter.id = mer.submitted_by
    ${whereSql}
  `;
  const rowsSql = `
    SELECT
      mer.id,
      mer.application_id,
      ${refSelect}
      ${nameSql} AS applicant_name,
      COALESCE(mer.intake_form->>'position_applying_for', ra.position_applied_for) AS position_applied_for,
      mer.priority,
      mer.status,
      mer.submitted_at,
      mer.approved_at,
      mer.office_form_approved_at,
      mer.rejected_at,
      mer.submitted_by,
      COALESCE(mer.submitted_by_name, submitter.full_name) AS submitted_by_name,
      mer.requested_office_id,
      COALESCE(req_off.name, mer.requested_office_name) AS requested_office_name,
      mer.destination_office_id,
      COALESCE(dest_off.name, mer.destination_office_name) AS destination_office_name,
      COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name,
      mer.appointment_at,
      mer.appointment_status,
      mer.appointment_notes,
      mer.no_show_count,
      ${meetingSelect}
      mer.staff_notes,
      mer.mayor_remarks,
      mer.rejection_reason
    FROM mayor_endorsement_requests mer
    LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
    LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
    LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
    LEFT JOIN users submitter ON submitter.id = mer.submitted_by
    ${whereSql}
    ORDER BY COALESCE(mer.rejected_at, mer.office_form_approved_at, mer.approved_at, mer.submitted_at) DESC
    LIMIT $${i} OFFSET $${i + 1}
  `;
  const queryParams = params.concat([limit, offset]);

  const [countRes, rowsRes] = await Promise.all([
    pool.query(countSql, params),
    pool.query(rowsSql, queryParams),
  ]);

  return {
    total: countRes.rows[0]?.total || 0,
    rows: rowsRes.rows,
  };
}

// Mayor's Office Staff: submit endorsement intake (Municipal Mayor cannot create intake).
// Pre-M3: may create a temporary RSP stub so NOT NULL application_id inserts succeed.
// Post-M3 (independentIntakeEnabled): never creates stubs or writes RSP statuses.
router.post('/requests', staffOpsOnly, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const {
      applicationId,
      requestedOfficeId = null,
      requestedOfficeName = null,
      priority = 'normal',
      staffNotes = null,
      intakeForm = {},
    } = req.body || {};

    const normalizedPriority = normalizePriority(priority);
    const sanitizedForm = sanitizeIntakeForm(intakeForm);
    const intakeValidation = validateIntakeForm(sanitizedForm);
    if (!intakeValidation.valid) {
      return res.status(400).json({
        error: 'Missing required intake form fields',
        missing_fields: intakeValidation.missing,
      });
    }

    const caps = await getMayorIsolationCapabilities(pool);
    const applicantFullName = buildApplicantFullName(sanitizedForm) || 'Unnamed Applicant';
    let resolvedApplicationId = asUuidOrNull(applicationId);
    let displayName = applicantFullName;

    // Explicit applicationId is legacy-only. Independent intake never requires it.
    if (resolvedApplicationId) {
      const appResult = await pool.query(
        `SELECT id, full_name
         FROM recruitment_applications
         WHERE id = $1::uuid`,
        [resolvedApplicationId],
      );
      const appRow = appResult.rows[0];
      if (!appRow) return res.status(404).json({ error: 'Application not found' });
      displayName = String(appRow.full_name || applicantFullName).trim() || applicantFullName;
    } else if (!caps.independentIntakeEnabled) {
      // Compatibility path until M3: satisfy NOT NULL application_id + CASCADE schema.
      const generatedEmail =
        `mayor-intake-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@local.intake`;
      const created = await pool.query(
        `INSERT INTO recruitment_applications
          (first_name, middle_name, last_name, full_name, email, course, address, position_applied_for, status, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'passed', now(), now())
         RETURNING id, full_name`,
        [
          sanitizedForm.first_name || '',
          sanitizedForm.middle_name_or_initial || '',
          sanitizedForm.last_name || '',
          applicantFullName,
          generatedEmail,
          sanitizedForm.course || null,
          sanitizedForm.address || null,
          sanitizedForm.position_applying_for || null,
        ],
      );
      resolvedApplicationId = created.rows[0].id;
      displayName = created.rows[0].full_name || applicantFullName;
    }

    const submitterRes = await pool.query(
      `SELECT full_name FROM users WHERE id = $1::uuid`,
      [req.user.id],
    );
    const submitterName =
      String(submitterRes.rows[0]?.full_name || req.user?.email || '').trim() || null;

    const insertCols = [
      'requested_office_id',
      'requested_office_name',
      'priority',
      'intake_form',
      'staff_notes',
      'status',
      'submitted_at',
      'submitted_by',
      'submitted_by_name',
      'updated_at',
    ];
    const insertVals = [
      requestedOfficeId,
      requestedOfficeName,
      normalizedPriority,
      JSON.stringify(sanitizedForm),
      staffNotes,
      'pending',
      new Date(),
      req.user.id,
      submitterName,
      new Date(),
    ];

    if (resolvedApplicationId) {
      insertCols.unshift('application_id');
      insertVals.unshift(resolvedApplicationId);
    }
    if (caps.hasApplicantFullName) {
      insertCols.push('applicant_full_name');
      insertVals.push(applicantFullName);
    }
    if (caps.hasMeetingRequestStatus) {
      insertCols.push('meeting_request_status');
      insertVals.push('none');
    }

    let requestRow;
    if (caps.independentIntakeEnabled || !resolvedApplicationId) {
      const placeholders = insertVals.map((_, idx) => {
        const col = insertCols[idx];
        if (col === 'application_id' || col === 'requested_office_id' || col === 'submitted_by') {
          return `$${idx + 1}::uuid`;
        }
        if (col === 'intake_form') return `$${idx + 1}::jsonb`;
        return `$${idx + 1}`;
      });
      const insertResult = await pool.query(
        `INSERT INTO mayor_endorsement_requests (${insertCols.join(', ')})
         VALUES (${placeholders.join(', ')})
         RETURNING *`,
        insertVals,
      );
      requestRow = insertResult.rows[0];
    } else {
      // Pre-M3 unique(application_id) upsert path for legacy/stub-linked rows.
      const upsertResult = await pool.query(
        `INSERT INTO mayor_endorsement_requests
          (application_id, requested_office_id, requested_office_name, priority, intake_form, staff_notes, status, submitted_at, submitted_by, submitted_by_name, updated_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6, 'pending', now(), $7::uuid, $8, now())
         ON CONFLICT (application_id)
         DO UPDATE SET
           requested_office_id = EXCLUDED.requested_office_id,
           requested_office_name = EXCLUDED.requested_office_name,
           priority = EXCLUDED.priority,
           intake_form = EXCLUDED.intake_form,
           staff_notes = EXCLUDED.staff_notes,
           submitted_by = EXCLUDED.submitted_by,
           submitted_by_name = EXCLUDED.submitted_by_name,
           status = 'pending',
           submitted_at = now(),
           updated_at = now()
         RETURNING *`,
        [
          resolvedApplicationId,
          requestedOfficeId,
          requestedOfficeName,
          normalizedPriority,
          JSON.stringify(sanitizedForm),
          staffNotes,
          req.user.id,
          submitterName,
        ],
      );
      requestRow = upsertResult.rows[0];
      if (caps.hasApplicantFullName) {
        await pool.query(
          `UPDATE mayor_endorsement_requests
           SET applicant_full_name = COALESCE(NULLIF(TRIM(applicant_full_name), ''), $2)
           WHERE id = $1::uuid`,
          [requestRow.id, applicantFullName],
        );
      }
    }

    if (caps.hasReferenceNumber && !requestRow.reference_number) {
      const ref = buildReferenceNumber(requestRow.id, requestRow.submitted_at || new Date());
      const updated = await pool.query(
        `UPDATE mayor_endorsement_requests
         SET reference_number = $2
         WHERE id = $1::uuid
         RETURNING *`,
        [requestRow.id, ref],
      );
      requestRow = updated.rows[0] || requestRow;
    }

    // Hard isolation: never modify recruitment_applications.status from Mayor intake.

    await pool.query(
      `INSERT INTO mayor_endorsement_activity_logs
        (request_id, application_id, actor_id, action, remarks, metadata)
       VALUES ($1::uuid, $2::uuid, $3::uuid, 'request_submitted', $4, $5::jsonb)`,
      [
        requestRow.id,
        resolvedApplicationId,
        req.user.id,
        staffNotes,
        JSON.stringify({
          requested_office_id: requestedOfficeId,
          requested_office_name: requestedOfficeName,
          priority: normalizedPriority,
          intake_form: sanitizedForm,
          independent_intake: caps.independentIntakeEnabled,
        }),
      ],
    );

    const reviewerRows = await pool.query(
      `SELECT id
       FROM users
       WHERE role IN ('mayor', 'mayor_office_staff')
         AND is_active = true`,
    );
    const reviewerIds = reviewerRows.rows
      .map((r) => r.id)
      .filter((id) => id && id !== req.user.id);
    if (reviewerIds.length) {
      await insertNotificationForUsers(pool, reviewerIds, {
        category: 'mayor_endorsement',
        type: 'endorsement_request_submitted',
        title: 'New endorsement request submitted',
        body: `${displayName} has a new intake form for review.`,
        referenceType: 'mayor_endorsement_request',
        referenceId: requestRow.id,
        metadata: {
          request_id: requestRow.id,
          priority: normalizedPriority,
          legacy_application_id: resolvedApplicationId,
        },
      });
    }

    return res.status(201).json({ request: requestRow });
  } catch (err) {
    console.error('[mayor endorsements POST /requests]', err);
    return res.status(500).json({ error: 'Failed to submit endorsement request' });
  }
});

// Mayor / Staff dashboard metrics (Asia/Manila; excludes is_test by default).
router.get('/dashboard', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const includeTest =
      req.query.include_test === '1' || req.query.include_test === 'true';
    const metrics = await fetchDashboardMetrics(pool, { includeTest });
    return res.json(metrics);
  } catch (err) {
    console.error('[mayor endorsements GET /dashboard]', err);
    return res.status(500).json({ error: 'Failed to load dashboard data' });
  }
});

// Printable / PDF report data (JSON). Frontend renders PDF.
router.get('/reports', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const report = await fetchEndorsementReport(pool, req.query || {});
    if (report.error) {
      return res.status(report.status || 400).json({ error: report.error });
    }
    return res.json(report);
  } catch (err) {
    console.error('[mayor endorsements GET /reports]', err);
    return res.status(500).json({ error: 'Failed to build endorsement report' });
  }
});

// Search + filter endorsement requests.
router.get('/', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const page = parsePositiveInt(req.query.page, 1, 100000);
    const pageSize = parsePositiveInt(req.query.page_size || req.query.limit, 20, 100);
    const offset = (page - 1) * pageSize;
    const fromDate = parseDateOnly(req.query.from_date);
    const toDateRaw = parseDateOnly(req.query.to_date);
    const toDate = toDateRaw ? new Date(toDateRaw.getTime() + 24 * 60 * 60 * 1000) : null;

    const includeTest =
      req.query.include_test === '1' || req.query.include_test === 'true';
    const result = await listEndorsements({
      search: req.query.search,
      office: req.query.office,
      status: req.query.status,
      priority: req.query.priority,
      meetingRequestStatus:
        req.query.meeting_request_status || req.query.meetingRequestStatus,
      fromDate,
      toDate,
      limit: pageSize,
      offset,
      historyOnly: false,
      includeTest,
    });

    return res.json({
      items: result.rows,
      pagination: {
        page,
        page_size: pageSize,
        total: result.total,
        total_pages: Math.max(1, Math.ceil(result.total / pageSize)),
      },
    });
  } catch (err) {
    console.error('[mayor endorsements GET /]', err);
    return res.status(500).json({ error: 'Failed to list endorsement requests' });
  }
});

// History endpoint for endorsed/rejected records.
router.get('/history', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const page = parsePositiveInt(req.query.page, 1, 100000);
    const pageSize = parsePositiveInt(req.query.page_size || req.query.limit, 20, 100);
    const offset = (page - 1) * pageSize;
    const fromDate = parseDateOnly(req.query.from_date);
    const toDateRaw = parseDateOnly(req.query.to_date);
    const toDate = toDateRaw ? new Date(toDateRaw.getTime() + 24 * 60 * 60 * 1000) : null;

    const includeTest =
      req.query.include_test === '1' || req.query.include_test === 'true';
    const result = await listEndorsements({
      search: req.query.search,
      office: req.query.office,
      status: req.query.status,
      priority: req.query.priority,
      fromDate,
      toDate,
      limit: pageSize,
      offset,
      historyOnly: true,
      includeTest,
    });

    return res.json({
      items: result.rows,
      pagination: {
        page,
        page_size: pageSize,
        total: result.total,
        total_pages: Math.max(1, Math.ceil(result.total / pageSize)),
      },
    });
  } catch (err) {
    console.error('[mayor endorsements GET /history]', err);
    return res.status(500).json({ error: 'Failed to load endorsement history' });
  }
});

router.get('/:id/activity', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const rows = await pool.query(
      `SELECT
         mal.id,
         mal.action,
         mal.remarks,
         mal.metadata,
         mal.created_at,
         mal.actor_id,
         u.full_name AS actor_name
       FROM mayor_endorsement_activity_logs mal
       LEFT JOIN users u ON u.id = mal.actor_id
       WHERE mal.request_id = $1::uuid
       ORDER BY mal.created_at DESC`,
      [id],
    );
    return res.json({ activity: rows.rows });
  } catch (err) {
    console.error('[mayor endorsements GET /:id/activity]', err);
    return res.status(500).json({ error: 'Failed to load activity log' });
  }
});

// Full request details (applicant details, submitted docs, history, previous endorsements).
router.get('/:id', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const requestRes = await pool.query(
      `SELECT
         mer.*,
         req_off.name AS requested_office_label,
         dest_off.name AS destination_office_label,
         COALESCE(mer.submitted_by_name, submitter.full_name) AS submitted_by_label,
         ra.*,
         -- ra.* can overwrite mer.status/id when application_id is null; keep endorsement fields.
         mer.id AS endorsement_request_id,
         mer.status AS endorsement_request_status,
         mer.created_at AS endorsement_created_at,
         mer.updated_at AS endorsement_updated_at
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
       LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
       LEFT JOIN users submitter ON submitter.id = mer.submitted_by
       WHERE mer.id = $1::uuid`,
      [id],
    );
    const row = requestRes.rows[0];
    if (!row) return res.status(404).json({ error: 'Endorsement request not found' });

    const [activityRes, previousRes] = await Promise.all([
      pool.query(
        `SELECT
           mal.id,
           mal.action,
           mal.remarks,
           mal.metadata,
           mal.created_at,
           mal.actor_id,
           u.full_name AS actor_name
         FROM mayor_endorsement_activity_logs mal
         LEFT JOIN users u ON u.id = mal.actor_id
         WHERE mal.request_id = $1::uuid
         ORDER BY mal.created_at DESC`,
        [id],
      ),
      (async () => {
        const intake = row.intake_form || {};
        const nameKey = [
          intake.first_name,
          intake.middle_name_or_initial,
          intake.last_name,
        ]
          .map((s) => String(s || '').trim().toLowerCase())
          .filter(Boolean)
          .join(' ');
        const emailKey = String(row.email || '').trim().toLowerCase();
        return pool.query(
          `SELECT
             mer2.id,
             mer2.application_id,
             mer2.status,
             mer2.submitted_at,
             mer2.approved_at,
             mer2.rejected_at,
             COALESCE(dest_off.name, mer2.destination_office_name, req_off.name, mer2.requested_office_name) AS office_name
           FROM mayor_endorsement_requests mer2
           LEFT JOIN recruitment_applications ra2 ON ra2.id = mer2.application_id
           LEFT JOIN offices req_off ON req_off.id = mer2.requested_office_id
           LEFT JOIN offices dest_off ON dest_off.id = mer2.destination_office_id
           WHERE mer2.id <> $1::uuid
             AND (
               ($2 <> '' AND LOWER(COALESCE(ra2.email, '')) = $2)
               OR (
                 $3 <> ''
                 AND LOWER(TRIM(CONCAT_WS(
                   ' ',
                   mer2.intake_form->>'first_name',
                   mer2.intake_form->>'middle_name_or_initial',
                   mer2.intake_form->>'last_name'
                 ))) = $3
               )
             )
           ORDER BY mer2.submitted_at DESC
           LIMIT 20`,
          [id, emailKey, nameKey],
        );
      })(),
    ]);

    const documents = [
      {
        kind: 'application_letter',
        label: 'Application Letter',
        path: row.doc_application_letter_path,
        file_name: row.doc_application_letter_name,
      },
      {
        kind: 'resume',
        label: 'Resume',
        path: row.doc_resume_path,
        file_name: row.doc_resume_name,
      },
      { kind: 'tor', label: 'Transcript of Records', path: row.doc_tor_path, file_name: row.doc_tor_name },
      {
        kind: 'eligibility_trainings',
        label: 'Eligibility / Trainings',
        path: row.doc_eligibility_trainings_path,
        file_name: row.doc_eligibility_trainings_name,
      },
      {
        kind: 'medical_certificate',
        label: 'Medical Certificate',
        path: row.doc_medical_certificate_path,
        file_name: row.doc_medical_certificate_name,
      },
      {
        kind: 'drug_test_result',
        label: 'Drug Test Result',
        path: row.doc_drug_test_path,
        file_name: row.doc_drug_test_name,
      },
      {
        kind: 'nbi_clearance',
        label: 'NBI Clearance',
        path: row.doc_nbi_clearance_path,
        file_name: row.doc_nbi_clearance_name,
      },
    ].filter((doc) => doc.path);

    const intake = row.intake_form || {};
    const intakeFirst = String(intake.first_name || '').trim();
    const intakeMiddle = String(intake.middle_name_or_initial || '').trim();
    const intakeLast = String(intake.last_name || '').trim();
    const intakeFullName = [intakeFirst, intakeMiddle, intakeLast]
      .filter(Boolean)
      .join(' ')
      .trim();

    return res.json({
      request: {
        id: row.endorsement_request_id || row.id,
        application_id: row.application_id,
        requested_office_id: row.requested_office_id,
        requested_office_name: row.requested_office_name,
        requested_office_label: row.requested_office_label,
        destination_office_id: row.destination_office_id,
        destination_office_name: row.destination_office_name,
        destination_office_label: row.destination_office_label,
        priority: row.priority,
        intake_form: row.intake_form || {},
        status: row.endorsement_request_status || row.status,
        staff_notes: row.staff_notes,
        mayor_remarks: row.mayor_remarks,
        rejection_reason: row.rejection_reason,
        endorsement_letter: row.endorsement_letter,
        submitted_at: row.submitted_at,
        approved_at: row.approved_at,
        approved_by: row.approved_by,
        office_form_approved_at: row.office_form_approved_at,
        office_form_approved_by: row.office_form_approved_by,
        rejected_at: row.rejected_at,
        rejected_by: row.rejected_by,
        submitted_by: row.submitted_by,
        submitted_by_name: row.submitted_by_label || row.submitted_by_name,
        appointment_at: row.appointment_at,
        appointment_status: row.appointment_status || 'none',
        appointment_notes: row.appointment_notes,
        no_show_count: row.no_show_count || 0,
        reference_number: row.reference_number || null,
        meeting_request_status: row.meeting_request_status || 'none',
        meeting_proposed_at: row.meeting_proposed_at || null,
        meeting_purpose: row.meeting_purpose || null,
        meeting_decision: row.meeting_decision || null,
        meeting_decided_at: row.meeting_decided_at || null,
        meeting_decided_by: row.meeting_decided_by || null,
        meeting_decision_remarks: row.meeting_decision_remarks || null,
        meeting_reschedule_proposed_at: row.meeting_reschedule_proposed_at || null,
      },
      applicant: {
        id: row.application_id,
        full_name: intakeFullName || row.full_name,
        first_name: intakeFirst || row.first_name,
        middle_name: intakeMiddle || row.middle_name,
        last_name: intakeLast || row.last_name,
        suffix: row.suffix,
        sex: row.sex,
        course: row.course,
        address: row.address,
        age: row.age,
        civil_status: row.civil_status,
        email: row.email,
        phone: row.phone,
        resume_notes: row.resume_notes,
        position_applied_for: row.position_applied_for,
        status: row.status,
        final_interview_at: row.final_interview_at,
        final_interview_passed: row.final_interview_passed,
        final_requirements_approved: row.final_requirements_approved,
        orientation_at: row.orientation_at,
        orientation_attended: row.orientation_attended,
        created_at: row.created_at,
        updated_at: row.updated_at,
      },
      documents,
      application_history: activityRes.rows,
      previous_endorsements: previousRes.rows,
    });
  } catch (err) {
    console.error('[mayor endorsements GET /:id]', err);
    return res.status(500).json({ error: 'Failed to load endorsement details' });
  }
});

function asUuidOrNull(value) {
  const s = String(value || '').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s)) {
    return null;
  }
  return s;
}

function parseAppointmentAt(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

async function submitMeetingRequestHandler(req, res) {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const proposedAt = parseAppointmentAt(
      req.body?.proposedAt || req.body?.appointmentAt,
    );
    if (!proposedAt) {
      return res.status(400).json({
        error: 'A valid proposed meeting date and time is required.',
      });
    }
    // Purpose / remarks are optional for Staff meeting requests.
    const purposeRaw = String(
      req.body?.purpose || req.body?.remarks || req.body?.notes || '',
    ).trim();
    const purpose = purposeRaw || null;

    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT *
       FROM mayor_endorsement_requests
       WHERE id = $1::uuid
       FOR UPDATE`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    const gate = canStaffSubmitMeetingRequest(row);
    if (!gate.ok) {
      await client.query('ROLLBACK');
      return res.status(gate.status).json({ error: gate.error });
    }

    const previousMrs = normalizeMeetingRequestStatus(row.meeting_request_status);
    const updated = await client.query(
      `UPDATE mayor_endorsement_requests
          SET meeting_request_status = 'submitted',
              meeting_proposed_at = $2,
              meeting_purpose = $3,
              meeting_decision = NULL,
              meeting_decided_at = NULL,
              meeting_decided_by = NULL,
              meeting_decision_remarks = NULL,
              meeting_reschedule_proposed_at = NULL,
              appointment_notes = COALESCE($3, appointment_notes),
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, proposedAt, purpose],
    );

    await logEndorsementActivity(client, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'meeting_request_submitted',
      remarks: purpose,
      metadata: {
        previous_meeting_request_status: previousMrs,
        new_meeting_request_status: 'submitted',
        meeting_proposed_at: proposedAt.toISOString(),
        reference_number: row.reference_number || null,
      },
    });

    await client.query('COMMIT');

    const applicantName =
      buildApplicantFullName(row.intake_form || {}) ||
      row.applicant_full_name ||
      'Applicant';
    await notifyActiveMayors(pool, {
      category: 'mayor_endorsement',
      type: 'meeting_request_submitted',
      title: 'New meeting request',
      body: `${applicantName} — meeting proposed for Mayor review.`,
      referenceId: req.params.id,
      metadata: {
        request_id: req.params.id,
        reference_number: row.reference_number || null,
        meeting_proposed_at: proposedAt.toISOString(),
      },
    });

    return res.json({ ok: true, request: updated.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements meeting-request]', err);
    return res.status(500).json({ error: 'Failed to submit meeting request' });
  } finally {
    client.release();
  }
}

/** Phase 3 primary: Staff submits/revises a meeting request for Mayor approval. */
router.post('/:id/meeting-request', staffOpsOnly, submitMeetingRequestHandler);

/** Compatibility: former direct-schedule now submits a meeting request. */
router.post('/:id/schedule', staffOpsOnly, submitMeetingRequestHandler);

router.post('/:id/meeting/approve', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT * FROM mayor_endorsement_requests WHERE id = $1::uuid FOR UPDATE`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    const gate = canMayorDecideMeeting(row);
    if (!gate.ok) {
      await client.query('ROLLBACK');
      return res.status(gate.status).json({ error: gate.error });
    }
    if (!row.meeting_proposed_at) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Meeting request has no proposed schedule.' });
    }
    const remarks = String(req.body?.remarks || '').trim() || null;
    const decidedAt = new Date();
    const updated = await client.query(
      `UPDATE mayor_endorsement_requests
          SET meeting_request_status = 'approved',
              meeting_decision = 'approved',
              meeting_decided_at = $2,
              meeting_decided_by = $3::uuid,
              meeting_decision_remarks = $4,
              appointment_at = meeting_proposed_at,
              appointment_status = 'scheduled',
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, decidedAt, req.user.id, remarks],
    );
    await logEndorsementActivity(client, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'meeting_approved',
      remarks,
      metadata: {
        previous_meeting_request_status: 'submitted',
        new_meeting_request_status: 'approved',
        appointment_at: updated.rows[0].appointment_at,
        endorsement_status: row.status,
      },
    });
    await client.query('COMMIT');

    await notifyMayorOfficeStaff(pool, {
      requestId: req.params.id,
      submittedBy: row.submitted_by,
      excludeUserId: req.user.id,
      category: 'mayor_endorsement',
      type: 'meeting_approved',
      title: 'Meeting approved by Mayor',
      body: 'The Mayor approved the proposed meeting schedule.',
      metadata: { request_id: req.params.id, reference_number: row.reference_number || null },
    });

    return res.json({
      ok: true,
      request: updated.rows[0],
      message: 'Meeting approved. Endorsement is not yet decided.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/meeting/approve]', err);
    return res.status(500).json({ error: 'Failed to approve meeting' });
  } finally {
    client.release();
  }
});

router.post('/:id/meeting/reschedule', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT * FROM mayor_endorsement_requests WHERE id = $1::uuid FOR UPDATE`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    const gate = canMayorDecideMeeting(row);
    if (!gate.ok) {
      await client.query('ROLLBACK');
      return res.status(gate.status).json({ error: gate.error });
    }
    const remarks = String(req.body?.remarks || req.body?.purpose || '').trim();
    if (!remarks) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'Remarks are required when requesting a reschedule.',
      });
    }
    const alternativeAt = parseAppointmentAt(
      req.body?.alternativeAt || req.body?.proposedAt,
    );
    const decidedAt = new Date();
    const updated = await client.query(
      `UPDATE mayor_endorsement_requests
          SET meeting_request_status = 'reschedule_requested',
              meeting_decision = 'reschedule_requested',
              meeting_decided_at = $2,
              meeting_decided_by = $3::uuid,
              meeting_decision_remarks = $4,
              meeting_reschedule_proposed_at = $5,
              appointment_status = CASE
                WHEN appointment_status = 'scheduled' THEN 'none'
                ELSE appointment_status
              END,
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, decidedAt, req.user.id, remarks, alternativeAt],
    );
    await logEndorsementActivity(client, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'meeting_reschedule_requested',
      remarks,
      metadata: {
        previous_meeting_request_status: 'submitted',
        new_meeting_request_status: 'reschedule_requested',
        alternative_at: alternativeAt ? alternativeAt.toISOString() : null,
        endorsement_status: row.status,
      },
    });
    await client.query('COMMIT');

    await notifyMayorOfficeStaff(pool, {
      requestId: req.params.id,
      submittedBy: row.submitted_by,
      excludeUserId: req.user.id,
      category: 'mayor_endorsement',
      type: 'meeting_reschedule_requested',
      title: 'Mayor requested a meeting reschedule',
      body: remarks,
      metadata: { request_id: req.params.id, reference_number: row.reference_number || null },
    });

    return res.json({
      ok: true,
      request: updated.rows[0],
      message: 'Reschedule requested. Staff must submit a revised meeting request.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/meeting/reschedule]', err);
    return res.status(500).json({ error: 'Failed to request reschedule' });
  } finally {
    client.release();
  }
});

router.post('/:id/meeting/decline', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    await client.query('BEGIN');
    const existing = await client.query(
      `SELECT * FROM mayor_endorsement_requests WHERE id = $1::uuid FOR UPDATE`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    const gate = canMayorDecideMeeting(row);
    if (!gate.ok) {
      await client.query('ROLLBACK');
      return res.status(gate.status).json({ error: gate.error });
    }
    const remarks = String(req.body?.remarks || '').trim() || null;
    const decidedAt = new Date();
    const updated = await client.query(
      `UPDATE mayor_endorsement_requests
          SET meeting_request_status = 'declined',
              meeting_decision = 'declined',
              meeting_decided_at = $2,
              meeting_decided_by = $3::uuid,
              meeting_decision_remarks = $4,
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, decidedAt, req.user.id, remarks],
    );
    await logEndorsementActivity(client, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'meeting_declined',
      remarks,
      metadata: {
        previous_meeting_request_status: 'submitted',
        new_meeting_request_status: 'declined',
        endorsement_status: row.status,
        note: 'Meeting decline does not reject the endorsement',
      },
    });
    await client.query('COMMIT');

    await notifyMayorOfficeStaff(pool, {
      requestId: req.params.id,
      submittedBy: row.submitted_by,
      excludeUserId: req.user.id,
      category: 'mayor_endorsement',
      type: 'meeting_declined',
      title: 'Mayor declined the meeting request',
      body: remarks || 'The Mayor declined the proposed meeting.',
      metadata: { request_id: req.params.id, reference_number: row.reference_number || null },
    });

    return res.json({
      ok: true,
      request: updated.rows[0],
      message: 'Meeting declined. Endorsement request remains open.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/meeting/decline]', err);
    return res.status(500).json({ error: 'Failed to decline meeting' });
  } finally {
    client.release();
  }
});

/** Attendance: Mayor or Staff (sudden/early meetings — Mayor may record immediately after approve). */
router.post('/:id/no-show', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const existing = await pool.query(
      `SELECT * FROM mayor_endorsement_requests WHERE id = $1::uuid`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) return res.status(404).json({ error: 'Endorsement request not found' });
    const gate = canStaffRecordAttendance(row, 'no_show');
    if (!gate.ok) return res.status(gate.status).json({ error: gate.error });
    const notes = String(req.body?.notes || '').trim() || 'Applicant did not appear.';
    const updated = await pool.query(
      `UPDATE mayor_endorsement_requests
          SET appointment_status = 'no_show',
              no_show_count = COALESCE(no_show_count, 0) + 1,
              appointment_notes = $2,
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, notes],
    );
    await logEndorsementActivity(pool, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'appointment_no_show',
      remarks: notes,
      metadata: {
        appointment_at: row.appointment_at,
        meeting_request_status: row.meeting_request_status,
      },
    });
    return res.json({ ok: true, request: updated.rows[0] });
  } catch (err) {
    console.error('[mayor endorsements POST /:id/no-show]', err);
    return res.status(500).json({ error: 'Failed to mark no-show' });
  }
});

router.post('/:id/met', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const existing = await pool.query(
      `SELECT * FROM mayor_endorsement_requests WHERE id = $1::uuid`,
      [req.params.id],
    );
    const row = existing.rows[0];
    if (!row) return res.status(404).json({ error: 'Endorsement request not found' });
    const gate = canStaffRecordAttendance(row, 'met');
    if (!gate.ok) return res.status(gate.status).json({ error: gate.error });
    const notes = String(req.body?.notes || '').trim() || 'Applicant met the Mayor.';
    const updated = await pool.query(
      `UPDATE mayor_endorsement_requests
          SET appointment_status = 'completed',
              appointment_at = COALESCE(appointment_at, now()),
              appointment_notes = $2,
              updated_at = now()
        WHERE id = $1::uuid
        RETURNING *`,
      [req.params.id, notes],
    );
    await logEndorsementActivity(pool, {
      requestId: req.params.id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'appointment_completed',
      remarks: notes,
      metadata: {
        previous_status: row.appointment_status || 'none',
        meeting_request_status: row.meeting_request_status,
      },
    });
    return res.json({ ok: true, request: updated.rows[0] });
  } catch (err) {
    console.error('[mayor endorsements POST /:id/met]', err);
    return res.status(500).json({ error: 'Failed to record meeting with the Mayor' });
  }
});

router.post('/:id/approve', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const {
      destinationOfficeId = null,
      destinationOfficeName = null,
      remarks = null,
    } = req.body || {};

    await client.query('BEGIN');

    const requestRes = await client.query(
      `SELECT
         mer.*,
         ${APPLICANT_NAME_SQL} AS applicant_name,
         ra.id AS app_id
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       WHERE mer.id = $1::uuid
       FOR UPDATE OF mer`,
      [id],
    );
    const requestRow = requestRes.rows[0];
    if (!requestRow) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    if (requestRow.status === 'endorsed') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Request is already endorsed' });
    }
    if (requestRow.status === 'mayor_approved') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'Municipal Mayor already approved. Mayor\'s Office can now approve the endorsement form.',
      });
    }
    if (requestRow.status === 'rejected') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Rejected requests cannot be approved' });
    }
    if (requestRow.status !== 'pending') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Only pending requests can be approved by the Municipal Mayor' });
    }
    if (String(requestRow.appointment_status || '') !== 'completed') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'The applicant must meet the Mayor first. Schedule a meeting if they have not appeared yet.',
      });
    }

    const approvedAt = new Date();
    const destOfficeId = asUuidOrNull(destinationOfficeId);
    const updateRes = await client.query(
      `UPDATE mayor_endorsement_requests
       SET status = 'mayor_approved',
           destination_office_id = $2::uuid,
           destination_office_name = $3,
           mayor_remarks = $4,
           rejection_reason = NULL,
           approved_at = $5,
           approved_by = $6::uuid,
           rejected_at = NULL,
           rejected_by = NULL,
           updated_at = now()
       WHERE id = $1::uuid
       RETURNING *`,
      [id, destOfficeId, destinationOfficeName, remarks, approvedAt, req.user.id],
    );
    const updatedRow = updateRes.rows[0];

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: requestRow.application_id,
      actorId: req.user.id,
      action: 'mayor_approved',
      remarks,
      metadata: {
        destination_office_id: destOfficeId,
        destination_office_name: destinationOfficeName,
        stage: 'municipal_mayor',
      },
    });

    await client.query('COMMIT');

    return res.json({
      request: updatedRow,
      message: 'Approved by Municipal Mayor. Awaiting Mayor\'s Office endorsement form approval.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/approve]', err);
    return res.status(500).json({ error: 'Failed to approve endorsement request' });
  } finally {
    client.release();
  }
});

router.post('/:id/approve-form', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const {
      remarks = null,
      destinationOfficeId: bodyDestinationOfficeId = null,
      destinationOfficeName: bodyDestinationOfficeName = null,
    } = req.body || {};

    await client.query('BEGIN');

    const requestRes = await client.query(
      `SELECT
         mer.*,
         ${APPLICANT_NAME_SQL} AS applicant_name,
         ra.id AS app_id,
         COALESCE(u.full_name, 'Municipal Mayor') AS mayor_name
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       LEFT JOIN users u ON u.id = mer.approved_by
       WHERE mer.id = $1::uuid
       FOR UPDATE OF mer`,
      [id],
    );
    const requestRow = requestRes.rows[0];
    if (!requestRow) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    if (requestRow.status === 'endorsed') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Endorsement form is already approved' });
    }
    if (requestRow.status !== 'mayor_approved') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'Endorsement form can only be approved after the Municipal Mayor has approved the request',
      });
    }

    const nextDestinationOfficeId = asUuidOrNull(
      bodyDestinationOfficeId || requestRow.destination_office_id,
    );
    const nextDestinationOfficeName = String(
      bodyDestinationOfficeName ||
        requestRow.destination_office_name ||
        requestRow.requested_office_name ||
        '',
    ).trim();
    if (!nextDestinationOfficeName) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'Destination office is required before Mayor\'s Office form approval',
      });
    }

    const officeApprovedAt = new Date();
    const officeRemarks = String(remarks || '').trim() || requestRow.mayor_remarks;
    const letter = buildEndorsementLetter({
      applicantName: requestRow.applicant_name,
      referenceNumber: requestRow.reference_number || null,
      applicationId: requestRow.app_id || requestRow.application_id,
      destinationOffice: nextDestinationOfficeName,
      remarks: officeRemarks,
      approvalDate: officeApprovedAt,
      mayorName: requestRow.mayor_name,
    });

    const isoCaps = await getMayorIsolationCapabilities(client);
    const endorsedAtSql = isoCaps.hasEndorsedAt ? ',\n           endorsed_at = $5' : '';
    const updateRes = await client.query(
      `UPDATE mayor_endorsement_requests
       SET status = 'endorsed',
           destination_office_id = $2::uuid,
           destination_office_name = $3,
           mayor_remarks = COALESCE($4, mayor_remarks),
           office_form_approved_at = $5,
           office_form_approved_by = $6::uuid,
           endorsement_letter = $7
           ${endorsedAtSql}
           , updated_at = now()
       WHERE id = $1::uuid
       RETURNING *`,
      [
        id,
        nextDestinationOfficeId,
        nextDestinationOfficeName,
        remarks,
        officeApprovedAt,
        req.user.id,
        letter,
      ],
    );
    const updatedRow = updateRes.rows[0];

    // Hard isolation: do not write recruitment_applications.status.

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: requestRow.application_id,
      actorId: req.user.id,
      action: 'office_form_approved',
      remarks: officeRemarks,
      metadata: {
        stage: 'mayors_office',
        previous_status: 'mayor_approved',
        destination_office_id: nextDestinationOfficeId,
        destination_office_name: nextDestinationOfficeName,
      },
    });

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: requestRow.application_id,
      actorId: req.user.id,
      action: 'endorsement_letter_generated',
      remarks: 'Endorsement letter generated after Mayor\'s Office form approval.',
      metadata: null,
    });

    await client.query('COMMIT');

    const destinationOfficeId = nextDestinationOfficeId;
    if (destinationOfficeId) {
      const officeUsersRes = await pool.query(
        `SELECT id
         FROM users
         WHERE office_id = $1::uuid
           AND is_active = true
           AND role <> 'mayor'`,
        [destinationOfficeId],
      );
      const officeUserIds = officeUsersRes.rows.map((r) => r.id);
      if (officeUserIds.length) {
        await insertNotificationForUsers(pool, officeUserIds, {
          category: 'mayor_endorsement',
          type: 'endorsement_approved_for_office',
          title: 'New endorsed applicant received',
          body: `${requestRow.applicant_name} has been endorsed to your office.`,
          referenceType: 'mayor_endorsement_request',
          referenceId: id,
          metadata: {
            request_id: id,
            destination_office_id: destinationOfficeId,
            destination_office_name: nextDestinationOfficeName,
            legacy_application_id: requestRow.application_id || null,
          },
        });
      }
    }

    return res.json({
      request: updatedRow,
      letter,
      message: 'Endorsement form approved by Mayor\'s Office successfully.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/approve-form]', err);
    return res.status(500).json({
      error: 'Failed to approve endorsement form',
      details: err?.message ?? String(err),
    });
  } finally {
    client.release();
  }
});

/**
 * Phase 3 single final decision for new requests: pending + attended → endorsed.
 * Also accepts legacy mayor_approved rows (skips separate approve-form).
 */
router.post('/:id/endorse', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const {
      destinationOfficeId = null,
      destinationOfficeName = null,
      remarks = null,
    } = req.body || {};

    await client.query('BEGIN');
    const requestRes = await client.query(
      `SELECT
         mer.*,
         ${APPLICANT_NAME_SQL} AS applicant_name,
         ra.id AS app_id,
         COALESCE(u.full_name, 'Municipal Mayor') AS acting_mayor_name
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       LEFT JOIN users u ON u.id = $2::uuid
       WHERE mer.id = $1::uuid
       FOR UPDATE OF mer`,
      [id, req.user.id],
    );
    const requestRow = requestRes.rows[0];
    if (!requestRow) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    const gate = canMayorEndorse(requestRow);
    if (!gate.ok) {
      await client.query('ROLLBACK');
      return res.status(gate.status).json({ error: gate.error });
    }

    const nextDestinationOfficeId = asUuidOrNull(
      destinationOfficeId || requestRow.destination_office_id,
    );
    const nextDestinationOfficeName = String(
      destinationOfficeName ||
        requestRow.destination_office_name ||
        requestRow.requested_office_name ||
        '',
    ).trim();
    if (!nextDestinationOfficeName) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: 'Destination office is required before endorsement',
      });
    }

    const endorsedAt = new Date();
    const officeRemarks = String(remarks || '').trim() || requestRow.mayor_remarks;
    const letter = buildEndorsementLetter({
      applicantName: requestRow.applicant_name,
      referenceNumber: requestRow.reference_number || null,
      applicationId: requestRow.app_id || requestRow.application_id,
      destinationOffice: nextDestinationOfficeName,
      remarks: officeRemarks,
      approvalDate: endorsedAt,
      mayorName: requestRow.acting_mayor_name,
    });

    const isoCaps = await getMayorIsolationCapabilities(client);
    const endorsedAtSql = isoCaps.hasEndorsedAt ? ',\n           endorsed_at = $5' : '';
    const updateRes = await client.query(
      `UPDATE mayor_endorsement_requests
       SET status = 'endorsed',
           destination_office_id = $2::uuid,
           destination_office_name = $3,
           mayor_remarks = COALESCE($4, mayor_remarks),
           rejection_reason = NULL,
           approved_at = COALESCE(approved_at, $5),
           approved_by = COALESCE(approved_by, $6::uuid),
           office_form_approved_at = COALESCE(office_form_approved_at, $5),
           office_form_approved_by = COALESCE(office_form_approved_by, $6::uuid),
           endorsement_letter = COALESCE(NULLIF(TRIM(endorsement_letter), ''), $7),
           rejected_at = NULL,
           rejected_by = NULL
           ${endorsedAtSql}
           , updated_at = now()
       WHERE id = $1::uuid
       RETURNING *`,
      [
        id,
        nextDestinationOfficeId,
        nextDestinationOfficeName,
        remarks,
        endorsedAt,
        req.user.id,
        letter,
      ],
    );
    const updatedRow = updateRes.rows[0];

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: requestRow.application_id,
      actorId: req.user.id,
      action: 'endorsed',
      remarks: officeRemarks,
      metadata: {
        previous_status: requestRow.status,
        new_status: 'endorsed',
        destination_office_id: nextDestinationOfficeId,
        destination_office_name: nextDestinationOfficeName,
        legacy_mayor_approved: Boolean(gate.legacyMayorApproved),
      },
    });

    if (!String(requestRow.endorsement_letter || '').trim()) {
      await logEndorsementActivity(client, {
        requestId: id,
        applicationId: requestRow.application_id,
        actorId: req.user.id,
        action: 'endorsement_letter_generated',
        remarks: 'Endorsement letter generated on Mayor final endorse.',
        metadata: null,
      });
    }

    await client.query('COMMIT');

    await notifyMayorOfficeStaff(pool, {
      requestId: id,
      submittedBy: requestRow.submitted_by,
      excludeUserId: req.user.id,
      category: 'mayor_endorsement',
      type: 'endorsement_endorsed',
      title: 'Applicant endorsed by Mayor',
      body: `${requestRow.applicant_name} was endorsed.`,
      metadata: {
        request_id: id,
        reference_number: requestRow.reference_number || null,
      },
    });

    if (nextDestinationOfficeId) {
      const officeUsersRes = await pool.query(
        `SELECT id
         FROM users
         WHERE office_id = $1::uuid
           AND is_active = true
           AND role <> 'mayor'`,
        [nextDestinationOfficeId],
      );
      const officeUserIds = officeUsersRes.rows.map((r) => r.id);
      if (officeUserIds.length) {
        await insertNotificationForUsers(pool, officeUserIds, {
          category: 'mayor_endorsement',
          type: 'endorsement_approved_for_office',
          title: 'New endorsed applicant received',
          body: `${requestRow.applicant_name} has been endorsed to your office.`,
          referenceType: 'mayor_endorsement_request',
          referenceId: id,
          metadata: {
            request_id: id,
            destination_office_id: nextDestinationOfficeId,
            destination_office_name: nextDestinationOfficeName,
          },
        });
      }
    }

    return res.json({
      request: updatedRow,
      letter: updatedRow.endorsement_letter || letter,
      message: 'Endorsed by Municipal Mayor.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/endorse]', err);
    return res.status(500).json({ error: 'Failed to endorse request' });
  } finally {
    client.release();
  }
});

router.post('/:id/reject', mayorDecisionOnly, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const { reason } = req.body || {};
    const rejectionReason = String(reason || '').trim() || null;

    await client.query('BEGIN');
    const requestRes = await client.query(
      `SELECT
         mer.*,
         ${APPLICANT_NAME_SQL} AS applicant_name
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       WHERE mer.id = $1::uuid
       FOR UPDATE OF mer`,
      [id],
    );
    const requestRow = requestRes.rows[0];
    if (!requestRow) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    if (requestRow.status === 'rejected') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Request is already rejected' });
    }
    if (requestRow.status === 'endorsed') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Fully endorsed requests cannot be rejected' });
    }
    if (
      requestRow.status === 'pending' &&
      String(requestRow.appointment_status || '') !== 'completed'
    ) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'The applicant must meet the Mayor first. Schedule a meeting if they have not appeared yet.',
      });
    }

    const updateRes = await client.query(
      `UPDATE mayor_endorsement_requests
       SET status = 'rejected',
           rejection_reason = $2,
           mayor_remarks = NULL,
           approved_at = NULL,
           approved_by = NULL,
           office_form_approved_at = NULL,
           office_form_approved_by = NULL,
           rejected_at = now(),
           rejected_by = $3::uuid,
           updated_at = now()
       WHERE id = $1::uuid
       RETURNING *`,
      [id, rejectionReason, req.user.id],
    );
    const updatedRow = updateRes.rows[0];

    // Hard isolation: do not write recruitment_applications.status.

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: requestRow.application_id,
      actorId: req.user.id,
      action: 'endorsement_rejected',
      remarks: rejectionReason,
      metadata: {
        previous_status: requestRow.status,
        new_status: 'rejected',
      },
    });

    await client.query('COMMIT');

    await notifyMayorOfficeStaff(pool, {
      requestId: id,
      submittedBy: requestRow.submitted_by,
      excludeUserId: req.user.id,
      category: 'mayor_endorsement',
      type: 'endorsement_rejected',
      title: 'Endorsement rejected by Mayor',
      body: rejectionReason
        ? `${requestRow.applicant_name}: ${rejectionReason}`
        : `${requestRow.applicant_name}: Rejected by Municipal Mayor.`,
      metadata: {
        request_id: id,
        reference_number: requestRow.reference_number || null,
      },
    });

    return res.json({
      request: updatedRow,
      message: 'Endorsement request rejected.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/reject]', err);
    return res.status(500).json({ error: 'Failed to reject endorsement request' });
  } finally {
    client.release();
  }
});

router.post('/:id/generate-letter', endorsementAccess, async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    await client.query('BEGIN');

    const requestRes = await client.query(
      `SELECT
         mer.*,
         ${APPLICANT_NAME_SQL} AS applicant_name,
         COALESCE(dest_off.name, mer.destination_office_name, req_off.name, mer.requested_office_name) AS office_name
       FROM mayor_endorsement_requests mer
       LEFT JOIN recruitment_applications ra ON ra.id = mer.application_id
       LEFT JOIN offices req_off ON req_off.id = mer.requested_office_id
       LEFT JOIN offices dest_off ON dest_off.id = mer.destination_office_id
       WHERE mer.id = $1::uuid
       FOR UPDATE OF mer`,
      [id],
    );
    const row = requestRes.rows[0];
    if (!row) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Endorsement request not found' });
    }
    if (row.status !== 'endorsed') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Only approved endorsements can generate letters' });
    }

    const mayorRes = await client.query(
      `SELECT full_name FROM users WHERE id = $1::uuid`,
      [req.user.id],
    );
    const mayorName = mayorRes.rows[0]?.full_name || 'Municipal Mayor';
    const letter = buildEndorsementLetter({
      applicantName: row.applicant_name,
      referenceNumber: row.reference_number || null,
      applicationId: row.application_id,
      destinationOffice: row.office_name,
      remarks: row.mayor_remarks,
      approvalDate: row.approved_at || new Date(),
      mayorName,
    });

    await client.query(
      `UPDATE mayor_endorsement_requests
       SET endorsement_letter = $2,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, letter],
    );

    await logEndorsementActivity(client, {
      requestId: id,
      applicationId: row.application_id,
      actorId: req.user.id,
      action: 'endorsement_letter_generated',
      remarks: 'Letter generated manually.',
      metadata: null,
    });

    await client.query('COMMIT');
    return res.json({ letter });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[mayor endorsements POST /:id/generate-letter]', err);
    return res.status(500).json({ error: 'Failed to generate endorsement letter' });
  } finally {
    client.release();
  }
});

router.get('/:id/letter', endorsementAccess, async (req, res) => {
  try {
    await ensureMayorEndorsementTables();
    const { id } = req.params;
    const rowRes = await pool.query(
      `SELECT endorsement_letter, status
       FROM mayor_endorsement_requests
       WHERE id = $1::uuid`,
      [id],
    );
    const row = rowRes.rows[0];
    if (!row) return res.status(404).json({ error: 'Endorsement request not found' });
    if (row.status !== 'endorsed') {
      return res.status(400).json({ error: 'Letter is only available for approved endorsements' });
    }
    return res.json({ letter: row.endorsement_letter || '' });
  } catch (err) {
    console.error('[mayor endorsements GET /:id/letter]', err);
    return res.status(500).json({ error: 'Failed to fetch endorsement letter' });
  }
});

// Convenience seed endpoint (admin/hr) to create mayor account if missing.
router.post('/seed-account', seedAccountOnly, async (_req, res) => {
  try {
    await pool.query(
      `INSERT INTO users (email, password_hash, role, full_name, is_active)
       VALUES ($1, $2, 'mayor', $3, true)
       ON CONFLICT (email) DO UPDATE
       SET role = 'mayor',
           full_name = EXCLUDED.full_name,
           password_hash = EXCLUDED.password_hash,
           is_active = true,
           updated_at = now()`,
      [
        'mayorsoffice@test.com',
        '$2b$10$uhPv2oXZLwC9WJ7hXjg3NOLTnYrjyWextH30e9CoR/z3JovGmHeyy',
        'Mayor\'s Office',
      ],
    );
    return res.json({ ok: true, email: 'mayorsoffice@test.com' });
  } catch (err) {
    console.error('[mayor endorsements POST /seed-account]', err);
    return res.status(500).json({ error: 'Failed to seed mayor account' });
  }
});

module.exports = router;
