const test = require('node:test');
const assert = require('node:assert/strict');
const {createReviewNotificationReconciler} = require('../src/services/reviewNotificationCompletion');

test('repair is coalesced per database and user and expires without caching counts', async () => {
  let now = 0, calls = 0, release;
  const db = {}, otherDb = {};
  const reconcile = createReviewNotificationReconciler({now: () => now, cooldownMs: 15, reconcile: async () => {
    calls++;
    if (calls === 1) await new Promise(resolve => {release = resolve;});
  }});
  const first = reconcile(db, 'a'), second = reconcile(db, 'a');
  assert.equal(calls, 1);
  release();
  await Promise.all([first, second]);
  await reconcile(db, 'a');
  assert.equal(calls, 1);
  await reconcile(db, 'b');
  await reconcile(otherDb, 'a');
  assert.equal(calls, 3);
  now = 16;
  await reconcile(db, 'a');
  assert.equal(calls, 4);
  reconcile.invalidate(db, 'a');
  await reconcile(db, 'a');
  assert.equal(calls, 5);
});

test('failed repair is retried immediately', async () => {
  let calls = 0;
  const reconcile = createReviewNotificationReconciler({reconcile: async () => {
    if (++calls === 1) throw Error('Unavailable');
  }});
  const db = {};
  await assert.rejects(reconcile(db, 'a'), /Unavailable/);
  await reconcile(db, 'a');
  assert.equal(calls, 2);
});

test('an alert arriving during repair makes every waiter await a fresh pass', async () => {
  let calls = 0, releaseFirst, releaseSecond, secondFinished = false;
  const repair = createReviewNotificationReconciler({reconcile: async () => {
    calls++;
    await new Promise(resolve => {if (calls === 1) releaseFirst = resolve; else releaseSecond = resolve;});
  }});
  const db = {};
  const first = repair(db, 'a');
  const second = repair(db, 'a').then(() => {secondFinished = true;});
  repair.invalidate(db, 'a');
  releaseFirst();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 2);
  assert.equal(secondFinished, false);
  releaseSecond();
  await Promise.all([first, second]);
});
