const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const express = require('express');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');
const contract = require('./fixtures/leave-route-contract.json');
const entry = '../src/routes/leaveRoutes';

async function withRouter(name, run) {
  const queries = [];
  const pool = {
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (String(sql).includes('ORDER BY is_system DESC'))
        return { rows: [{ id: name, name, display_name: name }] };
      return { rows: [] };
    },
  };
  const restore = withMockedModule('../src/config/db', { pool });
  clearModule(entry);
  try {
    await run(require(entry), queries);
  } finally {
    clearModule(entry);
    restore();
  }
}

test('Leave keeps its complete ordered route and authorization middleware contract', async () => {
  await withRouter('first', async (router) => {
    const actual = router.stack.map((layer) =>
      layer.route
        ? {
            path: layer.route.path,
            methods: Object.keys(layer.route.methods),
            middleware: layer.route.stack.slice(0, -1).map((s) => s.handle.name),
          }
        : { name: layer.name, regexp: String(layer.regexp) },
    );
    assert.deepEqual(actual, contract);
  });
});

test('recreating the compatibility entry uses the current database dependencies', async () => {
  for (const name of ['first', 'second']) {
    await withRouter(name, async (router) => {
      const handle = router.stack
        .find((l) => l.route?.path === '/types' && l.route.methods.get)
        .route.stack.at(-1).handle;
      const res = {
        json(body) {
          this.body = body;
        },
        status() {
          return this;
        },
      };
      await handle({ query: {} }, res);
      assert.equal(res.body[0].name, name);
    });
  }
});

test('real Express requests still reach authentication for fixed and request-specific paths', async () => {
  await withRouter('http', async (router) => {
    const app = express();
    app.use('/api/leave', router);
    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
      const base = `http://127.0.0.1:${server.address().port}/api/leave`;
      for (const url of [
        '/types',
        '/my/context',
        '/pending',
        '/balances/employee',
        '/request/attachment',
        '/request',
      ]) {
        const response = await fetch(base + url);
        assert.equal(response.status, 401, url);
        assert.match((await response.json()).error, /Authorization/);
      }
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  });
});

test('Leave entry delegates to a feature module with focused implementations', () => {
  const legacy = fs.readFileSync(path.resolve(__dirname, '../src/routes/leaveRoutes.js'), 'utf8');
  assert.ok(
    legacy.split('\n').length < 120,
    'The compatibility entry must only compose the Leave module',
  );
  assert.doesNotMatch(legacy, /pool\.query|BEGIN|ALTER TABLE/);
  assert.equal(typeof require('../src/modules/leave/leave.router').createLeaveRouter, 'function');
});

test('moving Leave files preserves default and configured upload roots', async () => {
  const original = process.env.UPLOAD_DIR;
  try {
    await withRouter('paths', async () => {
      const { loadLeaveDependencies } = require('../src/modules/leave/dependencies');
      delete process.env.UPLOAD_DIR;
      assert.equal(loadLeaveDependencies().UPLOAD_DIR, path.resolve(__dirname, '../uploads'));
      process.env.UPLOAD_DIR = 'custom-relative-upload-root';
      assert.equal(loadLeaveDependencies().UPLOAD_DIR, 'custom-relative-upload-root');
    });
  } finally {
    if (original === undefined) delete process.env.UPLOAD_DIR;
    else process.env.UPLOAD_DIR = original;
  }
});

test('every relative dependency in the Leave module resolves with exact filename casing', () => {
  function check(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, item.name);
      if (item.isDirectory()) { check(file); continue; }
      if (!file.endsWith('.js')) continue;
      const source = fs.readFileSync(file, 'utf8');
      for (const [, reference] of source.matchAll(/require\(['"](\.[^'"]+)['"]\)/g)) {
        const resolved = require.resolve(path.resolve(path.dirname(file), reference));
        const actualName = path.basename(resolved);
        assert.ok(fs.readdirSync(path.dirname(resolved)).includes(actualName), `${file}: ${reference}`);
        const expected = path.basename(reference);
        assert.ok(actualName === expected || actualName === `${expected}.js` || actualName === 'index.js', `${file}: ${reference}`);
      }
    }
  }
  check(path.resolve(__dirname, '../src/modules/leave'));
});
