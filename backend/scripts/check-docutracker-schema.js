'use strict';

/**
 * Read-only DocuTracker schema preflight.
 *
 * Connects with the same DATABASE_URL / pool options as the API and runs
 * SELECT queries against PostgreSQL catalogs. It does not insert, update,
 * delete, or change schema, and it does not run migrations.
 *
 * Usage (from backend/):
 *   node scripts/check-docutracker-schema.js
 */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { Pool } = require('pg');
const { buildPoolOptions } = require('../src/config/databasePoolOptions');

const DTR_PRIMARY_REVIEWER_MIGRATION =
  'backend/scripts/migrations/dtr/20261009_employee_primary_reviewers.sql';

const PRIMARY_REVIEWER_RECOMMENDATION = [
  `Older databases must apply this DTR migration manually: ${DTR_PRIMARY_REVIEWER_MIGRATION}`,
  'Fresh databases receive the table from backend/scripts/init-schema.sql.',
  'DocuTracker depends on the table and does not create it. This check does not run the migration.',
].join('\n');

/** Objects current DocuTracker code requires. Unused improved-schema tables are omitted. */
const CHECKS = [
  {
    kind: 'table',
    name: 'primary_reviewer_designations',
    recommendation: PRIMARY_REVIEWER_RECOMMENDATION,
  },
  { kind: 'table', name: 'department_reviewer_backups' },
  { kind: 'table', name: 'leave_request_department_reviewers' },
  { kind: 'table', name: 'locator_slip_department_reviewers' },
  { kind: 'table', name: 'docutracker_permissions' },
  { kind: 'table', name: 'docutracker_documents' },
  { kind: 'table', name: 'docutracker_document_types' },
  { kind: 'table', name: 'docutracker_workflow_steps' },
  { kind: 'table', name: 'docutracker_workflow_step_assignees' },
  { kind: 'table', name: 'docutracker_signature_fields' },
  { kind: 'column', table: 'docutracker_workflow_steps', name: 'assignee_source' },
  { kind: 'column', table: 'docutracker_signature_fields', name: 'signer_position_snapshot' },
  { kind: 'column', table: 'docutracker_signature_fields', name: 'signer_role_snapshot' },
  { kind: 'column', table: 'docutracker_documents', name: 'release_required' },
  { kind: 'column', table: 'docutracker_documents', name: 'released_to_department_id' },
  { kind: 'column', table: 'docutracker_documents', name: 'released_to_department_name' },
  { kind: 'column', table: 'docutracker_documents', name: 'released_by' },
  { kind: 'column', table: 'docutracker_documents', name: 'released_by_name' },
  { kind: 'column', table: 'docutracker_documents', name: 'released_at' },
  { kind: 'column', table: 'docutracker_documents', name: 'release_remarks' },
  { kind: 'column', table: 'docutracker_document_types', name: 'requires_release' },
  {
    kind: 'constraint',
    name: 'primary_reviewer_no_overlap',
    recommendation: PRIMARY_REVIEWER_RECOMMENDATION,
  },
  { kind: 'constraint', name: 'department_reviewer_backup_rank_no_overlap' },
  { kind: 'constraint', name: 'department_reviewer_employee_no_overlap' },
  { kind: 'constraint', name: 'docutracker_documents_release_native_check_v1' },
  { kind: 'constraint', name: 'docutracker_documents_release_state_check_v1' },
  { kind: 'constraint', name: 'docutracker_signature_fields_identity_snapshot_check_v1' },
  {
    kind: 'constraint',
    name: 'docutracker_workflow_steps_assignee_source_check',
    includes: 'submitter_department_reviewers',
  },
  { kind: 'index', name: 'idx_docutracker_documents_released_to_department' },
  { kind: 'index', name: 'idx_docutracker_documents_originating_department' },
];

function evaluateDocuTrackerSchema(catalog) {
  const tables = new Set(catalog.tables || []);
  const columns = new Set(
    (catalog.columns || []).map((column) => `${column.table}.${column.column}`),
  );
  const constraints = new Map(
    (catalog.constraints || []).map((constraint) => [
      constraint.name,
      constraint.definition || '',
    ]),
  );
  const indexes = new Set(catalog.indexes || []);
  const missing = [];

  for (const check of CHECKS) {
    if (check.kind === 'table') {
      if (!tables.has(check.name)) missing.push(check);
      continue;
    }
    if (check.kind === 'column') {
      if (!tables.has(check.table)) continue;
      if (!columns.has(`${check.table}.${check.name}`)) missing.push(check);
      continue;
    }
    if (check.kind === 'constraint') {
      if (!constraints.has(check.name)) {
        missing.push(check);
        continue;
      }
      const definition = constraints.get(check.name);
      if (check.includes && !definition.includes(check.includes)) {
        missing.push({ ...check, wrongDefinition: true });
      }
      continue;
    }
    if (check.kind === 'index' && !indexes.has(check.name)) missing.push(check);
  }

  return { ok: missing.length === 0, missing };
}

function preflightExitCode(result) {
  return result.ok ? 0 : 1;
}

function formatMissing(check) {
  if (check.kind === 'table') {
    const lines = [`Missing table: ${check.name}`];
    if (check.recommendation) lines.push(check.recommendation);
    return lines.join('\n');
  }
  if (check.kind === 'column') {
    return `Missing column: ${check.table}.${check.name}`;
  }
  if (check.kind === 'constraint' && check.wrongDefinition) {
    return `Constraint ${check.name} is present but does not include '${check.includes}'`;
  }
  if (check.kind === 'constraint') {
    const lines = [`Missing constraint: ${check.name}`];
    if (check.recommendation) lines.push(check.recommendation);
    return lines.join('\n');
  }
  return `Missing index: ${check.name}`;
}

function formatPreflightReport(result) {
  if (result.ok) return 'DocuTracker schema preflight: OK\n';
  return `DocuTracker schema preflight: FAILED\n${result.missing.map(formatMissing).join('\n')}\n`;
}

function names(kind) {
  return CHECKS.filter((check) => check.kind === kind).map((check) => check.name);
}

async function loadCatalog(client) {
  const tables = [...new Set([
    ...names('table'),
    ...CHECKS.filter((check) => check.kind === 'column').map((check) => check.table),
  ])];
  const columns = names('column');
  const constraints = names('constraint');
  const indexes = names('index');
  const tableRows = await client.query(
    `SELECT c.relname AS name
     FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = ANY($1::text[])`,
    [tables],
  );
  const columnRows = await client.query(
    `SELECT table_name, column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = ANY($1::text[])
       AND column_name = ANY($2::text[])`,
    [tables, columns],
  );
  const constraintRows = await client.query(
    `SELECT conname AS name, pg_get_constraintdef(oid) AS definition
     FROM pg_constraint
     WHERE conname = ANY($1::text[])`,
    [constraints],
  );
  const indexRows = await client.query(
    `SELECT indexname AS name
     FROM pg_indexes
     WHERE schemaname = 'public' AND indexname = ANY($1::text[])`,
    [indexes],
  );
  return {
    tables: tableRows.rows.map((row) => row.name),
    columns: columnRows.rows.map((row) => ({
      table: row.table_name,
      column: row.column_name,
    })),
    constraints: constraintRows.rows,
    indexes: indexRows.rows.map((row) => row.name),
  };
}

function safeMessage(error) {
  return String(error && error.message ? error.message : error)
    .replace(/postgres(?:ql)?:\/\/\S+/gi, '[redacted]');
}

async function main() {
  if (!process.env.DATABASE_URL) {
    console.error('DocuTracker schema preflight: FAILED');
    console.error('DATABASE_URL is not set. Use the backend .env used by the API.');
    process.exitCode = 1;
    return;
  }
  const pool = new Pool(buildPoolOptions());
  const client = await pool.connect();
  try {
    const result = evaluateDocuTrackerSchema(await loadCatalog(client));
    const report = formatPreflightReport(result);
    if (result.ok) console.log(report.trimEnd());
    else console.error(report.trimEnd());
    process.exitCode = preflightExitCode(result);
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error('DocuTracker schema preflight: FAILED');
    console.error(safeMessage(error));
    process.exitCode = 1;
  });
}

module.exports = {
  CHECKS,
  DTR_PRIMARY_REVIEWER_MIGRATION,
  evaluateDocuTrackerSchema,
  formatPreflightReport,
  preflightExitCode,
};
