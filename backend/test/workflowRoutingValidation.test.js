'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const engine = require('../src/services/approvalWorkflows');

const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const primary = id(1), backup = id(2), mayor = id(3), admin = id(4);
const step = (order, ids = [primary]) => ({
  step_order: order, label: `Review ${order}`, assignee_type: 'user',
  assignee_source: 'specific_users', user_ids: ids, enabled: true,
  requires_signature: true, allowed_actions: ['approve', 'return', 'reject'],
});
const response = () => ({
  code: 200, status(code) { this.code = code; return this; },
  json(body) { this.body = body; return this; },
});

async function withNativeRouter(query, run) {
  const calls = [];
  const db = {
    query: async (sql, params = []) => {
      calls.push({sql, params});
      return query(sql, params);
    },
    release() { calls.push({sql: 'RELEASE'}); },
  };
  const restore = withMockedModule('../src/config/db', {pool: {connect: async () => db}});
  clearModule('../src/routes/docutracker');
  try {
    const router = require('../src/routes/docutracker');
    const handler = router.stack.find(s => s.route?.path === '/routing-configs' && s.route.methods.post).route.stack.at(-1).handle;
    await run(handler, calls);
  } finally {
    clearModule('../src/routes/docutracker');
    restore();
  }
}

for (const failure of ['inactive reviewer', 'wrong department']) {
  test(`native routing rolls back ${failure} before releasing the connection`, async () => {
    await withNativeRouter(async sql => {
      if (sql.includes('FROM users') && !sql.includes('JOIN assignments')) {
        const rows = failure === 'inactive reviewer' ? [] : [{id: primary}];
        return {rows, rowCount: rows.length};
      }
      return {rows: [], rowCount: 0};
    }, async (handler, calls) => {
      const res = response();
      await handler({user: {id: admin}, body: {document_type: 'purchaseRequest', steps: [
        {...step(1), ...(failure === 'wrong department' ? {department_id: id(5)} : {})},
      ]}}, res);
      assert.equal(res.code, 400);
      assert.match(res.body.error, failure === 'inactive reviewer' ? /inactive/ : /selected department/);
      const sql = calls.map(c => c.sql);
      assert.ok(sql.includes('BEGIN'));
      assert.ok(sql.some(s => s.includes('pg_advisory_xact_lock')));
      assert.ok(sql.indexOf('ROLLBACK') > sql.indexOf('BEGIN'), 'Validation must end the transaction');
      assert.ok(sql.indexOf('ROLLBACK') < sql.indexOf('RELEASE'));
      assert.ok(!sql.some(s => /INSERT INTO docutracker_routing_config_versions/.test(s)));
    });
  });
}

test('publishing rejects impossible selected-person steps before writing a version', async () => {
  const calls = [];
  const query = async (sql, params = []) => {
    calls.push(sql);
    if (sql.startsWith('SELECT id FROM users')) return {rows: params[0].map(id => ({id}))};
    if (sql.startsWith('INSERT INTO approval_workflows')) return {rows: [{id: id(10), current_version: 1}]};
    return {rows: []};
  };
  const restore = withMockedModule('../src/config/db', {pool: {connect: async () => ({query, release() {}})}});
  clearModule('../src/routes/approvalWorkflows');
  try {
    const router = require('../src/routes/approvalWorkflows');
    const handler = router.stack.find(s => s.route?.path === '/' && s.route.methods.post).route.stack.at(-1).handle;
    const res = response();
    await handler({user: {id: admin}, params: {}, body: {
      name: 'Impossible route', steps: [step(1), step(2)],
    }}, res);
    assert.equal(res.code, 400);
    assert.match(res.body.error, /different.*reviewer|distinct.*reviewer/i);
    assert.ok(!calls.some(s => /INSERT INTO approval_workflow/.test(s)));
  } finally {
    clearModule('../src/routes/approvalWorkflows');
    restore();
  }
});

test('selected-person validation uses all primary/backup combinations and preserves dynamic steps', () => {
  assert.throws(() => engine.normalizeWorkflow({name: 'Three steps, two people', steps: [
    step(1, [primary, backup]), step(2, [primary, backup]), step(3, [backup]),
  ]}), {statusCode: 400});
  // Greedy assignment would incorrectly use primary at step 1 and block step 2.
  assert.doesNotThrow(() => engine.normalizeWorkflow({name: 'Use a backup first', steps: [
    step(1, [primary, backup]), step(2, [primary]),
    {...step(3), assignee_source: 'final_hr_reviewers', user_ids: []},
  ]}));
});

function publishDb(calls) {
  return {query: async (sql, params = []) => {
    calls.push({sql, params});
    if (sql.startsWith('SELECT id FROM users')) return {rows: params[0].map(id => ({id}))};
    if (sql.includes('MAX(version)')) return {rows: [{next_version: 1}]};
    if (sql.includes('INSERT INTO docutracker_workflow_steps')) return {rows: [{id: id(11)}]};
    return {rows: [], rowCount: 0};
  }};
}

for (const source of ['specific_users', 'final_hr_reviewers']) {
  test(`Memo linking rejects a ${source} final step that excludes the Mayor`, async () => {
    const restore = withMockedModule('../src/services/officialSignatoryService', {
      resolveActiveMayor: async () => ({employee_id: mayor}),
    });
    const calls = [];
    try {
      await assert.rejects(require('../src/services/sharedDocumentWorkflows').publishDocumentVersion(
        publishDb(calls), 'memo', {id: id(10), version: 1, is_active: true,
          steps: [{...step(1), assignee_source: source, user_ids: source === 'specific_users' ? [primary] : []}]}, admin,
      ), error => error.statusCode === 400 && /Mayor/.test(error.message));
      assert.ok(!calls.some(c => /INSERT INTO/.test(c.sql)), 'Do not publish or link an unusable version');
    } finally { restore(); }
  });
}

test('Memo linking supports current-Mayor routing and selected people including the active Mayor', async () => {
  const restore = withMockedModule('../src/services/officialSignatoryService', {
    resolveActiveMayor: async () => ({employee_id: mayor}),
  });
  try {
    for (const finalStep of [
      {...step(1), assignee_source: 'active_mayor', user_ids: []},
      step(1, [primary, mayor]),
    ]) {
      const calls = [];
      const version = await require('../src/services/sharedDocumentWorkflows').publishDocumentVersion(
        publishDb(calls), 'memo', {id: id(10), version: 1, is_active: true, steps: [finalStep]}, admin,
      );
      assert.equal(version, 1);
      assert.ok(calls.some(c => /INSERT INTO approval_workflow_document_types/.test(c.sql)));
    }
    const calls = [];
    assert.equal(await require('../src/services/sharedDocumentWorkflows').publishDocumentVersion(
      publishDb(calls), 'purchaseRequest', {id: id(10), version: 1, is_active: true, steps: [step(1)]}, admin,
    ), 1);
  } finally { restore(); }
});

test('editing a linked Memo workflow cannot remove its Mayor final step', async () => {
  const restore = withMockedModule('../src/services/officialSignatoryService', {
    resolveActiveMayor: async () => ({employee_id: mayor}),
  });
  const calls = [];
  const db = publishDb(calls);
  const query = db.query;
  db.query = async (sql, params) => {
    if (sql.startsWith('SELECT document_type,workflow_version')) return {rows: [{document_type: 'memo', workflow_version: 1}]};
    if (sql.startsWith('SELECT workflow_id')) return {rows: [{workflow_id: id(10), workflow_version: 1}]};
    return query(sql, params);
  };
  try {
    await assert.rejects(require('../src/services/sharedDocumentWorkflows').syncLinkedDocumentWorkflows(
      db, {id: id(10), version: 2, is_active: true, steps: [step(1)]}, admin,
    ), error => error.statusCode === 400 && /Mayor/.test(error.message));
    assert.ok(!calls.some(c => /INSERT INTO/.test(c.sql)));
  } finally { restore(); }
});

test('native Memo publishing rejects a final reviewer who cannot issue the Memo', async () => {
  const restore = withMockedModule('../src/services/officialSignatoryService', {
    resolveActiveMayor: async () => ({employee_id: mayor}),
  });
  try {
    await withNativeRouter(async (sql, params) => {
      if (sql.includes('FROM users')) return {rows: [{id: primary}], rowCount: 1};
      if (sql.includes('MAX(version)')) return {rows: [{next_version: 1}], rowCount: 1};
      if (sql.includes('INSERT INTO docutracker_routing_config_versions')) return {
        rows: [{document_type: 'memo', version: 1, steps: JSON.parse(params[2])}], rowCount: 1,
      };
      if (sql.includes('INSERT INTO docutracker_workflow_steps')) return {rows: [{id: id(11)}], rowCount: 1};
      return {rows: [], rowCount: 0};
    }, async (handler, calls) => {
      const res = response();
      await handler({user: {id: admin}, body: {document_type: 'memo', steps: [step(1)]}}, res);
      assert.equal(res.code, 400);
      assert.match(res.body.error, /Mayor/);
      assert.ok(calls.some(c => c.sql === 'ROLLBACK'));
      assert.ok(!calls.some(c => /INSERT INTO/.test(c.sql)));
    });
  } finally { restore(); }
});

for (const state of ['backup active', 'all inactive']) {
  test(`saved DocuTracker assignments recheck account eligibility: ${state}`, async () => {
    const db = {query: async (sql, params) => {
      if (sql.includes('FROM docutracker_workflow_steps s')) {
        // Model the SQL's users join: old queries return the stale primary too.
        const checksActive = /JOIN users/.test(sql) && /u\.is_active/.test(sql);
        const rows = checksActive
          ? (state === 'backup active' ? [{user_id: backup}] : [])
          : [{user_id: primary}, {user_id: backup}];
        return {rows, rowCount: rows.length};
      }
      if (sql.includes('SELECT id FROM docutracker_workflow_steps')) return {rows: [{id: id(11)}], rowCount: 1};
      if (sql.includes('FROM users')) {
        const active = state === 'backup active' && params[0] === backup;
        return {rows: active ? [{id: backup}] : [], rowCount: active ? 1 : 0};
      }
      throw Error(`Unexpected SQL: ${sql}`);
    }};
    const resolve = () => require('../src/services/docutrackerWorkflowService').resolveStepAssignees(db, {
      stepConfig: step(1, [primary, backup]), documentType: 'purchaseRequest', workflowVersion: 1,
    });
    if (state === 'backup active') assert.deepEqual(await resolve(), [backup]);
    else await assert.rejects(resolve(), error => error.code === 'VALIDATION' && /active assignee/i.test(error.message));
  });
}

test('no eligible normalized assignment cannot fall back to a different legacy JSON reviewer', async () => {
  const calls = [];
  const db = {query: async sql => {
    calls.push(sql);
    if (sql.includes('SELECT id FROM docutracker_workflow_steps')) return {rows: [{id: id(11)}], rowCount: 1};
    if (sql.includes('FROM users')) return {rows: [{id: backup}], rowCount: 1};
    return {rows: [], rowCount: 0};
  }};
  await assert.rejects(require('../src/services/docutrackerWorkflowService').resolveStepAssignees(db, {
    stepConfig: step(1, [backup]), documentType: 'purchaseRequest', workflowVersion: 1,
  }), {code: 'VALIDATION'});
  assert.ok(!calls.some(sql => sql.includes('FROM users')), 'Normalized assignments must remain authoritative');
});
