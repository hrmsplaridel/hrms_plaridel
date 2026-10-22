/**
 * RSP / L&D saved form rows — persisted in PostgreSQL (tables from init-schema.sql).
 * Flutter calls this API with JWT; all rows are in Postgres only.
 *
 * All routes: JWT + admin role.
 */
const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  creatorOwnedSlotKeys,
  initializeCreatorSourceSignatures,
  readApplicantsProfileSignatureLock,
  annotateApplicantsProfileSignatureState,
} = require('../services/docutrackerRspSignatureService');
const {
  APPLICANTS_PROFILE_TABLE,
  LOCKED_CODE,
  LOCKED_MESSAGE,
} = require('../services/applicantsProfileSignatureLock');
const { validateTurnAroundTimeCreate } = require('../services/rspTurnAroundTimeCreate');
const { writeGovernanceAudit } = require('../services/docutrackerGovernanceAudit');
const {
  SELECTION_LINEUP_TABLE,
  EDIT_EVENT: SELECTION_LINEUP_EDIT_EVENT,
  EDIT_ENTITY: SELECTION_LINEUP_EDIT_ENTITY,
  diffSelectionLineup,
  signatureStateFromSlot: lineupSignatureStateFromSlot,
  buildContentEditAudit: buildLineupContentEditAudit,
  serializeEditHistoryRow: serializeLineupEditHistoryRow,
} = require('../services/selectionLineupEditAudit');
const {
  COMPUTATION_OF_POINTS_TABLE,
  EDIT_EVENT: COMPUTATION_EDIT_EVENT,
  EDIT_ENTITY: COMPUTATION_EDIT_ENTITY,
  diffComputationOfPoints,
  signatureStateFromSlot: computationSignatureStateFromSlot,
  shouldRecordContentEdit,
  buildContentEditAudit: buildComputationContentEditAudit,
  serializeEditHistoryRow: serializeComputationEditHistoryRow,
} = require('../services/computationOfPointsEditAudit');
const {
  TURN_AROUND_TIME_TABLE,
  EDIT_EVENT: TAT_EDIT_EVENT,
  EDIT_ENTITY: TAT_EDIT_ENTITY,
  diffTurnAroundTime,
  planTatRevision,
  shouldRecordTatEdit,
  buildContentEditAudit: buildTatContentEditAudit,
  serializeEditHistoryRow: serializeTatEditHistoryRow,
} = require('../services/turnAroundTimeEditAudit');

const router = express.Router();

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Table name -> allowlisted column names for INSERT/UPDATE (snake_case). */
const TABLE_COLUMNS = {
  bi_form_entries: [
    'applicant_name',
    'applicant_department',
    'applicant_position',
    'position_applied_for',
    'respondent_name',
    'respondent_position',
    'respondent_relationship',
    'rating_1',
    'rating_2',
    'rating_3',
    'rating_4',
    'rating_5',
    'rating_6',
    'rating_7',
    'rating_8',
    'rating_9',
    'functional_areas',
    'other_functional_area',
    'performance_3_years',
    'challenges_coping',
    'compliance_attendance',
    'other_relevant_information',
    'updated_at',
  ],
  performance_evaluation_entries: [
    'applicant_name',
    'functional_areas',
    'other_functional_area',
    'performance_3_years',
    'challenges_coping',
    'compliance_attendance',
    'updated_at',
  ],
  training_need_analysis_entries: ['cy_year', 'department', 'rows', 'updated_at'],
  action_brainstorming_coaching_entries: [
    'department',
    'date',
    'rows',
    'certified_by',
    'certification_date',
    'updated_at',
  ],
  turn_around_time_entries: [
    'position',
    'office',
    'no_of_vacant_position',
    'date_of_publication',
    'end_search',
    'qs',
    'applicants',
    'prepared_by_name',
    'prepared_by_title',
    'noted_by_name',
    'noted_by_title',
    'updated_at',
  ],
  learning_application_plan_entries: [
    'memo_report_to',
    'from_name',
    'thru',
    'subject',
    'title',
    'date',
    'venue',
    'cost',
    'reap_types',
    'other_reap_type',
    'reported_by',
    'received_by',
    'entries',
    'updated_at',
  ],
  idp_entries: [
    'name',
    'position',
    'category',
    'division',
    'department',
    'education',
    'experience',
    'training',
    'eligibility',
    'significant_accomplishments',
    'target_position_1',
    'target_position_2',
    'avg_rating',
    'opcr',
    'ipcr',
    'performance_rating',
    'competency_description',
    'competence_rating',
    'succession_priority_score',
    'succession_priority_rating',
    'development_plan_rows',
    'prepared_by',
    'reviewed_by',
    'noted_by',
    'approved_by',
    'updated_at',
  ],
  selection_lineup_entries: [
    'date',
    'name_of_agency_office',
    'vacant_position',
    'item_no',
    'applicants',
    'prepared_by_name',
    'prepared_by_title',
    'updated_at',
  ],
  computation_of_points_entries: [
    'date',
    'position_level',
    'position',
    'salary_grade',
    'rate',
    'office',
    'min_education',
    'min_training',
    'min_experience',
    'min_eligibility',
    'candidates',
    'prepared_by_name',
    'updated_at',
  ],
  work_experience_sheet_entries: [
    'position_applied_for',
    'department',
    'min_education',
    'min_experience',
    'min_training',
    'min_eligibility',
    'job_description_last_work',
    'applicant_name',
    'updated_at',
  ],
  applicants_profile_entries: [
    'position_applied_for',
    'minimum_requirements',
    'date_of_posting',
    'closing_date',
    'applicants',
    'prepared_by',
    'checked_by',
    'updated_at',
  ],
  comparative_assessment_entries: [
    'position_to_be_filled',
    'min_req_education',
    'min_req_experience',
    'min_req_eligibility',
    'min_req_training',
    'candidates',
    'updated_at',
  ],
  promotion_certification_entries: [
    'position_for_promotion',
    'candidates',
    'date_day',
    'date_month',
    'date_year',
    'signatory_name',
    'signatory_title',
    'updated_at',
  ],
  ojt_work_immersion_evaluation_entries: [
    'ojt_immersion',
    'school',
    'interview_date',
    'problem_solving_score',
    'problem_solving_notes',
    'communication_score',
    'communication_notes',
    'teamwork_score',
    'teamwork_notes',
    'adaptability_score',
    'adaptability_notes',
    'total_score',
    'overall_recommendation',
    'key_strengths',
    'key_concerns',
    'interviewer',
    'interviewer_signature',
    'updated_at',
  ],
};

function isAllowedTable(table) {
  return Object.prototype.hasOwnProperty.call(TABLE_COLUMNS, table);
}

function quoteIdent(name) {
  if (!/^[a-z][a-z0-9_]*$/i.test(name)) {
    throw new Error('Invalid identifier');
  }
  return `"${name.replace(/"/g, '')}"`;
}

/** Plain object for INSERT/UPDATE (handles occasional string bodies or null-prototype objects). */
function coerceJsonObject(body) {
  if (body == null) return {};
  if (typeof body === 'string') {
    const t = body.trim();
    if (!t) return {};
    try {
      const parsed = JSON.parse(t);
      if (parsed != null && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed;
      }
    } catch (_) {
      return {};
    }
    return {};
  }
  if (typeof body === 'object' && !Array.isArray(body)) {
    return body;
  }
  return {};
}

function pickPayload(table, body) {
  const allowed = TABLE_COLUMNS[table];
  const obj = coerceJsonObject(body);
  if (!allowed) return {};
  const out = {};
  for (const col of allowed) {
    if (Object.prototype.hasOwnProperty.call(obj, col)) {
      out[col] = obj[col];
    }
  }
  return out;
}

/** JSON/JSONB columns: node-pg + some PG setups are more reliable with an explicit JSON string. */
const TABLE_JSONB_COLUMNS = {
  bi_form_entries: ['functional_areas'],
  performance_evaluation_entries: ['functional_areas'],
  training_need_analysis_entries: ['rows'],
  action_brainstorming_coaching_entries: ['rows'],
  turn_around_time_entries: ['applicants'],
  idp_entries: ['development_plan_rows'],
  learning_application_plan_entries: ['reap_types', 'entries'],
  selection_lineup_entries: ['applicants'],
  computation_of_points_entries: ['candidates'],
  applicants_profile_entries: ['applicants'],
  comparative_assessment_entries: ['candidates'],
  promotion_certification_entries: ['candidates'],
};

function stringifyJsonbForPg(table, payload) {
  const cols = TABLE_JSONB_COLUMNS[table];
  if (!cols || cols.length === 0) return payload;
  const out = { ...payload };
  for (const col of cols) {
    if (!Object.prototype.hasOwnProperty.call(out, col)) continue;
    const v = out[col];
    if (v === null || v === undefined) continue;
    if (typeof v === 'object') {
      out[col] = JSON.stringify(v);
    }
  }
  return out;
}

function pgErrorHint(err) {
  const msg = err && err.message ? String(err.message) : '';
  if (!msg) return '';
  return msg.length <= 200 ? msg : `${msg.slice(0, 197)}…`;
}

/**
 * Defensive: same DDL as init-schema.sql so saves work
 * if the DB was created before those scripts were added.
 */
let rspLdSavedEntryTablesReady = false;

async function ensureRspLdSavedEntryTables() {
  if (rspLdSavedEntryTablesReady) return;
  await pool.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.bi_form_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      applicant_name TEXT NOT NULL,
      applicant_department TEXT,
      applicant_position TEXT,
      position_applied_for TEXT,
      respondent_name TEXT NOT NULL,
      respondent_position TEXT,
      respondent_relationship TEXT NOT NULL DEFAULT 'supervisor'
        CHECK (respondent_relationship IN ('supervisor', 'peer', 'subordinate')),
      rating_1 INT,
      rating_2 INT,
      rating_3 INT,
      rating_4 INT,
      rating_5 INT,
      rating_6 INT,
      rating_7 INT,
      rating_8 INT,
      rating_9 INT,
      functional_areas JSONB DEFAULT '[]'::JSONB,
      other_functional_area TEXT,
      performance_3_years TEXT,
      challenges_coping TEXT,
      compliance_attendance TEXT,
      other_relevant_information TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS functional_areas JSONB DEFAULT '[]'::JSONB;
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS other_functional_area TEXT;
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS performance_3_years TEXT;
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS challenges_coping TEXT;
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS compliance_attendance TEXT;
    ALTER TABLE public.bi_form_entries ADD COLUMN IF NOT EXISTS other_relevant_information TEXT;
  `);

  await pool.query(`
    ALTER TABLE public.idp_entries ADD COLUMN IF NOT EXISTS significant_accomplishments TEXT;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.performance_evaluation_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      applicant_name TEXT,
      functional_areas JSONB DEFAULT '[]'::JSONB,
      other_functional_area TEXT,
      performance_3_years TEXT,
      challenges_coping TEXT,
      compliance_attendance TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.training_need_analysis_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      cy_year TEXT,
      department TEXT,
      rows JSONB DEFAULT '[]'::JSONB,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.action_brainstorming_coaching_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      department TEXT,
      date TEXT,
      rows JSONB DEFAULT '[]'::JSONB,
      certified_by TEXT,
      certification_date TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.turn_around_time_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      position TEXT,
      office TEXT,
      no_of_vacant_position TEXT,
      date_of_publication TEXT,
      end_search TEXT,
      qs TEXT,
      applicants JSONB DEFAULT '[]'::JSONB,
      prepared_by_name TEXT,
      prepared_by_title TEXT,
      noted_by_name TEXT,
      noted_by_title TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.learning_application_plan_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      memo_report_to TEXT,
      from_name TEXT,
      thru TEXT,
      subject TEXT,
      title TEXT,
      date TEXT,
      venue TEXT,
      cost TEXT,
      reap_types JSONB DEFAULT '[]'::JSONB,
      other_reap_type TEXT,
      reported_by TEXT,
      received_by TEXT,
      entries JSONB DEFAULT '[]'::JSONB,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.idp_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      name TEXT,
      position TEXT,
      category TEXT,
      division TEXT,
      department TEXT,
      education TEXT,
      experience TEXT,
      training TEXT,
      eligibility TEXT,
      target_position_1 TEXT,
      target_position_2 TEXT,
      avg_rating TEXT,
      opcr TEXT,
      ipcr TEXT,
      performance_rating TEXT,
      competency_description TEXT,
      competence_rating TEXT,
      succession_priority_score TEXT,
      succession_priority_rating TEXT,
      development_plan_rows JSONB DEFAULT '[]'::JSONB,
      prepared_by TEXT,
      reviewed_by TEXT,
      noted_by TEXT,
      approved_by TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.selection_lineup_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      date TEXT,
      name_of_agency_office TEXT,
      vacant_position TEXT,
      item_no TEXT,
      applicants JSONB DEFAULT '[]',
      prepared_by_name TEXT,
      prepared_by_title TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.computation_of_points_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      date TEXT,
      position_level TEXT,
      position TEXT,
      salary_grade TEXT,
      rate TEXT,
      office TEXT,
      min_education TEXT,
      min_training TEXT,
      min_experience TEXT,
      min_eligibility TEXT,
      candidates JSONB DEFAULT '[]',
      prepared_by_name TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.work_experience_sheet_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      position_applied_for TEXT,
      department TEXT,
      min_education TEXT,
      min_experience TEXT,
      min_training TEXT,
      min_eligibility TEXT,
      job_description_last_work TEXT,
      applicant_name TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.applicants_profile_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
      position_applied_for TEXT,
      minimum_requirements TEXT,
      date_of_posting TEXT,
      closing_date TEXT,
      applicants JSONB DEFAULT '[]',
      prepared_by TEXT,
      checked_by TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.comparative_assessment_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      position_to_be_filled TEXT,
      min_req_education TEXT,
      min_req_experience TEXT,
      min_req_eligibility TEXT,
      min_req_training TEXT,
      candidates JSONB DEFAULT '[]',
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.promotion_certification_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      position_for_promotion TEXT,
      candidates JSONB DEFAULT '[]',
      date_day TEXT,
      date_month TEXT,
      date_year TEXT,
      signatory_name TEXT,
      signatory_title TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.ojt_work_immersion_evaluation_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      ojt_immersion TEXT,
      school TEXT,
      interview_date TEXT,
      problem_solving_score INT,
      problem_solving_notes TEXT,
      communication_score INT,
      communication_notes TEXT,
      teamwork_score INT,
      teamwork_notes TEXT,
      adaptability_score INT,
      adaptability_notes TEXT,
      total_score INT,
      overall_recommendation TEXT,
      key_strengths TEXT,
      key_concerns TEXT,
      interviewer TEXT,
      interviewer_signature TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  `);

  await pool.query(`
    ALTER TABLE public.ojt_work_immersion_evaluation_entries
      ADD COLUMN IF NOT EXISTS interviewer_signature TEXT;
  `);

  rspLdSavedEntryTablesReady = true;
}

router.use(authMiddleware, requireAdmin);

const EDIT_HISTORY_FORMS = Object.freeze({
  [SELECTION_LINEUP_TABLE]: Object.freeze({
    entity: SELECTION_LINEUP_EDIT_ENTITY,
    event: SELECTION_LINEUP_EDIT_EVENT,
    serialize: serializeLineupEditHistoryRow,
  }),
  [COMPUTATION_OF_POINTS_TABLE]: Object.freeze({
    entity: COMPUTATION_EDIT_ENTITY,
    event: COMPUTATION_EDIT_EVENT,
    serialize: serializeComputationEditHistoryRow,
  }),
  [TURN_AROUND_TIME_TABLE]: Object.freeze({
    entity: TAT_EDIT_ENTITY,
    event: TAT_EDIT_EVENT,
    serialize: serializeTatEditHistoryRow,
  }),
});

router.get('/:table/:id/edit-history', async (req, res) => {
  const { table, id } = req.params;
  const historyForm = EDIT_HISTORY_FORMS[table];
  if (!historyForm) {
    return res.status(404).json({ error: 'Edit history is not available for this form' });
  }
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'Invalid id' });
  }
  try {
    await ensureRspLdSavedEntryTables();
    const found = await pool.query(
      `SELECT id FROM ${quoteIdent(table)} WHERE id = $1`,
      [id],
    );
    if (!found.rowCount) return res.status(404).json({ error: 'Not found' });
    const history = await pool.query(
      `SELECT a.id, a.created_at, a.actor_id, a.before_state, a.after_state, a.reason,
              u.full_name AS actor_name
       FROM docutracker_governance_audit a
       LEFT JOIN users u ON u.id = a.actor_id
       WHERE a.entity_type = $1
         AND a.entity_id = $2
         AND a.event_type = $3
       ORDER BY a.created_at DESC`,
      [historyForm.entity, id, historyForm.event],
    );
    return res.json({
      ok: true,
      edits: history.rows.map(historyForm.serialize),
    });
  } catch (err) {
    if (err.code === '42P01' || err.code === '42703') {
      return res.status(503).json({
        error: 'Edit history is not available until the governance audit table is installed.',
      });
    }
    console.error('[rspLdSavedEntries GET edit-history]', err);
    return res.status(500).json({ error: 'Failed to load edit history' });
  }
});

router.get('/:table/:id', async (req, res) => {
  const { table, id } = req.params;
  if (!isAllowedTable(table)) {
    return res.status(400).json({ error: 'Unknown table' });
  }
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'Invalid id' });
  }
  try {
    await ensureRspLdSavedEntryTables();
    const q = `SELECT * FROM ${quoteIdent(table)} WHERE id = $1`;
    const result = await pool.query(q, [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    if (table === APPLICANTS_PROFILE_TABLE) {
      const [annotated] = await annotateApplicantsProfileSignatureState(pool, result.rows);
      return res.json(annotated);
    }
    return res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
      });
    }
    console.error('[rspLdSavedEntries GET one]', err);
    return res.status(500).json({ error: 'Failed to load record' });
  }
});

router.get('/:table', async (req, res) => {
  const { table } = req.params;
  if (!isAllowedTable(table)) {
    return res.status(400).json({ error: 'Unknown table' });
  }
  try {
    await ensureRspLdSavedEntryTables();
    const q = `SELECT * FROM ${quoteIdent(table)} ORDER BY created_at DESC`;
    const result = await pool.query(q);
    if (table === APPLICANTS_PROFILE_TABLE) {
      return res.json(await annotateApplicantsProfileSignatureState(pool, result.rows));
    }
    return res.json(result.rows);
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
      });
    }
    console.error('[rspLdSavedEntries GET list]', err);
    return res.status(500).json({ error: 'Failed to list records' });
  }
});

router.post('/:table', async (req, res) => {
  const { table } = req.params;
  if (!isAllowedTable(table)) {
    return res.status(400).json({ error: 'Unknown table' });
  }
  let payload = pickPayload(table, req.body);
  delete payload.id;
  payload = stringifyJsonbForPg(table, payload);
  if (table === 'turn_around_time_entries') {
    const check = validateTurnAroundTimeCreate(payload);
    if (!check.ok) {
      return res.status(check.status).json({
        error: check.error,
        code: check.code,
        fields: check.fields,
      });
    }
    payload.position = check.position;
    payload.office = check.office;
  }
  if (Object.keys(payload).length === 0) {
    return res.status(400).json({ error: 'Empty body' });
  }
  if (creatorOwnedSlotKeys(table).length) {
    payload.created_by = req.user.id;
  }
  const keys = Object.keys(payload);
  let client;
  try {
    await ensureRspLdSavedEntryTables();
    client = await pool.connect();
    await client.query('BEGIN');
    const jsonbSet = new Set(TABLE_JSONB_COLUMNS[table] || []);
    const colsList = keys.map((k) => quoteIdent(k)).join(', ');
    const phList = keys
      .map((k, i) => (jsonbSet.has(k) ? `$${i + 1}::jsonb` : `$${i + 1}`))
      .join(', ');
    const values = keys.map((k) => payload[k]);
    const q = `INSERT INTO ${quoteIdent(table)} (${colsList}) VALUES (${phList}) RETURNING *`;
    const result = await client.query(q, values);
    // Snapshots automatic RSP/L&D signers (creator, dept head, HRMDO, mayor)
    // in the same transaction. Unresolved roles stay empty for admin recovery.
    await initializeCreatorSourceSignatures(
      client,
      req.user,
      table,
      result.rows[0].id
    );
    const saved = table === APPLICANTS_PROFILE_TABLE
      ? (await annotateApplicantsProfileSignatureState(client, result.rows))[0]
      : result.rows[0];
    await client.query('COMMIT');
    return res.status(201).json(saved);
  } catch (err) {
    if (client) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    if (err.code === '42P01' || err.code === '42703') {
      return res.status(503).json({
        error: 'Form signatures are not initialized. Apply the latest DocuTracker migrations.',
      });
    }
    console.error('[rspLdSavedEntries POST]', err);
    const hint = pgErrorHint(err);
    return res.status(500).json({
      error: hint ? `Failed to save record (${hint})` : 'Failed to save record',
    });
  } finally {
    client?.release();
  }
});

router.put('/:table/:id', async (req, res) => {
  const { table, id } = req.params;
  if (!isAllowedTable(table)) {
    return res.status(400).json({ error: 'Unknown table' });
  }
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'Invalid id' });
  }
  let payload = pickPayload(table, req.body);
  delete payload.id;
  payload = stringifyJsonbForPg(table, payload);
  const keys = Object.keys(payload);
  if (keys.length === 0) {
    return res.status(400).json({ error: 'No fields to update' });
  }
  try {
    await ensureRspLdSavedEntryTables();
    const jsonbSet = new Set(TABLE_JSONB_COLUMNS[table] || []);
    const setClause = keys
      .map((k, i) =>
        jsonbSet.has(k)
          ? `${quoteIdent(k)} = $${i + 1}::jsonb`
          : `${quoteIdent(k)} = $${i + 1}`,
      )
      .join(', ');
    const values = keys.map((k) => payload[k]);
    values.push(id);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      let lineupAudit = null;
      if (table === SELECTION_LINEUP_TABLE) {
        const current = await client.query(
          `SELECT * FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
          [id],
        );
        if (!current.rowCount) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Not found' });
        }
        const diff = diffSelectionLineup(current.rows[0], payload);
        if (diff) {
          let signature = lineupSignatureStateFromSlot(null);
          try {
            const slot = await client.query(
              `SELECT assigned_signer_id, signature_asset_id, signed_at, signer_name_snapshot
               FROM docutracker_rsp_source_signatures
               WHERE source_table = $1 AND source_record_id = $2::uuid AND slot_key = 'prepared_by'`,
              [SELECTION_LINEUP_TABLE, id],
            );
            signature = lineupSignatureStateFromSlot(slot.rows[0]);
          } catch (slotErr) {
            if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
          }
          const actor = await client.query(
            `SELECT full_name FROM users WHERE id = $1::uuid`,
            [req.user.id],
          );
          lineupAudit = buildLineupContentEditAudit({
            recordId: id,
            actorId: req.user.id,
            actorName: actor.rows[0]?.full_name || null,
            diff,
            signature,
          });
        }
      }
      let computationAudit = null;
      if (table === COMPUTATION_OF_POINTS_TABLE) {
        const current = await client.query(
          `SELECT * FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
          [id],
        );
        if (!current.rowCount) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Not found' });
        }
        const diff = diffComputationOfPoints(current.rows[0], payload);
        if (diff) {
          let signature = computationSignatureStateFromSlot(null);
          try {
            const slot = await client.query(
              `SELECT assigned_signer_id, signature_asset_id, signed_at, signer_name_snapshot
               FROM docutracker_rsp_source_signatures
               WHERE source_table = $1 AND source_record_id = $2::uuid AND slot_key = 'prepared_by'`,
              [COMPUTATION_OF_POINTS_TABLE, id],
            );
            signature = computationSignatureStateFromSlot(slot.rows[0]);
          } catch (slotErr) {
            if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
          }
          const actor = await client.query(
            `SELECT full_name FROM users WHERE id = $1::uuid`,
            [req.user.id],
          );
          computationAudit = buildComputationContentEditAudit({
            recordId: id,
            actorId: req.user.id,
            actorName: actor.rows[0]?.full_name || null,
            diff,
            signature,
          });
        }
      }
      let tatAudit = null;
      if (table === TURN_AROUND_TIME_TABLE) {
        const current = await client.query(
          `SELECT * FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
          [id],
        );
        if (!current.rowCount) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Not found' });
        }
        const diff = diffTurnAroundTime(current.rows[0], payload);
        let signatureRows = [];
        if (diff) {
          try {
            const slots = await client.query(
              `SELECT slot_key, assigned_signer_id, signed_by, signer_name_snapshot,
                      signed_at, signature_asset_id
               FROM docutracker_rsp_source_signatures
               WHERE source_table = $1 AND source_record_id = $2::uuid
               ORDER BY slot_key
               FOR UPDATE`,
              [TURN_AROUND_TIME_TABLE, id],
            );
            signatureRows = slots.rows;
          } catch (slotErr) {
            if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
          }
          const plan = planTatRevision({ diff, signatureRows });
          if (plan.clearSlotKeys.length > 0) {
            await client.query(
              `UPDATE docutracker_rsp_source_signatures
               SET signature_asset_id = NULL,
                   signed_by = NULL,
                   signer_name_snapshot = NULL,
                   signed_at = NULL,
                   updated_at = now()
               WHERE source_table = $1
                 AND source_record_id = $2::uuid
                 AND slot_key = ANY($3::text[])`,
              [TURN_AROUND_TIME_TABLE, id, plan.clearSlotKeys],
            );
          }
          const actor = await client.query(
            `SELECT full_name FROM users WHERE id = $1::uuid`,
            [req.user.id],
          );
          tatAudit = buildTatContentEditAudit({
            recordId: id,
            actorId: req.user.id,
            actorName: actor.rows[0]?.full_name || null,
            diff,
            plan,
          });
        }
      }
      // Lock the profile row before reading signatures so a final signature
      // cannot commit between this check and the update.
      if (table === APPLICANTS_PROFILE_TABLE) {
        const lock = await readApplicantsProfileSignatureLock(client, id);
        if (!lock.found) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Not found' });
        }
        if (lock.locked) {
          await client.query('ROLLBACK');
          return res.status(409).json({ error: LOCKED_MESSAGE, code: LOCKED_CODE });
        }
      }
      const q = `UPDATE ${quoteIdent(table)} SET ${setClause} WHERE id = $${values.length} RETURNING *`;
      const result = await client.query(q, values);
      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }
      // Fill any still-missing automatic signature slots (does not override existing).
      await initializeCreatorSourceSignatures(client, req.user, table, id);
      const saved = table === APPLICANTS_PROFILE_TABLE
        ? (await annotateApplicantsProfileSignatureState(client, result.rows))[0]
        : result.rows[0];
      if (lineupAudit) {
        await writeGovernanceAudit(client, lineupAudit);
      }
      if (shouldRecordContentEdit(computationAudit, result.rowCount)) {
        await writeGovernanceAudit(client, computationAudit);
      }
      if (shouldRecordTatEdit(tatAudit, result.rowCount)) {
        await writeGovernanceAudit(client, tatAudit);
      }
      await client.query('COMMIT');
      return res.json(saved);
    } catch (inner) {
      try { await client.query('ROLLBACK'); } catch (_) {}
      throw inner;
    } finally {
      client.release();
    }
  } catch (err) {
    if (err.code === '42P01' || err.code === '42703') {
      return res.status(503).json({
        error: 'Form signatures are not initialized. Apply the latest DocuTracker migrations.',
      });
    }
    console.error('[rspLdSavedEntries PUT]', err);
    const hint = pgErrorHint(err);
    return res.status(500).json({
      error: hint ? `Failed to update record (${hint})` : 'Failed to update record',
    });
  }
});

router.delete('/:table/:id', async (req, res) => {
  const { table, id } = req.params;
  if (!isAllowedTable(table)) {
    return res.status(400).json({ error: 'Unknown table' });
  }
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'Invalid id' });
  }
  let client;
  try {
    await ensureRspLdSavedEntryTables();
    if (table === APPLICANTS_PROFILE_TABLE) {
      client = await pool.connect();
      await client.query('BEGIN');
      const lock = await readApplicantsProfileSignatureLock(client, id);
      if (!lock.found) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }
      if (lock.locked) {
        await client.query('ROLLBACK');
        return res.status(409).json({ error: LOCKED_MESSAGE, code: LOCKED_CODE });
      }
      const result = await client.query(
        `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`,
        [id]
      );
      await client.query('COMMIT');
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Not found' });
      }
      return res.status(204).send();
    }
    if (table === SELECTION_LINEUP_TABLE) {
      client = await pool.connect();
      await client.query('BEGIN');
      const current = await client.query(
        `SELECT id FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
        [id],
      );
      if (!current.rowCount) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }
      try {
        await client.query(
          `DELETE FROM docutracker_rsp_source_signatures
           WHERE source_table = $1 AND source_record_id = $2::uuid`,
          [SELECTION_LINEUP_TABLE, id],
        );
      } catch (slotErr) {
        if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
      }
      const result = await client.query(
        `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`,
        [id],
      );
      await client.query('COMMIT');
      if (!result.rowCount) return res.status(404).json({ error: 'Not found' });
      return res.status(204).send();
    }
    if (table === COMPUTATION_OF_POINTS_TABLE) {
      client = await pool.connect();
      await client.query('BEGIN');
      const current = await client.query(
        `SELECT id FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
        [id],
      );
      if (!current.rowCount) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }
      try {
        await client.query(
          `DELETE FROM docutracker_rsp_source_signatures
           WHERE source_table = $1 AND source_record_id = $2::uuid`,
          [COMPUTATION_OF_POINTS_TABLE, id],
        );
      } catch (slotErr) {
        if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
      }
      const result = await client.query(
        `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`,
        [id],
      );
      await client.query('COMMIT');
      if (!result.rowCount) return res.status(404).json({ error: 'Not found' });
      return res.status(204).send();
    }
    if (table === TURN_AROUND_TIME_TABLE) {
      client = await pool.connect();
      await client.query('BEGIN');
      const current = await client.query(
        `SELECT id FROM ${quoteIdent(table)} WHERE id = $1::uuid FOR UPDATE`,
        [id],
      );
      if (!current.rowCount) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }
      try {
        await client.query(
          `DELETE FROM docutracker_rsp_source_signatures
           WHERE source_table = $1 AND source_record_id = $2::uuid`,
          [TURN_AROUND_TIME_TABLE, id],
        );
      } catch (slotErr) {
        if (slotErr.code !== '42P01' && slotErr.code !== '42703') throw slotErr;
      }
      const result = await client.query(
        `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`,
        [id],
      );
      await client.query('COMMIT');
      if (!result.rowCount) return res.status(404).json({ error: 'Not found' });
      return res.status(204).send();
    }
    const q = `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`;
    const result = await pool.query(q, [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    return res.status(204).send();
  } catch (err) {
    if (client) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
      });
    }
    console.error('[rspLdSavedEntries DELETE]', err);
    return res.status(500).json({ error: 'Failed to delete record' });
  } finally {
    client?.release();
  }
});

module.exports = router;
