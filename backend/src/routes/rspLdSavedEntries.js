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
  selection_lineup_entries: ['applicants'],
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
    CREATE TABLE IF NOT EXISTS public.idp_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    CREATE TABLE IF NOT EXISTS public.applicants_profile_entries (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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

  rspLdSavedEntryTablesReady = true;
}

router.use(authMiddleware, requireAdmin);

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
  const keys = Object.keys(payload);
  if (keys.length === 0) {
    return res.status(400).json({ error: 'Empty body' });
  }
  try {
    await ensureRspLdSavedEntryTables();
    const jsonbSet = new Set(TABLE_JSONB_COLUMNS[table] || []);
    const colsList = keys.map((k) => quoteIdent(k)).join(', ');
    const phList = keys
      .map((k, i) => (jsonbSet.has(k) ? `$${i + 1}::jsonb` : `$${i + 1}`))
      .join(', ');
    const values = keys.map((k) => payload[k]);
    const q = `INSERT INTO ${quoteIdent(table)} (${colsList}) VALUES (${phList}) RETURNING *`;
    const result = await pool.query(q, values);
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
      });
    }
    console.error('[rspLdSavedEntries POST]', err);
    const hint = pgErrorHint(err);
    return res.status(500).json({
      error: hint ? `Failed to save record (${hint})` : 'Failed to save record',
    });
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
    const q = `UPDATE ${quoteIdent(table)} SET ${setClause} WHERE id = $${values.length} RETURNING *`;
    const result = await pool.query(q, values);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
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
  try {
    await ensureRspLdSavedEntryTables();
    const q = `DELETE FROM ${quoteIdent(table)} WHERE id = $1 RETURNING id`;
    const result = await pool.query(q, [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not found' });
    }
    return res.status(204).send();
  } catch (err) {
    if (err.code === '42P01') {
      return res.status(503).json({
        error: 'Form table not found in database. Run init-schema.sql.',
      });
    }
    console.error('[rspLdSavedEntries DELETE]', err);
    return res.status(500).json({ error: 'Failed to delete record' });
  }
});

module.exports = router;
