const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  EMPLOYEE_SCHEMA_SOURCE,
  EmployeeSchemaValidationError,
  REQUIRED_EMPLOYEE_COLUMNS,
  REQUIRED_EMPLOYEE_INDEXES,
  validateEmployeeSchema,
} = require('../src/services/employeeSchemaValidation');

function schemaDb({ columns = REQUIRED_EMPLOYEE_COLUMNS, indexes = REQUIRED_EMPLOYEE_INDEXES } = {}) {
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

test('accepts a complete employee schema', async () => {
  const result = await validateEmployeeSchema(schemaDb());
  assert.equal(result.columns, REQUIRED_EMPLOYEE_COLUMNS.length);
  assert.equal(result.indexes, REQUIRED_EMPLOYEE_INDEXES.length);
});

test('reports missing employee columns and indexes with the schema source', async () => {
  await assert.rejects(
    validateEmployeeSchema(
      schemaDb({
        columns: REQUIRED_EMPLOYEE_COLUMNS.filter(
          (column) => column !== 'leave_credit_eligible_until'
        ),
        indexes: [],
      })
    ),
    (error) => {
      assert.ok(error instanceof EmployeeSchemaValidationError);
      assert.equal(error.code, 'EMPLOYEE_SCHEMA_OUTDATED');
      assert.deepEqual(error.missingColumns, ['leave_credit_eligible_until']);
      assert.deepEqual(error.missingIndexes, REQUIRED_EMPLOYEE_INDEXES);
      assert.match(error.message, new RegExp(EMPLOYEE_SCHEMA_SOURCE));
      return true;
    }
  );
});

test('schema validation uses read-only catalog queries', async () => {
  const sql = [];
  const db = {
    query: async (statement) => {
      sql.push(statement);
      return sql.length === 1
        ? {
            rows: REQUIRED_EMPLOYEE_COLUMNS.map((column_name) => ({
              column_name,
            })),
          }
        : {
            rows: REQUIRED_EMPLOYEE_INDEXES.map((indexname) => ({ indexname })),
          };
    },
  };

  await validateEmployeeSchema(db);
  assert.equal(sql.length, 2);
  for (const statement of sql) {
    assert.doesNotMatch(statement, /\b(?:ALTER|CREATE|DROP)\b/i);
  }
});

test('employee and profile request routes contain no users-table DDL', () => {
  for (const route of ['employees.js', 'auth.js']) {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../src/routes', route),
      'utf8'
    );
    assert.doesNotMatch(source, /ALTER\s+TABLE\s+users/i);
    assert.doesNotMatch(source, /ensureEmployeeProfileColumns/);
    assert.doesNotMatch(source, /ensurePersonalInfoColumns/);
  }
});
