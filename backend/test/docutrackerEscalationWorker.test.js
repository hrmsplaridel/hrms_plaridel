const test = require('node:test');
const assert = require('node:assert/strict');

const { processEscalationsOnce } = require('../src/services/docutrackerEscalationWorker');

function fakePool({
  connectError = null,
  connectGate = null,
  lockResult = { rows: [{ locked: true }] },
  failOn = {},
  releaseError = null,
} = {}) {
  const state = { connects: 0, releases: [], queries: [] };
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      state.queries.push(text);
      for (const [fragment, error] of Object.entries(failOn)) {
        if (text.includes(fragment)) throw error;
      }
      if (text.includes('pg_try_advisory_lock')) return lockResult;
      return { rowCount: 0, rows: [] };
    },
    release(discard) {
      state.releases.push(discard);
      if (releaseError) throw releaseError;
    },
  };
  const db = {
    async connect() {
      state.connects += 1;
      if (connectGate) await connectGate;
      if (connectError) throw connectError;
      return client;
    },
  };
  const ran = (fragment) => state.queries.some((q) => q.includes(fragment));
  return { db, state, ran };
}

function silenceErrors(t) {
  t.mock.method(console, 'error', () => {});
}

async function assertNextRunProceeds() {
  const next = fakePool();
  await processEscalationsOnce({ db: next.db });
  assert.equal(next.state.connects, 1, 'a later run is not skipped');
  assert.equal(next.ran('COMMIT'), true);
  assert.deepEqual(next.state.releases, [false]);
}

test('a successful run commits, unlocks, releases once, and resets the running flag', async () => {
  const { db, state, ran } = fakePool();
  await processEscalationsOnce({ db });
  assert.equal(ran('BEGIN'), true);
  assert.equal(ran('COMMIT'), true);
  assert.equal(ran('ROLLBACK'), false);
  assert.equal(ran('pg_advisory_unlock'), true);
  assert.deepEqual(state.releases, [false]);
  await assertNextRunProceeds();
});

test('a processing exception rolls back, unlocks, releases once, and resets the flag', async (t) => {
  silenceErrors(t);
  const { db, state, ran } = fakePool({
    failOn: { 'FOR UPDATE OF d SKIP LOCKED': new Error('query failed') },
  });
  await processEscalationsOnce({ db });
  assert.equal(ran('COMMIT'), false);
  assert.equal(ran('ROLLBACK'), true);
  assert.equal(ran('pg_advisory_unlock'), true);
  assert.deepEqual(state.releases, [false]);
  await assertNextRunProceeds();
});

test('a failed commit is rolled back and the flag is reset', async (t) => {
  silenceErrors(t);
  const { db, state, ran } = fakePool({ failOn: { COMMIT: new Error('commit failed') } });
  await processEscalationsOnce({ db });
  assert.equal(ran('ROLLBACK'), true);
  assert.equal(ran('pg_advisory_unlock'), true);
  assert.deepEqual(state.releases, [false]);
  await assertNextRunProceeds();
});

test('a connection acquisition failure releases nothing and resets the flag', async (t) => {
  silenceErrors(t);
  const { db, state } = fakePool({ connectError: new Error('pool exhausted') });
  await assert.doesNotReject(() => processEscalationsOnce({ db }));
  assert.equal(state.connects, 1);
  assert.deepEqual(state.releases, []);
  assert.deepEqual(state.queries, []);
  await assertNextRunProceeds();
});

test('an advisory lock query error skips the transaction, releases once, and resets the flag', async (t) => {
  silenceErrors(t);
  const { db, state, ran } = fakePool({
    failOn: { pg_try_advisory_lock: new Error('connection reset') },
  });
  await processEscalationsOnce({ db });
  assert.equal(ran('BEGIN'), false);
  assert.equal(ran('ROLLBACK'), false);
  assert.equal(ran('pg_advisory_unlock'), false);
  assert.deepEqual(state.releases, [false]);
  await assertNextRunProceeds();
});

test('an advisory lock held elsewhere or an unexpected lock result skips the run and resets the flag', async () => {
  for (const lockResult of [{ rows: [{ locked: false }] }, { rows: [] }, null]) {
    const { db, state, ran } = fakePool({ lockResult });
    await processEscalationsOnce({ db });
    assert.equal(ran('BEGIN'), false);
    assert.equal(ran('pg_advisory_unlock'), false);
    assert.deepEqual(state.releases, [false]);
  }
  await assertNextRunProceeds();
});

test('failing rollback, unlock, and release still reset the flag and discard the client', async (t) => {
  silenceErrors(t);
  const { db, state, ran } = fakePool({
    failOn: {
      'FOR UPDATE OF d SKIP LOCKED': new Error('query failed'),
      ROLLBACK: new Error('rollback failed'),
      pg_advisory_unlock: new Error('unlock failed'),
    },
    releaseError: new Error('release failed'),
  });
  await assert.doesNotReject(() => processEscalationsOnce({ db }));
  assert.equal(ran('ROLLBACK'), true);
  assert.equal(ran('pg_advisory_unlock'), true);
  assert.deepEqual(state.releases, [true], 'client is released once and discarded');
  await assertNextRunProceeds();
});

test('a failed unlock alone discards the client so the session lock cannot linger in the pool', async (t) => {
  silenceErrors(t);
  const { db, state } = fakePool({ failOn: { pg_advisory_unlock: new Error('unlock failed') } });
  await processEscalationsOnce({ db });
  assert.deepEqual(state.releases, [true]);
  await assertNextRunProceeds();
});

test('overlapping runs are skipped while a run is genuinely active', async () => {
  let openGate;
  const gate = new Promise((resolve) => {
    openGate = resolve;
  });
  const first = fakePool({ connectGate: gate });
  const firstRun = processEscalationsOnce({ db: first.db });

  const overlapping = fakePool();
  await processEscalationsOnce({ db: overlapping.db });
  assert.equal(overlapping.state.connects, 0, 'overlapping run does not start');

  openGate();
  await firstRun;
  assert.equal(first.ran('COMMIT'), true);
  assert.deepEqual(first.state.releases, [false]);
  await assertNextRunProceeds();
});
