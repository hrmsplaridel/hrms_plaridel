'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {Client} = require('pg');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
const {resolveStepAssignees} = require('../src/services/docutrackerWorkflowService');
const url = process.env.APPROVAL_WORKFLOWS_TEST_DATABASE_URL;
const id = n => `22222222-2222-4222-8222-${String(n).padStart(12, '0')}`;

test('routing validation releases real PostgreSQL locks and filters saved inactive assignees', {skip: !url}, async () => {
  const db = new Client({connectionString: url});
  await db.connect();
  let restore;
  try {
    // Session-local tables shadow production names; no application records change.
    await db.query('SET search_path=pg_temp,pg_catalog');
    await db.query(`
      CREATE TEMP TABLE users(id uuid PRIMARY KEY, full_name text, is_active boolean, employment_status text);
      CREATE TEMP TABLE assignments(employee_id uuid,department_id uuid,is_active boolean,effective_from date,effective_to date);
      CREATE TEMP TABLE approval_workflow_document_types(document_type text,workflow_id uuid);
      CREATE TEMP TABLE docutracker_workflow_steps(
        id uuid PRIMARY KEY,document_type text,workflow_version int,step_order int,enabled boolean);
      CREATE TEMP TABLE docutracker_workflow_step_assignees(
        step_id uuid,user_id uuid,is_primary boolean,backup_rank int,is_enabled boolean,created_at timestamptz DEFAULT now());
    `);
    await db.query(`INSERT INTO users VALUES
      ($1,'Former Primary',false,'inactive'),($2,'First Backup',true,'active'),
      ($3,'Second Backup',true,'active'),($4,'Unconfigured Person',true,'active')`, [id(1), id(2), id(3), id(4)]);
    await db.query("INSERT INTO docutracker_workflow_steps VALUES($1,'purchaseRequest',1,1,true)", [id(10)]);
    for (const n of [1, 2, 3]) await db.query(
      'INSERT INTO docutracker_workflow_step_assignees(step_id,user_id,is_primary,backup_rank,is_enabled) VALUES($1,$2,$3,$4,true)',
      [id(10), id(n), n === 1, n === 1 ? null : n - 1],
    );
    const options = {documentType: 'purchaseRequest', workflowVersion: 1,
      stepConfig: {step_order: 1, assignee_source: 'specific_users', assignee_type: 'user', user_ids: [id(1), id(2), id(3)]}};
    assert.deepEqual(await resolveStepAssignees(db, options), [id(2), id(3)]);
    await db.query('UPDATE users SET is_active=false WHERE id=ANY($1::uuid[])', [[id(2), id(3)]]);
    await assert.rejects(resolveStepAssignees(db, options), {code: 'VALIDATION'});
    await assert.rejects(resolveStepAssignees(db, {...options, stepConfig: {...options.stepConfig, user_ids: [id(4)]}}), {code: 'VALIDATION'},
      'Do not resurrect stale JSON assignments when all normalized assignees are inactive');
    await db.query('UPDATE users SET is_active=true,employment_status=\'active\' WHERE id=$1', [id(2)]);
    assert.deepEqual(await resolveStepAssignees(db, {...options,
      stepConfig: {...options.stepConfig, step_order: 2, user_ids: [id(2)]}}), [id(2)], 'Legacy steps retain their active-user fallback');

    const calls = [];
    const connection = {query: async (sql, params) => {
      calls.push(sql);
      return db.query(sql, params);
    }, release() { calls.push('RELEASE'); }};
    restore = withMockedModule('../src/config/db', {pool: {connect: async () => connection}});
    clearModule('../src/routes/docutracker');
    const router = require('../src/routes/docutracker');
    const handler = router.stack.find(s => s.route?.path === '/routing-configs' && s.route.methods.post).route.stack.at(-1).handle;
    for (const failure of ['inactive', 'department']) {
      calls.length = 0;
      const res = {code: 200, status(code) {this.code = code; return this;}, json(body) {this.body = body; return this;}};
      await handler({user: {id: id(4)}, body: {document_type: 'purchaseRequest', steps: [{
        step_order: 1, assignee_type: 'user', assignee_source: 'specific_users', label: 'Review',
        user_ids: [failure === 'inactive' ? id(1) : id(2)], allowed_actions: ['approve'],
        ...(failure === 'department' ? {department_id: id(20)} : {}),
      }]}}, res);
      assert.equal(res.code, 400);
      assert.match(res.body.error, failure === 'inactive' ? /inactive/ : /selected department/);
      assert.ok(calls.indexOf('ROLLBACK') >= 0 && calls.indexOf('ROLLBACK') < calls.indexOf('RELEASE'));
      const locks = await db.query("SELECT count(*)::int AS n FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory'");
      assert.equal(locks.rows[0].n, 0, 'A rejected save must release its transaction-scoped routing lock');
    }
  } finally {
    clearModule('../src/routes/docutracker');
    restore?.();
    await db.query('ROLLBACK');
    await db.end();
  }
});
