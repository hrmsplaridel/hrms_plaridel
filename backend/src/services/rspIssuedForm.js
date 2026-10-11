const { pool } = require('../config/db');
const policy = require('./rspIssuedFormPolicy');
const { revisionIsNew } = require('./rspApplicantNotices');

const ISSUED_FORM_MIGRATION = 'backend/scripts/migrations/20261006_rsp_issued_form_gate.sql';
let issuedFormSchemaReady = false;

class IssuedFormError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const ASSIGNMENT_SQL = `
  id, status, full_name, position_applied_for, course,
  step2_gate_required, required_form_type, required_form_status,
  required_form_entry_id, required_form_assigned_by, required_form_assigned_at,
  required_form_submitted_at, required_form_reviewed_by, required_form_reviewed_at,
  required_form_review_comment
`;

async function assertIssuedFormSchema() {
  if (issuedFormSchemaReady) return;
  const result = await pool.query(`
    SELECT
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'recruitment_applications'
          AND column_name = 'step2_gate_required'
      ) AS gate_column,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'bi_form_entries'
          AND column_name = 'application_id'
      ) AS bi_link,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ojt_work_immersion_evaluation_entries'
          AND column_name = 'application_id'
      ) AS ojt_link,
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'uq_bi_form_entries_application'
      ) AS bi_index,
      EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'uq_ojt_entries_application'
      ) AS ojt_index
  `);
  const row = result.rows[0] || {};
  if (!row.gate_column || !row.bi_link || !row.ojt_link || !row.bi_index || !row.ojt_index) {
    throw new IssuedFormError(
      503,
      'ISSUED_FORM_SCHEMA_MISSING',
      `HR-issued form schema is not installed. Apply ${ISSUED_FORM_MIGRATION}`,
    );
  }
  issuedFormSchemaReady = true;
}

function publicAssignment(row) {
  return {
    applicationId: row.id,
    step2GateRequired: row.step2_gate_required === true,
    formType: row.required_form_type,
    status: row.required_form_status,
    entryId: row.required_form_entry_id,
    assignedAt: row.required_form_assigned_at,
    submittedAt: row.required_form_submitted_at,
    reviewedAt: row.required_form_reviewed_at,
    reviewComment: row.required_form_review_comment,
    assessmentUnlocked: !policy.assessmentBlocked(row),
  };
}

async function loadLocked(client, applicationId) {
  const result = await client.query(
    `SELECT ${ASSIGNMENT_SQL}
     FROM public.recruitment_applications
     WHERE id = $1
     FOR UPDATE`,
    [applicationId],
  );
  if (!result.rows[0]) {
    throw new IssuedFormError(404, 'NOT_FOUND', 'Application not found');
  }
  return result.rows[0];
}

function assertGatedDocumentApproved(row) {
  if (row.step2_gate_required !== true) {
    throw new IssuedFormError(
      409,
      'FORM_GATE_NOT_REQUIRED',
      'This application does not use the HR-issued form step.',
    );
  }
  if (row.status !== 'document_approved') {
    throw new IssuedFormError(
      409,
      'DOCUMENTS_NOT_APPROVED',
      'Initial documents must be approved before a form can be assigned.',
    );
  }
}

async function appendLog(client, applicationId, event) {
  await client.query(
    `UPDATE public.recruitment_applications
     SET required_form_review_log = COALESCE(required_form_review_log, '[]'::jsonb) || $2::jsonb,
         updated_at = now()
     WHERE id = $1`,
    [applicationId, JSON.stringify([event])],
  );
}

async function unlinkEntry(client, formType, entryId) {
  if (!entryId) return;
  const table =
    formType === 'ojt'
      ? 'public.ojt_work_immersion_evaluation_entries'
      : 'public.bi_form_entries';
  await client.query(
    `UPDATE ${table} SET application_id = NULL, updated_at = now() WHERE id = $1`,
    [entryId],
  );
}

async function insertBi(client, app) {
  const name = String(app.full_name || 'Applicant').trim() || 'Applicant';
  const result = await client.query(
    `INSERT INTO public.bi_form_entries (
       applicant_name, position_applied_for, respondent_name, respondent_relationship,
       functional_areas, application_id, created_at, updated_at
     ) VALUES ($1, $2, $1, 'supervisor', '[]'::jsonb, $3, now(), now())
     RETURNING *`,
    [name, app.position_applied_for, app.id],
  );
  return result.rows[0];
}

async function insertOjt(client, app) {
  const name = String(app.full_name || '').trim();
  const school = app.course ? String(app.course).trim() : null;
  const result = await client.query(
    `INSERT INTO public.ojt_work_immersion_evaluation_entries (
       ojt_immersion, school, application_id, created_at, updated_at
     ) VALUES ($1, $2, $3, now(), now())
     RETURNING *`,
    [name || null, school || null, app.id],
  );
  return result.rows[0];
}

async function loadEntry(formType, entryId) {
  if (!entryId || (formType !== 'bi' && formType !== 'ojt')) return null;
  const table =
    formType === 'ojt'
      ? 'public.ojt_work_immersion_evaluation_entries'
      : 'public.bi_form_entries';
  const result = await pool.query(`SELECT * FROM ${table} WHERE id = $1`, [entryId]);
  return result.rows[0] || null;
}

async function assignRequiredForm({ applicationId, formType, actorId }) {
  if (!policy.isFormType(formType)) {
    throw new IssuedFormError(400, 'INVALID_FORM_TYPE', 'Choose Background Investigation or OJT / Work Immersion Evaluation.');
  }
  await assertIssuedFormSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const app = await loadLocked(client, applicationId);
    assertGatedDocumentApproved(app);

    if (
      app.required_form_type === formType &&
      app.required_form_entry_id &&
      app.required_form_status &&
      app.required_form_status !== 'waiting_for_hr_form'
    ) {
      await client.query('COMMIT');
      const entry = await loadEntry(formType, app.required_form_entry_id);
      return { assignment: publicAssignment(app), entry, created: false, applicantNotice: false };
    }

    if (!policy.canReassign(app.required_form_status)) {
      throw new IssuedFormError(
        409,
        'FORM_ALREADY_SUBMITTED',
        'This form was already submitted. Approve it or request a revision instead of assigning a different form.',
      );
    }

    if (app.required_form_entry_id && app.required_form_type && app.required_form_type !== formType) {
      await unlinkEntry(client, app.required_form_type, app.required_form_entry_id);
    }

    let entryId = app.required_form_entry_id;
    let entry = null;
    if (app.required_form_type === formType && entryId) {
      entry = await loadEntry(formType, entryId);
    } else {
      entry = formType === 'ojt' ? await insertOjt(client, app) : await insertBi(client, app);
      entryId = entry.id;
    }

    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET required_form_type = $2,
           required_form_status = 'assigned',
           required_form_entry_id = $3,
           required_form_assigned_by = $4,
           required_form_assigned_at = now(),
           required_form_submitted_at = NULL,
           required_form_reviewed_by = NULL,
           required_form_reviewed_at = NULL,
           required_form_review_comment = NULL,
           updated_at = now()
       WHERE id = $1
       RETURNING ${ASSIGNMENT_SQL}`,
      [applicationId, formType, entryId, actorId || null],
    );
    await appendLog(client, applicationId, {
      at: new Date().toISOString(),
      action: 'assigned',
      formType,
      by: actorId || null,
    });
    await client.query('COMMIT');
    return {
      assignment: publicAssignment(updated.rows[0]),
      entry,
      created: true,
      applicantNotice: true,
    };
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

function biPayload(body) {
  const source = body && typeof body === 'object' ? body : {};
  const ratings = {};
  for (let i = 1; i <= 9; i += 1) {
    const raw = source[`rating_${i}`];
    if (raw == null || raw === '') {
      ratings[`rating_${i}`] = null;
    } else {
      const n = Number(raw);
      ratings[`rating_${i}`] = Number.isInteger(n) ? n : null;
    }
  }
  const relationship = ['supervisor', 'peer', 'subordinate'].includes(source.respondent_relationship)
    ? source.respondent_relationship
    : 'supervisor';
  const areas = Array.isArray(source.functional_areas)
    ? source.functional_areas.map((item) => String(item))
    : [];
  return {
    applicant_name: trimOrNull(source.applicant_name) || '',
    applicant_department: trimOrNull(source.applicant_department),
    applicant_position: trimOrNull(source.applicant_position),
    position_applied_for: trimOrNull(source.position_applied_for),
    respondent_name: trimOrNull(source.respondent_name) || '',
    respondent_position: trimOrNull(source.respondent_position),
    respondent_relationship: relationship,
    ...ratings,
    functional_areas: areas,
    other_functional_area: trimOrNull(source.other_functional_area),
    performance_3_years: trimOrNull(source.performance_3_years),
    challenges_coping: trimOrNull(source.challenges_coping),
    compliance_attendance: trimOrNull(source.compliance_attendance),
    other_relevant_information: trimOrNull(source.other_relevant_information),
  };
}

function trimOrNull(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text === '' ? null : text;
}

async function saveBi(client, entryId, payload, { requireComplete }) {
  if (requireComplete) {
    const missing = policy.validateBiSubmission(payload);
    if (missing.length) {
      throw new IssuedFormError(
        400,
        'FORM_INCOMPLETE',
        `Complete the required fields: ${missing.join(', ')}.`,
      );
    }
  }
  if (!payload.applicant_name || !payload.respondent_name) {
    throw new IssuedFormError(
      400,
      'FORM_INCOMPLETE',
      'Applicant name and respondent name are required.',
    );
  }
  const result = await client.query(
    `UPDATE public.bi_form_entries
     SET applicant_name = $2,
         applicant_department = $3,
         applicant_position = $4,
         position_applied_for = $5,
         respondent_name = $6,
         respondent_position = $7,
         respondent_relationship = $8,
         rating_1 = $9,
         rating_2 = $10,
         rating_3 = $11,
         rating_4 = $12,
         rating_5 = $13,
         rating_6 = $14,
         rating_7 = $15,
         rating_8 = $16,
         rating_9 = $17,
         functional_areas = $18::jsonb,
         other_functional_area = $19,
         performance_3_years = $20,
         challenges_coping = $21,
         compliance_attendance = $22,
         other_relevant_information = $23,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      entryId,
      payload.applicant_name,
      payload.applicant_department,
      payload.applicant_position,
      payload.position_applied_for,
      payload.respondent_name,
      payload.respondent_position,
      payload.respondent_relationship,
      payload.rating_1,
      payload.rating_2,
      payload.rating_3,
      payload.rating_4,
      payload.rating_5,
      payload.rating_6,
      payload.rating_7,
      payload.rating_8,
      payload.rating_9,
      JSON.stringify(payload.functional_areas),
      payload.other_functional_area,
      payload.performance_3_years,
      payload.challenges_coping,
      payload.compliance_attendance,
      payload.other_relevant_information,
    ],
  );
  return result.rows[0];
}

async function saveOjtApplicant(client, entryId, body, { requireComplete }) {
  const payload = {
    ojt_immersion: trimOrNull(body?.ojt_immersion),
    school: trimOrNull(body?.school),
  };
  if (requireComplete) {
    const missing = policy.validateOjtApplicant(payload);
    if (missing.length) {
      throw new IssuedFormError(
        400,
        'FORM_INCOMPLETE',
        `Complete the required fields: ${missing.join(', ')}.`,
      );
    }
  }
  const result = await client.query(
    `UPDATE public.ojt_work_immersion_evaluation_entries
     SET ojt_immersion = $2,
         school = $3,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [entryId, payload.ojt_immersion, payload.school],
  );
  return result.rows[0];
}

async function withApplicantEdit(applicationId, writer) {
  await assertIssuedFormSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const app = await loadLocked(client, applicationId);
    assertGatedDocumentApproved(app);
    if (!app.required_form_entry_id || !policy.isFormType(app.required_form_type)) {
      throw new IssuedFormError(409, 'FORM_NOT_ASSIGNED', 'HR has not assigned a form yet.');
    }
    if (!policy.applicantCanEdit(app.required_form_status)) {
      throw new IssuedFormError(
        409,
        'FORM_LOCKED',
        'This form is with HR and cannot be edited right now.',
      );
    }
    const saved = await writer(client, app);
    const nextStatus =
      app.required_form_status === 'needs_revision' ? 'needs_revision' : 'in_progress';
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET required_form_status = $2, updated_at = now()
       WHERE id = $1
       RETURNING ${ASSIGNMENT_SQL}`,
      [applicationId, nextStatus],
    );
    await client.query('COMMIT');
    return { assignment: publicAssignment(updated.rows[0]), entry: saved.entry };
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function saveApplicantDraft({ applicationId, body }) {
  return withApplicantEdit(applicationId, async (client, app) => {
    const entry =
      app.required_form_type === 'ojt'
        ? await saveOjtApplicant(client, app.required_form_entry_id, body, { requireComplete: false })
        : await saveBi(client, app.required_form_entry_id, biPayload(body), { requireComplete: false });
    return { entry };
  });
}

async function submitApplicantForm({ applicationId, body }) {
  await assertIssuedFormSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const app = await loadLocked(client, applicationId);
    assertGatedDocumentApproved(app);
    if (!app.required_form_entry_id) {
      throw new IssuedFormError(409, 'FORM_NOT_ASSIGNED', 'HR has not assigned a form yet.');
    }
    if (policy.hrCanReview(app.required_form_status) || app.required_form_status === 'approved') {
      await client.query('COMMIT');
      const entry = await loadEntry(app.required_form_type, app.required_form_entry_id);
      return { assignment: publicAssignment(app), entry, duplicate: true };
    }
    if (!policy.applicantCanEdit(app.required_form_status)) {
      throw new IssuedFormError(409, 'FORM_LOCKED', 'This form cannot be submitted right now.');
    }

    const entry =
      app.required_form_type === 'ojt'
        ? await saveOjtApplicant(client, app.required_form_entry_id, body, { requireComplete: true })
        : await saveBi(client, app.required_form_entry_id, biPayload(body), { requireComplete: true });

    const nextStatus = policy.statusAfterApplicantSubmit(app.required_form_status);
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET required_form_status = $2,
           required_form_submitted_at = now(),
           required_form_review_comment = NULL,
           updated_at = now()
       WHERE id = $1
       RETURNING ${ASSIGNMENT_SQL}`,
      [applicationId, nextStatus],
    );
    await appendLog(client, applicationId, {
      at: new Date().toISOString(),
      action: nextStatus,
      formType: app.required_form_type,
    });
    await client.query('COMMIT');
    return { assignment: publicAssignment(updated.rows[0]), entry, duplicate: false };
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function getRequiredForm(applicationId) {
  await assertIssuedFormSchema();
  const result = await pool.query(
    `SELECT ${ASSIGNMENT_SQL}
     FROM public.recruitment_applications
     WHERE id = $1`,
    [applicationId],
  );
  if (!result.rows[0]) {
    throw new IssuedFormError(404, 'NOT_FOUND', 'Application not found');
  }
  const row = result.rows[0];
  const entry = await loadEntry(row.required_form_type, row.required_form_entry_id);
  return { assignment: publicAssignment(row), entry };
}

async function approveRequiredForm({ applicationId, actorId }) {
  await assertIssuedFormSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const app = await loadLocked(client, applicationId);
    assertGatedDocumentApproved(app);
    if (app.required_form_status === 'approved') {
      await client.query('COMMIT');
      return { assignment: publicAssignment(app), duplicate: true };
    }
    if (!policy.hrCanReview(app.required_form_status)) {
      throw new IssuedFormError(
        409,
        'NOT_READY_FOR_APPROVAL',
        'The applicant must submit the form before it can be approved.',
      );
    }
    if (app.required_form_type === 'ojt') {
      const entry = await loadEntry('ojt', app.required_form_entry_id);
      if (!policy.ojtReadyForApproval(entry || {})) {
        throw new IssuedFormError(
          409,
          'OJT_EVALUATION_INCOMPLETE',
          'Complete the interviewer scores, recommendation, and interviewer name on the evaluation before approving.',
        );
      }
    }
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET required_form_status = 'approved',
           required_form_reviewed_by = $2,
           required_form_reviewed_at = now(),
           updated_at = now()
       WHERE id = $1
       RETURNING ${ASSIGNMENT_SQL}`,
      [applicationId, actorId || null],
    );
    await appendLog(client, applicationId, {
      at: new Date().toISOString(),
      action: 'approved',
      by: actorId || null,
    });
    await client.query('COMMIT');
    return { assignment: publicAssignment(updated.rows[0]), duplicate: false };
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function requestFormRevision({ applicationId, actorId, comment }) {
  const reason = trimOrNull(comment);
  if (!reason) {
    throw new IssuedFormError(400, 'COMMENT_REQUIRED', 'Enter the reason the form needs revision.');
  }
  await assertIssuedFormSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const app = await loadLocked(client, applicationId);
    assertGatedDocumentApproved(app);
    if (app.required_form_status === 'approved') {
      throw new IssuedFormError(409, 'ALREADY_APPROVED', 'This form is already approved.');
    }
    if (!policy.hrCanReview(app.required_form_status)) {
      throw new IssuedFormError(
        409,
        'NOT_READY_FOR_REVISION',
        'Request a revision after the applicant submits the form.',
      );
    }
    const notifyApplicant = revisionIsNew(
      app.required_form_status,
      app.required_form_review_comment,
      reason,
    );
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET required_form_status = 'needs_revision',
           required_form_reviewed_by = $2,
           required_form_reviewed_at = now(),
           required_form_review_comment = $3,
           updated_at = now()
       WHERE id = $1
       RETURNING ${ASSIGNMENT_SQL}`,
      [applicationId, actorId || null, reason],
    );
    await appendLog(client, applicationId, {
      at: new Date().toISOString(),
      action: 'needs_revision',
      by: actorId || null,
      comment: reason,
    });
    await client.query('COMMIT');
    return { assignment: publicAssignment(updated.rows[0]), applicantNotice: notifyApplicant };
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

function sendIssuedFormError(res, err, label) {
  if (err instanceof IssuedFormError) {
    return res.status(err.status).json({ error: err.message, code: err.code });
  }
  console.error(label, err);
  return res.status(500).json({
    error: 'Failed to update the required form',
    details: err?.message ? String(err.message) : String(err),
  });
}

module.exports = {
  IssuedFormError,
  assertIssuedFormSchema,
  assignRequiredForm,
  saveApplicantDraft,
  submitApplicantForm,
  getRequiredForm,
  approveRequiredForm,
  requestFormRevision,
  sendIssuedFormError,
  assessmentBlocked: policy.assessmentBlocked,
  shouldEnableIssuedFormGate: policy.shouldEnableIssuedFormGate,
};
