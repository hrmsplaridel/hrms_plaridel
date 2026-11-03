const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CHECKS,
  DTR_PRIMARY_REVIEWER_MIGRATION,
  evaluateDocuTrackerSchema,
  formatPreflightReport,
  preflightExitCode,
} = require('../scripts/check-docutracker-schema');

function completeCatalog() {
  const tables = new Set();
  const columns = [];
  const constraints = [];
  const indexes = [];
  for (const check of CHECKS) {
    if (check.kind === 'table') tables.add(check.name);
    if (check.kind === 'column') {
      tables.add(check.table);
      columns.push({ table: check.table, column: check.name });
    }
    if (check.kind === 'constraint') {
      constraints.push({ name: check.name, definition: check.includes || '' });
    }
    if (check.kind === 'index') indexes.push(check.name);
  }
  return { tables: [...tables], columns, constraints, indexes };
}

test('complete DocuTracker schema preflight passes', () => {
  const result = evaluateDocuTrackerSchema(completeCatalog());
  assert.equal(result.ok, true);
  assert.equal(preflightExitCode(result), 0);
  assert.equal(formatPreflightReport(result), 'DocuTracker schema preflight: OK\n');
});

test('a missing primary reviewer table fails and names the DTR migration', () => {
  const catalog = completeCatalog();
  catalog.tables = catalog.tables.filter((name) => name !== 'primary_reviewer_designations');
  const result = evaluateDocuTrackerSchema(catalog);
  const report = formatPreflightReport(result);
  assert.equal(result.ok, false);
  assert.equal(preflightExitCode(result), 1);
  assert.equal(report.includes('DocuTracker schema preflight: FAILED'), true);
  assert.equal(report.includes('Missing table: primary_reviewer_designations'), true);
  assert.equal(report.includes(DTR_PRIMARY_REVIEWER_MIGRATION), true);
  assert.equal(report.includes('does not create it'), true);
  assert.equal(report.includes('DocuTracker schema preflight: OK'), false);
});

test('a missing assignee_source column fails without a database', () => {
  const catalog = completeCatalog();
  catalog.columns = catalog.columns.filter((column) => column.column !== 'assignee_source');
  const result = evaluateDocuTrackerSchema(catalog);
  assert.equal(preflightExitCode(result), 1);
  assert.match(
    formatPreflightReport(result),
    /Missing column: docutracker_workflow_steps\.assignee_source/,
  );
});
