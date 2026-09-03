'use strict';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule } = require('./helpers/moduleMocks');

const {
  PositionValidationError,
  normalizePositionWrite,
} = require('../src/services/positionValidation');

const DEPARTMENT_ID = '33333333-3333-4333-8333-333333333333';

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

async function invokeCreateRoute(pool, body) {
  const restoreDb = withMockedModule('../src/config/db', { pool });
  const routePath = require.resolve('../src/routes/positions');
  delete require.cache[routePath];
  try {
    const router = require('../src/routes/positions');
    const layer = router.stack.find(
      (entry) => entry.route?.path === '/' && entry.route.methods.post
    );
    const handler = layer.route.stack[layer.route.stack.length - 1].handle;
    const res = responseRecorder();
    await handler(
      { body, user: { id: '11111111-1111-4111-8111-111111111111', role: 'admin' } },
      res
    );
    return res;
  } finally {
    delete require.cache[routePath];
    restoreDb();
  }
}

test('position creation trims values and supplies safe defaults', () => {
  assert.deepEqual(
    normalizePositionWrite(
      {
        name: '  Administrative Assistant  ',
        description: '  Records support  ',
        department_id: DEPARTMENT_ID.toUpperCase(),
      },
      { creating: true }
    ),
    {
      name: 'Administrative Assistant',
      description: 'Records support',
      department_id: DEPARTMENT_ID,
      is_department_head: false,
      is_active: true,
    }
  );
});

test('position updates preserve valid explicit values', () => {
  assert.deepEqual(
    normalizePositionWrite({
      description: null,
      department_id: null,
      is_department_head: false,
      is_active: false,
      department_head_period_id: null,
      department_head_effective_from: null,
      department_head_effective_to: '2026-09-30',
    }),
    {
      description: null,
      department_id: null,
      is_department_head: false,
      is_active: false,
      department_head_period_id: null,
      department_head_effective_from: null,
      department_head_effective_to: '2026-09-30',
    }
  );
});

test('position name must be nonblank text within its length limit', () => {
  for (const name of ['', '   ', null, 42, false]) {
    assert.throws(
      () => normalizePositionWrite({ name }),
      PositionValidationError
    );
  }
  assert.throws(
    () => normalizePositionWrite({ name: 'x'.repeat(201) }),
    /must not exceed 200 characters/
  );
});

test('position creation requires a name', () => {
  assert.throws(
    () => normalizePositionWrite({}, { creating: true }),
    /Position name must be a text value/
  );
});

test('position Boolean fields accept only real Booleans', () => {
  for (const field of ['is_active', 'is_department_head']) {
    for (const value of ['false', 'true', 0, 1, null]) {
      assert.throws(
        () => normalizePositionWrite({ [field]: value }),
        new RegExp(`${field} must be a Boolean value`)
      );
    }
  }
});

test('position description accepts only bounded text or null', () => {
  assert.throws(
    () => normalizePositionWrite({ description: 123 }),
    /Description must be a text value or null/
  );
  assert.throws(
    () => normalizePositionWrite({ description: 'x'.repeat(2001) }),
    /must not exceed 2000 characters/
  );
});

test('position identifiers accept only UUID strings or null', () => {
  for (const field of ['department_id', 'department_head_period_id']) {
    for (const value of ['', 'not-a-uuid', 42, false]) {
      assert.throws(
        () => normalizePositionWrite({ [field]: value }),
        new RegExp(`${field} must be a valid UUID or null`)
      );
    }
  }
});

test('Department Head dates require valid ISO calendar dates', () => {
  for (const value of ['', '09/01/2026', '2026-02-30', 20260901]) {
    assert.throws(
      () => normalizePositionWrite({ department_head_effective_from: value }),
      PositionValidationError
    );
  }
});

test('position schemas enforce blank-name and normalized uniqueness rules', () => {
  const initSchema = fs.readFileSync(
    path.join(__dirname, '../scripts/init-schema.sql'),
    'utf8'
  );
  const migration = fs.readFileSync(
    path.join(
      __dirname,
      '../scripts/migrations/dtr/20260901_position_name_integrity.sql'
    ),
    'utf8'
  );

  for (const sql of [initSchema, migration]) {
    assert.match(sql, /chk_positions_name_not_blank/);
    assert.match(sql, /uq_positions_name_department_ci/);
    assert.match(sql, /LOWER\(BTRIM\(name\)\)/);
    assert.match(sql, /COALESCE\(department_id/);
  }
});

test('position route returns 400 for a string Boolean without opening a transaction', async () => {
  let connected = false;
  const res = await invokeCreateRoute(
    {
      async connect() {
        connected = true;
        throw new Error('Database must not be reached');
      },
    },
    { name: 'Accountant', is_active: 'false' }
  );

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /is_active must be a Boolean value/);
  assert.equal(connected, false);
});

test('position route returns 409 for a normalized name conflict', async () => {
  const calls = [];
  let released = false;
  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    const res = await invokeCreateRoute(
      {
        async connect() {
          return {
            async query(sql) {
              const text = String(sql).trim();
              calls.push(text);
              if (text === 'BEGIN' || text === 'ROLLBACK') {
                return { rowCount: 0, rows: [] };
              }
              if (text.startsWith('INSERT INTO positions')) {
                const error = new Error('duplicate');
                error.code = '23505';
                error.constraint = 'uq_positions_name_department_ci';
                throw error;
              }
              throw new Error(`Unexpected SQL: ${text}`);
            },
            release() {
              released = true;
            },
          };
        },
      },
      { name: 'accountant', is_active: true }
    );

    assert.equal(res.statusCode, 409);
    assert.match(res.body.error, /already exists/i);
    assert.equal(calls.at(-1), 'ROLLBACK');
    assert.equal(released, true);
  } finally {
    console.error = originalConsoleError;
  }
});
