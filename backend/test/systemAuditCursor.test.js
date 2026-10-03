const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('audit cursor traversal excludes new visits and handles equal timestamps without repeats', async () => {
  const stamp = '2026-10-04T00:00:00.123456Z';
  const snapshot = '2026-10-04T00:00:01.000000Z';
  const records = [5, 4, 3, 2, 1].map(n => ({
    id: `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
    cursor_time: stamp, created_at: stamp,
  }));
  const queries = [];
  const restore = withMockedModule('../src/config/db', { pool: { async query(sql, params = []) {
    queries.push(sql);
    if (sql.includes('clock_timestamp()')) return { rows: [{ snapshot }] };
    if (sql.includes('INSERT INTO')) {
      records.unshift({ id: `new-${records.length}`, cursor_time: '2026-10-04T00:00:02.000000Z' });
      return { rows: [] };
    }
    assert.match(sql, /a\.created_at < \$\d+::timestamptz/);
    let selected = records.filter(row => row.cursor_time < params[0]);
    if (sql.includes('COUNT(*)')) return { rows: [{ total: selected.length }] };
    assert.doesNotMatch(sql, /OFFSET/);
    if (sql.includes('(a.created_at, a.id) <')) {
      selected = selected.filter(row => row.cursor_time < params[1] ||
        (row.cursor_time === params[1] && row.id < params[2]));
    }
    return { rows: selected.slice(0, params.at(-1)) };
  } } });
  const path = '../src/routes/systemAudit';
  clearModule(path);
  try {
    const handler = require(path).stack.find(e => e.route?.methods.get).route.stack.at(-1).handle;
    async function load(cursor, page = '1') {
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
      await handler({ user: { id: 'admin' }, query: { pagination: 'cursor', page, limit: '2', ...(cursor ? { cursor } : {}) } }, res);
      return res;
    }
    const first = await load();
    assert.equal(first.statusCode, 200);
    assert.ok(first.body.next_cursor);
    assert.ok(first.body.first_cursor);
    const second = await load(first.body.next_cursor);
    const third = await load(second.body.next_cursor);
    assert.deepEqual([...first.body.entries, ...second.body.entries, ...third.body.entries].map(e => e.id),
      [5, 4, 3, 2, 1].map(n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`));
    assert.equal(third.body.next_cursor, null);
    assert.equal(third.body.total, 5);
    assert.deepEqual((await load(first.body.first_cursor)).body.entries, first.body.entries);
    assert.equal((await load(second.body.next_cursor, '201')).statusCode, 200);
    const count = queries.length;
    for (const token of ['invalid', Buffer.from(JSON.stringify({ snapshot: '2026-02-30T00:00:00.000000Z' })).toString('base64url'),
      Buffer.from(JSON.stringify({ snapshot, after: { time: stamp, id: 'invalid' } })).toString('base64url')]) {
      assert.equal((await load(token)).statusCode, 400);
    }
    assert.equal(queries.length, count);
  } finally { clearModule(path); restore(); }
});
