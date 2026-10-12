const test = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const {createHeavyWorkQueue, mapConcurrent} = require('../src/services/heavyWorkQueue');
const {withHeavyWork} = require('../src/middleware/heavyWork');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return {promise, resolve}; }
const tick = () => new Promise(r => setImmediate(r));

test('shared queue bounds active jobs, serves FIFO and rejects overflow', async () => {
  const queue = createHeavyWorkQueue({concurrency: 1, maxQueue: 2, waitMs: 1000});
  const release = deferred(); const order = [];
  const first = queue.run(async () => { order.push('report'); await release.promise; });
  const second = queue.run(async () => { order.push('leave'); });
  const third = queue.run(async () => { order.push('locator'); });
  await assert.rejects(queue.run(() => assert.fail('overflow must not run')), {code: 'HEAVY_OPERATION_BUSY'});
  assert.deepEqual(order, ['report']);
  release.resolve(); await Promise.all([first, second, third]);
  assert.deepEqual(order, ['report', 'leave', 'locator']);
});
test('queued timeout and cancellation never execute and free queue space', async () => {
  const queue = createHeavyWorkQueue({concurrency: 1, maxQueue: 1, waitMs: 20});
  const release = deferred(); const first = queue.run(() => release.promise);
  await assert.rejects(queue.run(() => assert.fail('expired job')), {code: 'HEAVY_OPERATION_BUSY'});
  const abort = new AbortController();
  const canceled = queue.run(() => assert.fail('canceled job'), {signal: abort.signal});
  abort.abort(); await assert.rejects(canceled, {code: 'HEAVY_OPERATION_ABORTED'});
  const next = queue.run(() => 'next');
  release.resolve(); await first; assert.equal(await next, 'next');
});
test('failures release capacity; active cancellation retains it until work ends', async () => {
  const queue = createHeavyWorkQueue({concurrency: 1, maxQueue: 0, waitMs: 1000});
  await assert.rejects(queue.run(() => { throw new Error('failed'); }), /failed/);
  const release = deferred(); const abort = new AbortController();
  const active = queue.run(() => release.promise, {signal: abort.signal});
  await tick();
  abort.abort();
  await assert.rejects(queue.run(() => 'early'), {code: 'HEAVY_OPERATION_BUSY'});
  release.resolve(); await active;
  assert.equal(await queue.run(() => 'recovered'), 'recovered');
});
test('HTTP busy response includes retry time and disconnect does not free running work', async () => {
  const queue = createHeavyWorkQueue({concurrency: 1, maxQueue: 0, waitMs: 1000});
  const release = deferred();
  function response() { return Object.assign(new EventEmitter(), {headers: {}, setHeader(k,v) {this.headers[k]=v;}, status(n) {this.code=n;return this;}, json(b) {this.body=b;return this;}}); }
  const req = new EventEmitter(); const res = response();
  const active = withHeavyWork(() => release.promise, {queue})(req, res);
  await tick(); res.emit('close');
  const busy = response(); let ran = false;
  await withHeavyWork(() => {ran=true;}, {queue})(new EventEmitter(), busy);
  assert.equal(ran, false); assert.equal(busy.code, 503);
  assert.equal(busy.body.code, 'HEAVY_OPERATION_BUSY');
  assert.equal(busy.headers['Retry-After'], String(busy.body.retryAfterSeconds));
  release.resolve(); await active;
  assert.equal(res.listenerCount('close'), 0);
});
test('bounded row mapping preserves order and drains active work before rejecting', async () => {
  let active = 0; let peak = 0;
  const output = await mapConcurrent([1,2,3,4,5], 2, async value => {
    active++; peak=Math.max(peak,active); await tick(); active--; return value*2;
  });
  assert.equal(peak, 2); assert.deepEqual(output, [2,4,6,8,10]);
  const release = deferred(); let finished = false; const started=[];
  const failed = mapConcurrent([1,2,3], 2, async value => {
    started.push(value);
    if(value===1) {await tick(); throw new Error('row failure');}
    await release.promise;
  });
  const assertion = assert.rejects(failed, /row failure/).then(() => {finished=true;});
  await tick(); await tick(); assert.equal(finished, false);
  release.resolve(); await assertion; assert.deepEqual(started, [1,2]);
});
test('bulk reports and all PDF endpoints use the same capacity guard before database work', async () => {
  const queue = createHeavyWorkQueue({concurrency: 1, maxQueue: 0, waitMs: 1000});
  const restoreQueue = withMockedModule('../src/services/heavyWorkQueue', {
    heavyWorkQueue: queue, mapConcurrent, dtrRowConcurrency: 2,
  });
  const restoreDb = withMockedModule('../src/config/db', {pool: {
    query() {assert.fail('Busy requests must not start database work');},
  }});
  const modules = ['../src/routes/dtrDailySummary', '../src/routes/leavePrintTemplates', '../src/routes/locatorPrintTemplates'];
  clearModule('../src/middleware/heavyWork');
  modules.forEach(clearModule);
  const release = deferred(); const active = queue.run(() => release.promise);
  await tick();
  try {
    for (const module of modules) {
      const router = require(module);
      const paths = module.endsWith('dtrDailySummary') ? ['/bulk-report'] : ['/requests/:id/render', '/types/:id/preview'];
      for (const path of paths) {
        const handler = router.stack.find(layer => layer.route?.path === path && layer.route.methods.post).route.stack.at(-1).handle;
        const res = {setHeader() {}, status(code) {this.code=code;return this;}, json(body) {this.body=body;return this;}};
        await handler({user: {id: 'employee', role: 'hr'}, params: {id: 'id'}, body: {}}, res);
        assert.equal(res.code, 503, `${module} ${path}`);
        assert.equal(res.body.code, 'HEAVY_OPERATION_BUSY');
      }
    }
  } finally {
    release.resolve(); await active;
    modules.forEach(clearModule); clearModule('../src/middleware/heavyWork');
    restoreDb(); restoreQueue();
  }
});
