'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../src/services/approvalWorkflows');
const {listInbox} = require('../src/services/sharedWorkflowInbox');
const id = n => `33333333-3333-4333-8333-${String(n).padStart(12, '0')}`;
function request(n, kind = 'leave') {
  return {id: id(n), employee_id: id(999), employee_name: 'Applicant', status: 'pending_hr',
    created_at: '2026-10-23T00:00:00.123456Z', kind,
    workflow_snapshot: {name: 'Route', version: 1, current_step: 0,
      steps: [{assignee_source: 'specific_users', user_ids: [id(1)], label: 'Review', allowed_actions: ['approve']}], decisions: []}};
}

test('paged inbox returns independent module pages and a continuation cursor', async () => {
  const original = engine.resolveWorkflowReviewers;
  engine.resolveWorkflowReviewers = async () => [{id: id(1)}];
  const rows = [request(4), request(3), request(2), request(8, 'locator')];
  const queries = [];
  const db = {query: async (sql, params) => {
    queries.push({sql, params});
    const kind = sql.includes('FROM leave_requests') ? 'leave' : 'locator';
    let result = rows.filter(r => r.kind === kind);
    if (params.length > 1) result = result.filter(r => r.id < params[3]);
    return {rows: result};
  }};
  try {
    const page = await listInbox(db, {id: id(1)}, {paginated: true, limit: 2});
    assert.deepEqual(page.items.map(r => r.id).sort(), [id(3), id(4), id(8)].sort());
    assert.equal(page.has_more.leave, true);
    assert.equal(page.has_more.locator, false);
    assert.ok(page.next_cursor.leave);
    assert.equal(page.next_cursor.locator, null);
    const next = await listInbox(db, {id: id(1)}, {paginated: true, kind: 'leave', limit: 2, cursor: page.next_cursor.leave});
    assert.deepEqual(next.items.map(r => r.id), [id(2)]);
    assert.equal(next.has_more.leave, false);
    assert.ok(queries.every(q => /LIMIT\s+\d+/i.test(q.sql)), 'candidate queries are bounded');
  } finally { engine.resolveWorkflowReviewers = original; }
});

test('authorization filtering occurs before the visible page fills', async () => {
  const original = engine.resolveWorkflowReviewers;
  engine.resolveWorkflowReviewers = async (_db, _kind, row) => [{id: row.id === id(9) ? id(2) : id(1)}];
  const db = {query: async sql => ({rows: sql.includes('FROM leave_requests') ? [request(9), request(8), request(7), request(6)] : []})};
  try {
    const page = await listInbox(db, {id: id(1)}, {paginated: true, kind: 'leave', limit: 2});
    assert.deepEqual(page.items.map(r => r.id), [id(8), id(7)]);
    assert.equal(page.has_more.leave, true);
    assert.ok(!page.items.some(r => r.id === id(9)));
  } finally { engine.resolveWorkflowReviewers = original; }
});

test('cursor cannot be reused for a different module or history scope', async () => {
  const {cursorFor, optionsFor} = require('../src/services/workflowInboxPaging');
  const cursor = cursorFor(request(3), 'leave', true);
  for (const options of [
    {kind: 'locator', includeHistory: true}, {kind: 'leave', includeHistory: false},
  ]) assert.throws(() => optionsFor({paginated: true, cursor, ...options}), {statusCode: 400});
});

test('targeted request lookup does not scan or page unrelated records', async () => {
  const original = engine.resolveWorkflowReviewers;
  engine.resolveWorkflowReviewers = async () => [{id: id(1)}];
  const queries = [];
  const db = {query: async (sql, params) => {queries.push({sql, params}); return {rows:[request(3)]};}};
  try {
    const page = await listInbox(db, {id:id(1)}, {paginated:true, kind:'leave', requestId:id(3)});
    assert.deepEqual(page.items.map(r=>r.id), [id(3)]);
    assert.equal(queries.length,1);
    assert.match(queries[0].sql,/r\.id=\$2::uuid LIMIT 1/);
    assert.deepEqual(queries[0].params, [id(1),id(3)]);
  } finally {engine.resolveWorkflowReviewers=original;}
});

test('repeated reviewer queries are shared within a request, never across requests', async () => {
  const original = engine.resolveWorkflowReviewers;
  let lookups = 0;
  engine.resolveWorkflowReviewers = async db => (await db.query('SELECT id FROM users WHERE id=$1', [id(1)])).rows;
  const db = {query: async sql => {
    if (sql.startsWith('SELECT id FROM users')) { lookups++; return {rows: [{id: id(1)}]}; }
    return {rows: sql.includes('FROM leave_requests') ? [request(3), request(2)] : []};
  }};
  try {
    assert.equal((await listInbox(db, {id: id(1)})).length, 2);
    assert.equal(lookups, 1);
    await listInbox(db, {id: id(1)});
    assert.equal(lookups, 2);
  } finally { engine.resolveWorkflowReviewers = original; }
});

test('candidate batches are not retained by the reviewer-query cache', async () => {
  const {memoizedReads} = require('../src/services/workflowInboxPaging');
  let calls = 0;
  const db = memoizedReads({query: async () => {calls++; return {rows:[]};}});
  await db.query('SELECT r.* FROM leave_requests r LIMIT 100', [id(1)]);
  await db.query('SELECT r.* FROM leave_requests r LIMIT 100', [id(1)]);
  assert.equal(calls, 2);
  await db.query('SELECT id FROM users WHERE id=$1', [id(1)]);
  await db.query('SELECT id FROM users WHERE id=$1', [id(1)]);
  assert.equal(calls, 3);
});

for (const options of [
  {limit: 0}, {limit: 201}, {limit: '2x'}, {kind: 'users'}, {cursor: 'bad'}, {requestId:'invalid'},
]) test(`invalid paging options are rejected before database access: ${JSON.stringify(options)}`, async () => {
  const db = {query: async () => {throw Error('Database must not be accessed');}};
  await assert.rejects(listInbox(db, {id: id(1)}, {paginated: true, ...options}), {statusCode: 400});
});
