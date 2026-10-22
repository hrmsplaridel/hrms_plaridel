const { pool } = require('../config/db');
const policy = require('./rspFinalHiringPolicy');

const MIGRATION = 'backend/scripts/migrations/rsp/20261008_rsp_final_hiring_gate.sql';
let schemaReady = false;

class FinalHiringError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra || null;
  }
}

async function assertFinalHiringSchema() {
  if (schemaReady) return;
  const result = await pool.query(`
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'recruitment_applications'
        AND column_name = 'step5_gate_required'
    ) AS gate_column
  `);
  if (!result.rows[0] || result.rows[0].gate_column !== true) {
    throw new FinalHiringError(
      503,
      'FINAL_HIRING_SCHEMA_MISSING',
      `Final Hiring gate schema is not installed. Apply ${MIGRATION}`,
    );
  }
  schemaReady = true;
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

async function loadTatEntry(entryId) {
  const result = await pool.query(
    `SELECT id, position, applicants
     FROM public.turn_around_time_entries
     WHERE id = $1`,
    [entryId],
  );
  return result.rows[0] || null;
}

async function matchingGatedApplications(entry) {
  const applicants = parseApplicants(entry.applicants);
  const ids = policy.applicationIdsFromEntry({ ...entry, applicants });
  if (ids.length === 0) {
    const named = applicants.some((item) => String(item && item.name || '').trim());
    if (!named) {
      throw new FinalHiringError(
        400,
        'TAT_HAS_NO_APPLICANTS',
        'Save applicant rows on this Turn-Around Time form before marking it completed.',
      );
    }
    return { matches: [], applicants, gatedRows: [], position: entry.position };
  }
  const result = await pool.query(
    `SELECT id::text AS id, full_name, position_applied_for, tat_status
     FROM public.recruitment_applications
     WHERE step5_gate_required = TRUE
       AND final_interview_passed = TRUE`,
  );
  const byId = new Map(result.rows.map((row) => [String(row.id).toLowerCase(), row]));
  const matched = new Map();
  for (const id of ids) {
    const row = byId.get(id);
    if (row) matched.set(row.id, row);
  }
  return { matches: [...matched.values()], applicants, gatedRows: result.rows, position: entry.position };
}

async function tatCompletion({ entryId }) {
  await assertFinalHiringSchema();
  const entry = await loadTatEntry(entryId);
  if (!entry) throw new FinalHiringError(404, 'NOT_FOUND', 'Turn-Around Time record not found');
  let matches = [];
  try {
    matches = (await matchingGatedApplications(entry)).matches;
  } catch (err) {
    if (err instanceof FinalHiringError && err.code === 'TAT_HAS_NO_APPLICANTS') {
      return { matched: 0, alreadyCompleted: 0, allCompleted: false };
    }
    throw err;
  }
  const alreadyCompleted = matches.filter((row) => row.tat_status === 'completed').length;
  return {
    matched: matches.length,
    alreadyCompleted,
    allCompleted: matches.length > 0 && alreadyCompleted === matches.length,
  };
}

async function completeTurnAroundTime({ entryId, actorId }) {
  await assertFinalHiringSchema();
  const entry = await loadTatEntry(entryId);
  if (!entry) throw new FinalHiringError(404, 'NOT_FOUND', 'Turn-Around Time record not found');
  const resolved = await matchingGatedApplications(entry);
  if (resolved.matches.length === 0) {
    throw new FinalHiringError(
      409,
      'TAT_NO_MATCHING_APPLICATION',
      'No recruitment application is linked on this form. Choose the applicant from Recruitment applications so the row keeps its application id.',
    );
  }
  let completed = 0;
  let alreadyCompleted = 0;
  for (const row of resolved.matches) {
    if (row.tat_status === 'completed') {
      alreadyCompleted += 1;
      continue;
    }
    await pool.query(
      `UPDATE public.recruitment_applications
       SET tat_entry_id = $2,
           tat_status = 'completed',
           tat_completed_by = $3,
           tat_completed_at = now(),
           csc_approval_status = COALESCE(csc_approval_status, 'waiting'),
           updated_at = now()
       WHERE id = $1
         AND tat_status IS DISTINCT FROM 'completed'`,
      [row.id, entryId, actorId || null],
    );
    completed += 1;
  }
  return {
    matched: resolved.matches.length,
    completed,
    alreadyCompleted,
    allCompleted: true,
    duplicate: completed === 0,
  };
}

async function markCscApproved({ applicationId, actorId }) {
  await assertFinalHiringSchema();
  const result = await pool.query(
    `SELECT id, final_interview_passed, step5_gate_required, tat_status, csc_approval_status
     FROM public.recruitment_applications
     WHERE id = $1`,
    [applicationId],
  );
  const row = result.rows[0];
  if (!row) throw new FinalHiringError(404, 'NOT_FOUND', 'Application not found');
  if (row.final_interview_passed !== true || row.step5_gate_required !== true) {
    throw new FinalHiringError(
      409,
      'FINAL_HIRING_GATE_INCOMPLETE',
      'CSC approval applies only after deliberation is passed for a gated application.',
      { missing: ['Deliberation not passed'] },
    );
  }
  if (row.tat_status !== 'completed') {
    throw new FinalHiringError(
      409,
      'FINAL_HIRING_GATE_INCOMPLETE',
      'Complete the Turn-Around Time form before confirming CSC approval.',
      { missing: ['Turn-Around Time not completed'] },
    );
  }
  if (row.csc_approval_status === 'approved') {
    return { duplicate: true, cscApprovalStatus: 'approved' };
  }
  await pool.query(
    `UPDATE public.recruitment_applications
     SET csc_approval_status = 'approved',
         csc_approved_by = $2,
         csc_approved_at = now(),
         updated_at = now()
     WHERE id = $1
       AND csc_approval_status IS DISTINCT FROM 'approved'`,
    [applicationId, actorId || null],
  );
  return { duplicate: false, cscApprovalStatus: 'approved' };
}

function sendFinalHiringError(res, err, label) {
  if (err instanceof FinalHiringError) {
    return res.status(err.status).json({
      error: err.message,
      code: err.code,
      ...(err.extra || {}),
    });
  }
  console.error(label, err);
  return res.status(500).json({ error: 'Final Hiring gate request failed' });
}

module.exports = {
  FinalHiringError,
  assertFinalHiringSchema,
  tatCompletion,
  completeTurnAroundTime,
  markCscApproved,
  sendFinalHiringError,
  missingFinalHiringPrerequisites: policy.missingFinalHiringPrerequisites,
  shouldEnableStep5Gate: policy.shouldEnableStep5Gate,
};
