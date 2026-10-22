const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const express = require('express');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const contract = require('./fixtures/locator-route-contract.json');
const entry = '../src/routes/locatorSlips';

async function withRouter(name, run) {
  const queries = [];
  const query = async (sql, params) => {
    queries.push({ sql, params });
    return { rows: String(sql).includes('ORDER BY sort_order ASC')
      ? [{ id: name, code: name, label: name, short_label: name }]
      : [] };
  };
  const pool = { query, connect: async () => ({ query, release() {} }) };
  const restore = withMockedModule('../src/config/db', { pool });
  clearModule(entry);
  try { await run(require(entry), queries); }
  finally { clearModule(entry); restore(); }
}

test('Locator preserves its ordered endpoints, print mount and authorization middleware', async () => {
  await withRouter('contract', async (router) => {
    assert.deepEqual(router.stack.map((layer) => layer.route ? {
      path: layer.route.path, methods: Object.keys(layer.route.methods),
      middleware: layer.route.stack.slice(0, -1).map((s) => s.handle.name),
    } : { name: layer.name, regexp: String(layer.regexp) }), contract);
  });
});

test('recreating the Locator entry uses the current database dependencies', async () => {
  for (const name of ['first', 'second']) {
    await withRouter(name, async (router) => {
      const handle = router.stack.find((l) => l.route?.path === '/types' && l.route.methods.get).route.stack.at(-1).handle;
      const res = { status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; } };
      await handle({ query: {}, user: { id: name, role: 'admin' } }, res);
      assert.equal(res.body[0].code, name);
    });
  }
});

test('real Express requests still authenticate every Locator endpoint and print routes', async () => {
  await withRouter('http', async (router) => {
    const app = express();
    app.use('/api/locator-slips', router);
    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
      const base = `http://127.0.0.1:${server.address().port}/api/locator-slips`;
      const routes = [...contract.filter((e) => e.path), { path: '/print/requests/request/render', methods: ['get'] }];
      for (const endpoint of routes) {
        const url = endpoint.path.replace(':id', 'request');
        const response = await fetch(base + url, { method: endpoint.methods[0].toUpperCase() });
        assert.equal(response.status, 401, `${endpoint.methods[0]} ${url}`);
        assert.match((await response.json()).error, /Authorization/);
      }
    } finally { await new Promise((resolve) => server.close(resolve)); }
  });
});

function moduleFiles(directory = path.resolve(__dirname, '../src/modules/locator')) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((item) => {
    const file = path.join(directory, item.name);
    return item.isDirectory() ? moduleFiles(file) : file.endsWith('.js') ? [file] : [];
  });
}

test('Locator entry delegates to focused module implementations', () => {
  const legacy = fs.readFileSync(path.resolve(__dirname, '../src/routes/locatorSlips.js'), 'utf8');
  assert.ok(legacy.split('\n').length < 120, 'The compatibility entry must only compose the Locator module');
  assert.doesNotMatch(legacy, /pool\.query|BEGIN|ALTER TABLE/);
  assert.equal(typeof require('../src/modules/locator/locator.router').createLocatorRouter, 'function');
  for (const file of moduleFiles()) {
    assert.ok(fs.readFileSync(file, 'utf8').split('\n').length <= 550, `${file} needs a focused responsibility`);
  }
});

test('Locator keeps both the default and configured attachment directory', async () => {
  const original = process.env.UPLOAD_DIR;
  try {
    await withRouter('paths', async () => {
      const { loadLocatorDependencies } = require('../src/modules/locator/dependencies');
      delete process.env.UPLOAD_DIR;
      assert.equal(loadLocatorDependencies().UPLOAD_DIR, path.resolve(__dirname, '../uploads'));
      process.env.UPLOAD_DIR = 'custom-relative-upload-root';
      assert.equal(loadLocatorDependencies().UPLOAD_DIR, 'custom-relative-upload-root');
    });
  } finally {
    if (original === undefined) delete process.env.UPLOAD_DIR;
    else process.env.UPLOAD_DIR = original;
  }
});

test('every Locator relative import resolves with exact filename casing', () => {
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
