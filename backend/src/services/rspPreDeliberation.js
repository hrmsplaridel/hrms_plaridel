const { pool } = require('../config/db');
const policy = require('./rspPreDeliberationPolicy');
const {
  loadVacanciesFromDb,
  findListedVacancyForPosition,
  findVacancyForPosition,
  vacancyMinimumStandards,
  mergeBlankMinimumStandards,
} = require('../utils/jobVacancySlots');
const { revisionIsNew } = require('./rspApplicantNotices');
const { initializeCreatorSourceSignatures } = require('./docutrackerRspSignatureService');
const { resolveLineupCreatorId } = require('./selectionLineupEditAudit');

const MIGRATION = 'backend/scripts/migrations/20261007_rsp_pre_deliberation_gate.sql';
let schemaReady = false;

class PreDeliberationError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra || null;
  }
}

const TRACKING_SQL = `
  id, status, full_name, position_applied_for,
  step4_gate_required, wes_status, wes_entry_id, wes_assigned_at, wes_submitted_at,
  wes_reviewed_at, wes_review_comment,
  applicants_profile_entry_id, applicants_profile_status, applicants_profile_completed_at,
  selection_lineup_entry_id, selection_lineup_status, selection_lineup_completed_at
`;

async function assertPreDeliberationSchema() {
  if (schemaReady) return;
  const result = await pool.query(`
    SELECT
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'recruitment_applications'
          AND column_name = 'step4_gate_required'
      ) AS gate_column,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'work_experience_sheet_entries'
          AND column_name = 'application_id'
      ) AS wes_link,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'applicants_profile_entries'
          AND column_name = 'application_id'
      ) AS profile_link,
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'selection_lineup_entries'
          AND column_name = 'application_id'
      ) AS lineup_link
  `);
  const row = result.rows[0] || {};
  if (!row.gate_column || !row.wes_link || !row.profile_link || !row.lineup_link) {
    throw new PreDeliberationError(
      503,
      'PRE_DELIBERATION_SCHEMA_MISSING',
      `Pre-deliberation schema is not installed. Apply ${MIGRATION}`,
    );
  }
  schemaReady = true;
}

function publicTracking(row) {
  const missing = policy.missingPrerequisites(row);
  return {
    applicationId: row.id,
    step4GateRequired: row.step4_gate_required === true,
    wesStatus: row.wes_status,
    wesEntryId: row.wes_entry_id,
    wesReviewComment: row.wes_review_comment,
    applicantsProfileStatus: row.applicants_profile_status,
    applicantsProfileEntryId: row.applicants_profile_entry_id,
    selectionLineupStatus: row.selection_lineup_status,
    selectionLineupEntryId: row.selection_lineup_entry_id,
    deliberationUnlocked: missing.length === 0,
    missing,
  };
}

function trimOrNull(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text === '' ? null : text;
}

async function standardsForAppliedPosition(position) {
  const title = trimOrNull(position);
  if (!title) return null;
  const vacancies = await loadVacanciesFromDb();
  const vacancy =
    findListedVacancyForPosition(vacancies, title) ||
    findVacancyForPosition(vacancies, title);
  return vacancyMinimumStandards(vacancy);
}

async function fillBlankWesStandards(entry, position) {
  if (!entry || !entry.id) return entry;
  let standards = null;
  try {
    standards = await standardsForAppliedPosition(position || entry.position_applied_for);
  } catch (err) {
    console.error('[rspPreDeliberation] vacancy standards lookup failed', err);
    return entry;
  }
  const merged = mergeBlankMinimumStandards(entry, standards);
  if (!merged.changed) return entry;
  const next = merged.entry;
  const updated = await pool.query(
    `UPDATE public.work_experience_sheet_entries
     SET min_education = $2,
         min_experience = $3,
         min_training = $4,
         min_eligibility = $5,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      entry.id,
      next.min_education ?? null,
      next.min_experience ?? null,
      next.min_training ?? null,
      next.min_eligibility ?? null,
    ],
  );
  return updated.rows[0] || next;
}

async function loadLocked(client, applicationId) {
  const result = await client.query(
    `SELECT ${TRACKING_SQL}
     FROM public.recruitment_applications
     WHERE id = $1
     FOR UPDATE`,
    [applicationId],
  );
  if (!result.rows[0]) {
    throw new PreDeliberationError(404, 'NOT_FOUND', 'Application not found');
  }
  return result.rows[0];
}

function assertGatedPassed(row) {
  if (row.step4_gate_required !== true) {
    throw new PreDeliberationError(
      409,
      'PRE_DELIBERATION_GATE_NOT_REQUIRED',
      'This application does not use the pre-deliberation requirements.',
    );
  }
  if (row.status !== 'passed') {
    throw new PreDeliberationError(
      409,
      'ASSESSMENT_NOT_PASSED',
      'Assessment must be passed before pre-deliberation preparation.',
    );
  }
}

async function withClient(work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function loadRow(table, id) {
  if (!id) return null;
  const result = await pool.query(`SELECT * FROM ${table} WHERE id = $1`, [id]);
  return result.rows[0] || null;
}

async function recordAssessmentOutcome(applicationId, nextStatus) {
  await assertPreDeliberationSchema();
  const current = await pool.query(
    `SELECT status, final_interview_at, final_interview_passed, hired_user_id, step4_gate_required
     FROM public.recruitment_applications
     WHERE id = $1`,
    [applicationId],
  );
  if (!current.rows[0]) {
    throw new PreDeliberationError(404, 'NOT_FOUND', 'Application not found');
  }
  const enable = policy.shouldEnableStep4Gate(current.rows[0], nextStatus);
  await pool.query(
    `UPDATE public.recruitment_applications
     SET status = $1,
         updated_at = now(),
         step4_gate_required = CASE WHEN $3::boolean THEN TRUE ELSE step4_gate_required END,
         wes_status = CASE
           WHEN $3::boolean THEN COALESCE(wes_status, 'waiting_for_work_experience_sheet')
           ELSE wes_status
         END,
         applicants_profile_status = CASE
           WHEN $3::boolean THEN COALESCE(applicants_profile_status, 'waiting')
           ELSE applicants_profile_status
         END,
         selection_lineup_status = CASE
           WHEN $3::boolean THEN COALESCE(selection_lineup_status, 'waiting')
           ELSE selection_lineup_status
         END
     WHERE id = $2`,
    [nextStatus, applicationId, enable],
  );
}

async function assignWorkExperience({ applicationId, actorId }) {
  await assertPreDeliberationSchema();
  return withClient(async (client) => {
    const app = await loadLocked(client, applicationId);
    assertGatedPassed(app);
    if (app.wes_entry_id && app.wes_status && app.wes_status !== 'waiting_for_work_experience_sheet') {
      const entry = await loadRow('public.work_experience_sheet_entries', app.wes_entry_id);
      return {
        tracking: publicTracking(app),
        entry,
        created: false,
        duplicate: true,
        applicantNotice: false,
      };
    }
    const standards = await standardsForAppliedPosition(app.position_applied_for);
    const inserted = await client.query(
      `INSERT INTO public.work_experience_sheet_entries (
         position_applied_for, applicant_name, application_id,
         min_education, min_experience, min_training, min_eligibility,
         created_at, updated_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, now(), now())
       RETURNING *`,
      [
        app.position_applied_for,
        app.full_name,
        app.id,
        standards?.min_education || null,
        standards?.min_experience || null,
        standards?.min_training || null,
        standards?.min_eligibility || null,
      ],
    );
    const entry = inserted.rows[0];
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET wes_status = 'assigned',
           wes_entry_id = $2,
           wes_assigned_by = $3,
           wes_assigned_at = now(),
           wes_submitted_at = NULL,
           wes_reviewed_by = NULL,
           wes_reviewed_at = NULL,
           wes_review_comment = NULL,
           updated_at = now()
       WHERE id = $1
       RETURNING ${TRACKING_SQL}`,
      [applicationId, entry.id, actorId || null],
    );
    return {
      tracking: publicTracking(updated.rows[0]),
      entry,
      created: true,
      duplicate: false,
      applicantNotice: true,
    };
  });
}

function wesPayload(body) {
  const source = body && typeof body === 'object' ? body : {};
  return {
    position_applied_for: trimOrNull(source.position_applied_for),
    department: trimOrNull(source.department),
    min_education: trimOrNull(source.min_education),
    min_experience: trimOrNull(source.min_experience),
    min_training: trimOrNull(source.min_training),
    min_eligibility: trimOrNull(source.min_eligibility),
    job_description_last_work: trimOrNull(source.job_description_last_work),
    applicant_name: trimOrNull(source.applicant_name),
  };
}

async function writeWes(client, entryId, payload, { requireComplete }) {
  if (requireComplete) {
    const missing = policy.validateWes(payload);
    if (missing.length) {
      throw new PreDeliberationError(
        400,
        'FORM_INCOMPLETE',
        `Complete the required fields: ${missing.join(', ')}.`,
      );
    }
  }
  const result = await client.query(
    `UPDATE public.work_experience_sheet_entries
     SET position_applied_for = $2,
         department = $3,
         min_education = $4,
         min_experience = $5,
         min_training = $6,
         min_eligibility = $7,
         job_description_last_work = $8,
         applicant_name = $9,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      entryId,
      payload.position_applied_for,
      payload.department,
      payload.min_education,
      payload.min_experience,
      payload.min_training,
      payload.min_eligibility,
      payload.job_description_last_work,
      payload.applicant_name,
    ],
  );
  return result.rows[0];
}

async function saveApplicantWes({ applicationId, body, submit }) {
  await assertPreDeliberationSchema();
  return withClient(async (client) => {
    const app = await loadLocked(client, applicationId);
    assertGatedPassed(app);
    if (!app.wes_entry_id || !policy.applicantCanEditWes(app.wes_status)) {
      if (submit && (app.wes_status === 'submitted_for_review' || app.wes_status === 'resubmitted_for_review')) {
        const entry = await loadRow('public.work_experience_sheet_entries', app.wes_entry_id);
        return { tracking: publicTracking(app), entry, duplicate: true };
      }
      throw new PreDeliberationError(
        409,
        'WES_NOT_EDITABLE',
        'The Work Experience Sheet is not open for editing.',
      );
    }
    const entry = await writeWes(client, app.wes_entry_id, wesPayload(body), { requireComplete: submit === true });
    const nextStatus = submit ? policy.statusAfterWesSubmit(app.wes_status) : 'in_progress';
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET wes_status = $2,
           wes_submitted_at = CASE WHEN $3::boolean THEN now() ELSE wes_submitted_at END,
           wes_review_comment = CASE WHEN $3::boolean THEN NULL ELSE wes_review_comment END,
           updated_at = now()
       WHERE id = $1
       RETURNING ${TRACKING_SQL}`,
      [applicationId, nextStatus, submit === true],
    );
    return { tracking: publicTracking(updated.rows[0]), entry, duplicate: false };
  });
}

async function reviewWes({ applicationId, actorId, approve, comment }) {
  await assertPreDeliberationSchema();
  return withClient(async (client) => {
    const app = await loadLocked(client, applicationId);
    assertGatedPassed(app);
    if (!policy.hrCanReviewWes(app.wes_status)) {
      throw new PreDeliberationError(
        409,
        'WES_NOT_IN_REVIEW',
        'The Work Experience Sheet is not waiting for HR review.',
      );
    }
    if (!approve) {
      const reason = trimOrNull(comment);
      if (!reason) {
        throw new PreDeliberationError(400, 'REVISION_REASON_REQUIRED', 'Enter the reason for the revision.');
      }
      const notifyApplicant = revisionIsNew(app.wes_status, app.wes_review_comment, reason);
      const updated = await client.query(
        `UPDATE public.recruitment_applications
         SET wes_status = 'needs_revision',
             wes_reviewed_by = $2,
             wes_reviewed_at = now(),
             wes_review_comment = $3,
             updated_at = now()
         WHERE id = $1
         RETURNING ${TRACKING_SQL}`,
        [applicationId, actorId || null, reason],
      );
      const entry = await loadRow('public.work_experience_sheet_entries', app.wes_entry_id);
      return { tracking: publicTracking(updated.rows[0]), entry, applicantNotice: notifyApplicant };
    }
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET wes_status = 'approved',
           wes_reviewed_by = $2,
           wes_reviewed_at = now(),
           updated_at = now()
       WHERE id = $1
       RETURNING ${TRACKING_SQL}`,
      [applicationId, actorId || null],
    );
    const entry = await loadRow('public.work_experience_sheet_entries', app.wes_entry_id);
    return { tracking: publicTracking(updated.rows[0]), entry };
  });
}

const HR_FORMS = {
  profile: {
    table: 'public.applicants_profile_entries',
    entryColumn: 'applicants_profile_entry_id',
    statusColumn: 'applicants_profile_status',
    byColumn: 'applicants_profile_completed_by',
    atColumn: 'applicants_profile_completed_at',
    insertSql: `INSERT INTO public.applicants_profile_entries (
      position_applied_for, applicants, application_id, created_at, updated_at
    ) VALUES ($1, '[]'::jsonb, $2, now(), now()) RETURNING *`,
  },
  lineup: {
    table: 'public.selection_lineup_entries',
    entryColumn: 'selection_lineup_entry_id',
    statusColumn: 'selection_lineup_status',
    byColumn: 'selection_lineup_completed_by',
    atColumn: 'selection_lineup_completed_at',
    insertSql: `INSERT INTO public.selection_lineup_entries (
      vacant_position, applicants, application_id, created_at, updated_at
    ) VALUES ($1, '[]'::jsonb, $2, now(), now()) RETURNING *`,
  },
};

async function openHrForm({ applicationId, kind, actorId }) {
  const form = HR_FORMS[kind];
  if (!form) throw new PreDeliberationError(400, 'INVALID_FORM', 'Unknown HR form.');
  await assertPreDeliberationSchema();
  return withClient(async (client) => {
    const app = await loadLocked(client, applicationId);
    assertGatedPassed(app);
    const existingId = app[form.entryColumn];
    if (existingId) {
      const entry = await loadRow(form.table, existingId);
      if (app[form.statusColumn] === 'waiting') {
        const updated = await client.query(
          `UPDATE public.recruitment_applications
           SET ${form.statusColumn} = 'in_progress', updated_at = now()
           WHERE id = $1
           RETURNING ${TRACKING_SQL}`,
          [applicationId],
        );
        return { tracking: publicTracking(updated.rows[0]), entry, created: false };
      }
      return { tracking: publicTracking(app), entry, created: false, duplicate: app[form.statusColumn] === 'completed' };
    }
    let inserted;
    if (kind === 'lineup') {
      let creatorId;
      try {
        creatorId = resolveLineupCreatorId(actorId);
      } catch (err) {
        throw new PreDeliberationError(400, err.code || 'CREATOR_REQUIRED', err.message);
      }
      inserted = await client.query(
        `INSERT INTO public.selection_lineup_entries (
           vacant_position, applicants, application_id, created_by, created_at, updated_at
         ) VALUES ($1, '[]'::jsonb, $2, $3::uuid, now(), now())
         RETURNING *`,
        [app.position_applied_for, app.id, creatorId],
      );
      await initializeCreatorSourceSignatures(
        client,
        { id: creatorId },
        'selection_lineup_entries',
        inserted.rows[0].id,
      );
    } else {
      inserted = await client.query(form.insertSql, [app.position_applied_for, app.id]);
    }
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET ${form.entryColumn} = $2,
           ${form.statusColumn} = 'in_progress',
           updated_at = now()
       WHERE id = $1
       RETURNING ${TRACKING_SQL}`,
      [applicationId, inserted.rows[0].id],
    );
    return { tracking: publicTracking(updated.rows[0]), entry: inserted.rows[0], created: true };
  });
}

async function completeHrForm({ applicationId, kind, actorId }) {
  const form = HR_FORMS[kind];
  if (!form) throw new PreDeliberationError(400, 'INVALID_FORM', 'Unknown HR form.');
  await assertPreDeliberationSchema();
  return withClient(async (client) => {
    const app = await loadLocked(client, applicationId);
    assertGatedPassed(app);
    if (!app[form.entryColumn]) {
      throw new PreDeliberationError(
        409,
        'HR_FORM_NOT_OPENED',
        'Open the existing form before marking it completed.',
      );
    }
    if (app[form.statusColumn] === 'completed') {
      const entry = await loadRow(form.table, app[form.entryColumn]);
      return { tracking: publicTracking(app), entry, duplicate: true };
    }
    const updated = await client.query(
      `UPDATE public.recruitment_applications
       SET ${form.statusColumn} = 'completed',
           ${form.byColumn} = $2,
           ${form.atColumn} = now(),
           updated_at = now()
       WHERE id = $1
       RETURNING ${TRACKING_SQL}`,
      [applicationId, actorId || null],
    );
    const entry = await loadRow(form.table, app[form.entryColumn]);
    return { tracking: publicTracking(updated.rows[0]), entry, duplicate: false };
  });
}

async function getPreDeliberation(applicationId, { includeHrForms }) {
  await assertPreDeliberationSchema();
  const result = await pool.query(
    `SELECT ${TRACKING_SQL} FROM public.recruitment_applications WHERE id = $1`,
    [applicationId],
  );
  if (!result.rows[0]) {
    throw new PreDeliberationError(404, 'NOT_FOUND', 'Application not found');
  }
  const row = result.rows[0];
  const wes = await fillBlankWesStandards(
    await loadRow('public.work_experience_sheet_entries', row.wes_entry_id),
    row.position_applied_for,
  );
  if (!includeHrForms) {
    return { tracking: publicTracking(row), wes };
  }
  const profile = await loadRow('public.applicants_profile_entries', row.applicants_profile_entry_id);
  const lineup = await loadRow('public.selection_lineup_entries', row.selection_lineup_entry_id);
  return { tracking: publicTracking(row), wes, profile, lineup };
}

function parseApplicants(value) {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

async function matchingGatedApplications(kind, entry) {
  const form = HR_FORMS[kind];
  const applicants = parseApplicants(entry.applicants);
  const ids = policy.applicationIdsFromEntry({ ...entry, applicants });
  const unlabeled = policy.rowsWithoutApplicationId(applicants);
  const position = kind === 'lineup' ? entry.vacant_position : entry.position_applied_for;
  const hasName = unlabeled.some((item) => policy.normalizeLabel(item && item.name));
  if (ids.length === 0 && !hasName) {
    throw new PreDeliberationError(
      400,
      'HR_FORM_HAS_NO_APPLICANTS',
      'Save the applicant names on this form before marking it completed.',
    );
  }
  const result = await pool.query(
    `SELECT id::text AS id, full_name, position_applied_for,
            ${form.statusColumn} AS hr_status,
            ${form.entryColumn} AS hr_entry_id
     FROM public.recruitment_applications
     WHERE step4_gate_required = TRUE
       AND status = 'passed'`,
  );
  const byId = new Map(result.rows.map((row) => [String(row.id).toLowerCase(), row]));
  const matched = new Map();
  for (const id of ids) {
    const row = byId.get(id);
    if (row) matched.set(row.id, row);
  }
  for (const item of unlabeled) {
    const hits = policy.uniqueNamePositionMatches(result.rows, {
      name: item && item.name,
      position,
    });
    if (hits.length === 1) matched.set(hits[0].id, hits[0]);
  }
  return {
    form,
    matches: [...matched.values()],
    gatedRows: result.rows,
    applicants,
    position,
  };
}

async function persistResolvedApplicationIds(kind, entry, { applicants, gatedRows, position }) {
  const used = new Set(policy.applicationIdsFromEntry({ applicants }));
  let changed = false;
  const next = applicants.map((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return item;
    if (policy.canonicalApplicationId(item.application_id || item.applicationId)) return item;
    const hits = policy.uniqueNamePositionMatches(gatedRows, { name: item.name, position });
    if (hits.length !== 1) return item;
    const id = String(hits[0].id).toLowerCase();
    if (used.has(id)) return item;
    used.add(id);
    changed = true;
    return { ...item, application_id: id };
  });
  if (!changed || !entry.id) return;
  await pool.query(
    `UPDATE ${HR_FORMS[kind].table}
     SET applicants = $2::jsonb, updated_at = now()
     WHERE id = $1`,
    [entry.id, JSON.stringify(next)],
  );
}

async function sharedHrFormCompletion({ kind, entryId }) {
  const form = HR_FORMS[kind];
  if (!form) throw new PreDeliberationError(400, 'INVALID_FORM', 'Unknown HR form.');
  await assertPreDeliberationSchema();
  const entry = await loadRow(form.table, entryId);
  if (!entry) throw new PreDeliberationError(404, 'NOT_FOUND', 'Form record not found');
  let matches = [];
  try {
    matches = (await matchingGatedApplications(kind, entry)).matches;
  } catch (err) {
    if (err instanceof PreDeliberationError && err.code === 'HR_FORM_HAS_NO_APPLICANTS') {
      return { matched: 0, alreadyCompleted: 0, allCompleted: false };
    }
    throw err;
  }
  const alreadyCompleted = matches.filter((row) => row.hr_status === 'completed').length;
  return {
    matched: matches.length,
    alreadyCompleted,
    allCompleted: matches.length > 0 && alreadyCompleted === matches.length,
  };
}

async function completeSharedHrForm({ kind, entryId, actorId }) {
  const form = HR_FORMS[kind];
  if (!form) throw new PreDeliberationError(400, 'INVALID_FORM', 'Unknown HR form.');
  await assertPreDeliberationSchema();
  const entry = await loadRow(form.table, entryId);
  if (!entry) throw new PreDeliberationError(404, 'NOT_FOUND', 'Form record not found');
  const resolved = await matchingGatedApplications(kind, entry);
  const { matches } = resolved;
  if (matches.length === 0) {
    throw new PreDeliberationError(
      409,
      'HR_FORM_NO_MATCHING_APPLICATION',
      'No recruitment application could be linked from this form. Use the application id on each row, or a name and position that matches exactly one applicant.',
    );
  }
  await persistResolvedApplicationIds(kind, entry, resolved);
  let completed = 0;
  let alreadyCompleted = 0;
  for (const row of matches) {
    if (row.hr_status === 'completed') {
      alreadyCompleted += 1;
      continue;
    }
    await pool.query(
      `UPDATE public.recruitment_applications
       SET ${form.entryColumn} = $2,
           ${form.statusColumn} = 'completed',
           ${form.byColumn} = $3,
           ${form.atColumn} = now(),
           updated_at = now()
       WHERE id = $1
         AND ${form.statusColumn} IS DISTINCT FROM 'completed'`,
      [row.id, entryId, actorId || null],
    );
    completed += 1;
  }
  return {
    matched: matches.length,
    completed,
    alreadyCompleted,
    allCompleted: true,
    duplicate: completed === 0,
  };
}

function sendPreDeliberationError(res, err, label) {
  if (err instanceof PreDeliberationError) {
    return res.status(err.status).json({
      error: err.message,
      code: err.code,
      ...(err.extra || {}),
    });
  }
  console.error(label, err);
  return res.status(500).json({ error: 'Pre-deliberation request failed' });
}

module.exports = {
  PreDeliberationError,
  assertPreDeliberationSchema,
  recordAssessmentOutcome,
  assignWorkExperience,
  saveApplicantWes,
  reviewWes,
  openHrForm,
  completeHrForm,
  sharedHrFormCompletion,
  completeSharedHrForm,
  getPreDeliberation,
  sendPreDeliberationError,
  missingPrerequisites: policy.missingPrerequisites,
  deliberationBlocked: policy.deliberationBlocked,
};
