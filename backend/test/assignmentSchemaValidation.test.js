const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  ASSIGNMENT_SCHEMA_SOURCE,
  AssignmentSchemaValidationError,
  REQUIRED_ADDITIONAL_POSITION_COLUMNS,
  REQUIRED_ADDITIONAL_POSITION_INDEXES,
  validateAssignmentSchema,
} = require('../src/services/assignmentSchemaValidation');

function schemaDb({
  columns = REQUIRED_ADDITIONAL_POSITION_COLUMNS,
  indexes = REQUIRED_ADDITIONAL_POSITION_INDEXES,
} = {}) {
  let queryIndex = 0;
  return {
    query: async () => {
      queryIndex += 1;
      return queryIndex === 1
        ? { rows: columns.map((column_name) => ({ column_name })) }
        : { rows: indexes.map((indexname) => ({ indexname })) };
    },
  };
}

test('accepts a complete additional-position schema', async () => {
  const result = await validateAssignmentSchema(schemaDb());

  assert.equal(result.columns, REQUIRED_ADDITIONAL_POSITION_COLUMNS.length);
  assert.equal(result.indexes, REQUIRED_ADDITIONAL_POSITION_INDEXES.length);
});

test('reports missing additional-position schema with the authoritative source', async () => {
  await assert.rejects(
    validateAssignmentSchema(schemaDb({ columns: [], indexes: [] })),
    (error) => {
      assert.ok(error instanceof AssignmentSchemaValidationError);
      assert.equal(error.code, 'ASSIGNMENT_SCHEMA_OUTDATED');
      assert.deepEqual(error.missingColumns, REQUIRED_ADDITIONAL_POSITION_COLUMNS);
      assert.deepEqual(error.missingIndexes, REQUIRED_ADDITIONAL_POSITION_INDEXES);
      assert.match(error.message, new RegExp(ASSIGNMENT_SCHEMA_SOURCE));
      return true;
    }
  );
});

test('assignment startup schema validation uses read-only catalog queries', async () => {
  const statements = [];
  const db = {
    async query(statement) {
      statements.push(statement);
      return statements.length === 1
        ? {
            rows: REQUIRED_ADDITIONAL_POSITION_COLUMNS.map((column_name) => ({
              column_name,
            })),
          }
        : {
            rows: REQUIRED_ADDITIONAL_POSITION_INDEXES.map((indexname) => ({
              indexname,
            })),
          };
    },
  };

  await validateAssignmentSchema(db);

  assert.equal(statements.length, 2);
  for (const statement of statements) {
    assert.doesNotMatch(statement, /\b(?:CREATE|ALTER|DROP)\b/i);
  }
});

test('main schema owns the complete additional-position table and indexes', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../scripts/init-schema.sql'),
    'utf8'
  );
  const table = source.match(
    /CREATE TABLE IF NOT EXISTS employee_other_positions\s*\(([\s\S]*?)\n\);/i
  );
  assert.ok(table, 'employee_other_positions must exist in init-schema.sql');

  for (const column of REQUIRED_ADDITIONAL_POSITION_COLUMNS) {
    assert.match(
      table[1],
      new RegExp(`^\\s*${column}\\s+`, 'mi'),
      `${column} must be defined on employee_other_positions`
    );
  }
  assert.match(table[1], /CONSTRAINT\s+chk_employee_other_position_dates/i);
  for (const index of [
    ...REQUIRED_ADDITIONAL_POSITION_INDEXES,
    'idx_employee_other_positions_duplicate_lookup',
  ]) {
    assert.match(
      source,
      new RegExp(`CREATE\\s+INDEX\\s+IF\\s+NOT\\s+EXISTS\\s+${index}\\b`, 'i')
    );
  }
});

test('runtime assignment and leave routes do not create additional-position schema', () => {
  const assignmentRoute = fs.readFileSync(
    path.resolve(__dirname, '../src/routes/employeeOtherPositions.js'),
    'utf8'
  );
  const leaveRoute = fs.readFileSync(
    path.resolve(__dirname, '../src/routes/leaveRoutes.js'),
    'utf8'
  );
  const schemaDdl = /\b(?:CREATE|ALTER|DROP)\s+(?:EXTENSION|TABLE|INDEX|SCHEMA|SEQUENCE|TYPE)\b/i;
  const tableDdl = /\b(?:CREATE|ALTER|DROP)\s+(?:TABLE|INDEX)\b[^;`]*employee_other_positions/i;

  assert.doesNotMatch(assignmentRoute, schemaDdl);
  assert.doesNotMatch(assignmentRoute, /ensureEmployeeOtherPositionsTable/);
  assert.doesNotMatch(leaveRoute, tableDdl);
  assert.doesNotMatch(leaveRoute, /ensureEmployeeOtherPositionsTable/);
});
