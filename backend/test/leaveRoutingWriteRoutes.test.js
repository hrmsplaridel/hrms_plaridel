const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

for (const body of [{}, {mayor_employment_types: null}, {approval_route: null}, {approval_route: ''}, {approval_route: false}]) {
  test(`routing write rejects incomplete route ${JSON.stringify(body)} without changing saved settings`, async () => {
    const writes = [];
    const restore = withMockedModule('../src/config/db', {pool: {query: async (sql, params) => {
      writes.push(params); return {rows: [{approval_route: 'hr', mayor_employment_types: null}]};
    }}});
    clearModule('../src/routes/leaveRouting');
    try {
      const router = require('../src/routes/leaveRouting');
      const handle = router.stack.find(s => s.route?.methods.post).route.stack.at(-1).handle;
      const res = {code: 200, status(n) {this.code=n;return this;}, json(v) {this.body=v;}};
      await handle({params: {id: 'type'}, body}, res);
      assert.equal(res.code, 400);
      assert.equal(writes.length, 0);
    } finally {clearModule('../src/routes/leaveRouting');restore();}
  });
}

for (const route of ['hr', 'mayor']) {
  test(`routing write accepts explicitly selected ${route}`, async () => {
    let written;
    const restore = withMockedModule('../src/config/db', {pool: {query: async (sql, params) => {
      written=params;return {rows: [{approval_route: params[0], mayor_employment_types: params[1]}]};
    }}});
    clearModule('../src/routes/leaveRouting');
    try {
      const router = require('../src/routes/leaveRouting');
      const handle = router.stack.find(s => s.route?.methods.post).route.stack.at(-1).handle;
      const res = {code: 200, status(n) {this.code=n;return this;}, json(v) {this.body=v;}};
      await handle({params: {id: 'type'}, body: {approval_route: route, mayor_employment_types: ['permanent']}}, res);
      assert.equal(res.code, 200);
      assert.deepEqual(written, [route, route==='hr' ? null : ['permanent'], 'type']);
    } finally {clearModule('../src/routes/leaveRouting');restore();}
  });
}

test('new leave type creation retains its default HR route', () => {
  const {normalizeRouting} = require('../src/services/leaveRouting');
  assert.deepEqual(normalizeRouting({}), {approval_route: 'hr', mayor_employment_types: null});
});
