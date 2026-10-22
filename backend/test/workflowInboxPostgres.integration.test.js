'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {Client} = require('pg');
const {seed, id} = require('./helpers/workflowInboxFixture');
const {listInbox} = require('../src/services/sharedWorkflowInbox');
const url = process.env.WORKFLOW_INBOX_TEST_DATABASE_URL;

test('real PostgreSQL paging retains visibility, exact timestamp ties, history and request targeting', {skip: !url}, async () => {
  const db = new Client({connectionString: url});
  await db.connect();
  try {
    await db.query('BEGIN');
    const schema = 'inbox_paging_' + require('node:crypto').randomBytes(6).toString('hex');
    await db.query(`CREATE SCHEMA ${schema}; SET LOCAL search_path=${schema},pg_catalog`);
    await seed(db, {users: 12, requests: 230});
    const actor = {id: id(1), role: 'admin'};
    let queries = 0;
    const counted = {query: (...args) => {queries++; return db.query(...args);}};
    const legacy = await listInbox(counted, actor, {includeHistory: true});
    const legacyQueries = queries;
    const collected = [];
    for (const kind of ['leave', 'locator']) {
      let cursor;
      do {
        const page = await listInbox(counted, actor, {includeHistory: true, paginated: true, kind, limit: 13, cursor});
        assert.ok(page.items.length <= 13);
        collected.push(...page.items);
        cursor = page.next_cursor[kind];
      } while (cursor);
    }
    assert.equal(new Set(collected.map(r => `${r.kind}/${r.id}`)).size, collected.length);
    assert.deepEqual(collected.map(r => r.id).sort(), legacy.map(r => r.id).sort());
    assert.ok(legacyQueries < 20, `reviewer queries were shared (${legacyQueries} queries)`);
    assert.equal(collected.filter(r => r.status === 'approved' && r.kind === 'leave').every(r => r.request_data.can_revoke_approval), true);
    const first = await listInbox(db, actor, {paginated: true, kind: 'leave', limit: 2});
    assert.ok(first.items.every(r => r.status === 'pending_hr'));
    const target = legacy.find(r => r.kind === 'leave' && !first.items.some(p => p.id === r.id));
    const exact = await listInbox(db, actor, {paginated: true, kind: 'leave', requestId: target.id, includeHistory: true});
    assert.deepEqual(exact.items.map(r => r.id), [target.id]);
    const outsider = await listInbox(db, {id: id(8)}, {paginated: true, kind: 'leave', requestId: target.id});
    assert.deepEqual(outsider.items, []);
    const denied = await listInbox(db, {id: id(999)}, {paginated: true, kind: 'leave'});
    assert.deepEqual(denied.items, []);
    await db.query('UPDATE users SET is_active=false WHERE id=$1', [actor.id]);
    const changed = await listInbox(db, actor, {paginated: true, kind: 'leave'});
    assert.deepEqual(changed.items, []);
  } finally {await db.query('ROLLBACK'); await db.end();}
});
