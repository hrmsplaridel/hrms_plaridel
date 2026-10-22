const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const express = require('express');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const contract = require('./fixtures/dtr-route-contract.json');
const entry = '../src/routes/dtrDailySummary';

async function withRouter(name, run) {
  const queries = [];
  const pool = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (String(sql).includes('d.attendance_date::text AS attendance_date_iso')) {
        return { rows: [{ id: name, employee_id: name, attendance_date_iso: '2026-01-05', status: 'present' }] };
      }
      return { rows: [] };
    },
  };
  const restore = withMockedModule('../src/config/db', { pool });
  clearModule(entry);
  try { await run(require(entry), queries); }
  finally { clearModule(entry); restore(); }
}

test('DTR preserves the complete ordered route and authorization middleware contract', async () => {
  await withRouter('contract', async (router) => {
    assert.deepEqual(router.stack.map((layer) => ({
      path: layer.route.path,
      methods: Object.keys(layer.route.methods),
      middleware: layer.route.stack.slice(0, -1).map((s) => s.handle.name),
    })), contract);
  });
});

test('recreating the DTR entry uses the current database and a fresh holiday capability cache', async () => {
  for (const name of ['first', 'second']) {
    await withRouter(name, async (router, queries) => {
      const handle = router.stack.find((l) => l.route.path === '/' && l.route.methods.get).route.stack.at(-1).handle;
      for (let attempt = 0; attempt < 2; attempt += 1) {
        const res = { status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; } };
        await handle({ user: { id: name, role: 'admin' }, query: {} }, res);
        assert.equal(res.body[0].id, name);
        assert.equal(res.body[0].user_id, name);
      }
      assert.equal(queries.filter((q) => q.sql === 'SELECT coverage FROM holidays LIMIT 1').length, 1);
    });
  }
});

test('real Express requests still authenticate all DTR endpoints', async () => {
  await withRouter('http', async (router) => {
    const app = express();
    app.use('/api/dtr-daily-summary', router);
    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
      const base = `http://127.0.0.1:${server.address().port}/api/dtr-daily-summary`;
      for (const endpoint of contract) {
        const url = endpoint.path.replace(':deletionId', 'deletion').replace(':id', 'record');
        const response = await fetch(base + url, { method: endpoint.methods[0].toUpperCase() });
        assert.equal(response.status, 401, `${endpoint.methods[0]} ${url}`);
        assert.match((await response.json()).error, /Authorization/);
      }
    } finally { await new Promise((resolve) => server.close(resolve)); }
  });
});

function moduleFiles() {
  const files = [];
  function visit(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, item.name);
      if (item.isDirectory()) visit(file);
      else if (file.endsWith('.js')) files.push(file);
    }
  }
  visit(path.resolve(__dirname, '../src/modules/dtr'));
  return files;
}

test('DTR entry delegates to a feature module with focused implementations', () => {
  const legacy = fs.readFileSync(path.resolve(__dirname, '../src/routes/dtrDailySummary.js'), 'utf8');
  assert.ok(legacy.split('\n').length < 120, 'The compatibility entry must only compose the DTR module');
  assert.doesNotMatch(legacy, /pool\.query|BEGIN|ALTER TABLE/);
  assert.equal(typeof require('../src/modules/dtr/dtr.router').createDtrRouter, 'function');
  for (const file of moduleFiles()) {
    assert.ok(fs.readFileSync(file, 'utf8').split('\n').length <= 550, `${file} needs a focused responsibility`);
  }
});

test('every DTR relative import resolves with exact filename casing', () => {
  for (const file of moduleFiles()) {
    for (const [, reference] of fs.readFileSync(file, 'utf8').matchAll(/require\(['"](\.[^'"]+)['"]\)/g)) {
      const resolved = require.resolve(path.resolve(path.dirname(file), reference));
      const relative = path.relative(path.resolve(__dirname, '../src'), resolved);
      let directory = path.resolve(__dirname, '../src');
      for (const segment of relative.split(path.sep)) {
        assert.ok(fs.readdirSync(directory).includes(segment), `${file}: ${reference} has incorrect casing`);
        directory = path.join(directory, segment);
      }
    }
  }
});
