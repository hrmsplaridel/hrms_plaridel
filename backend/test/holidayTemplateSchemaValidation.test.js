'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
const {
  REQUIRED_HOLIDAY_TEMPLATE_COLUMNS,
  REQUIRED_HOLIDAY_TEMPLATE_INDEXES,
  validateHolidayTemplateSchema,
} = require('../src/services/holidayTemplateSchemaValidation');

function completeColumnRows() {
  return Object.entries(REQUIRED_HOLIDAY_TEMPLATE_COLUMNS).flatMap(
    ([table_name, columns]) => columns.map((column_name) => ({ table_name, column_name }))
  );
}

test('holiday template startup validation accepts the provisioned schema', async () => {
  const db = {
    async query(sql) {
      if (String(sql).includes('information_schema.columns')) {
        return { rows: completeColumnRows() };
      }
      if (String(sql).includes('pg_indexes')) {
        return { rows: REQUIRED_HOLIDAY_TEMPLATE_INDEXES.map((indexname) => ({ indexname })) };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await validateHolidayTemplateSchema(db);
  assert.equal(result.columns, 22);
  assert.equal(result.indexes, 1);
});

test('holiday template startup validation reports missing schema objects', async () => {
  const rows = completeColumnRows().filter(
    (row) => !(row.table_name === 'holiday_default_template_items' && row.column_name === 'coverage')
  );
  const db = {
    async query(sql) {
      if (String(sql).includes('information_schema.columns')) return { rows };
      if (String(sql).includes('pg_indexes')) return { rows: [] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  await assert.rejects(
    validateHolidayTemplateSchema(db),
    (error) => {
      assert.equal(error.code, 'HOLIDAY_TEMPLATE_SCHEMA_OUTDATED');
      assert.deepEqual(error.missingColumns, ['holiday_default_template_items.coverage']);
      assert.deepEqual(error.missingIndexes, ['idx_holiday_default_template_items_template']);
      assert.match(error.message, /migrate-holiday-default-templates\.sql/);
      return true;
    }
  );
});

test('holiday template reads and listing execute read-only SQL', async () => {
  const statements = [];
  const pool = {
    async query(sql) {
      const text = String(sql).trim();
      statements.push(text);
      if (text.includes('FROM holiday_default_templates t')) {
        return { rows: [], rowCount: 0 };
      }
      if (text.startsWith('SELECT id, country_code')) {
        return { rows: [], rowCount: 0 };
      }
      if (text.startsWith('SELECT year')) {
        return { rows: [], rowCount: 0 };
      }
      throw new Error(`Unexpected query: ${text}`);
    },
  };
  const restore = withMockedModule('../src/config/db', { pool });
  const servicePath = '../src/services/holidayDefaultTemplates';
  clearModule(servicePath);
  try {
    const service = require(servicePath);
    await service.getHolidayDefaultTemplateYears();
    await service.listHolidayDefaultTemplates();
    await service.getHolidayDefaultTemplate(2026);

    assert.ok(statements.length > 0);
    assert.equal(
      statements.every((sql) => /^SELECT\b/i.test(sql)),
      true,
      `Expected SELECT-only template reads, received: ${statements.join(' | ')}`
    );
    assert.equal('ensureHolidayTemplateTables' in service, false);
  } finally {
    clearModule(servicePath);
    restore();
  }
});
