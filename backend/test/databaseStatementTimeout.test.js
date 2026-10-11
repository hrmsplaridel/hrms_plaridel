const test = require('node:test');
const assert = require('node:assert/strict');
const {buildPoolOptions, getStatementDeadlineMs} = require('../src/config/databasePoolOptions');

test('database deadline defaults are bounded and cannot be disabled by invalid settings', () => {
  const defaults = buildPoolOptions({});
  assert.equal(defaults.connectionTimeoutMillis, 10000);
  assert.equal(defaults.max, 20);
  assert.equal(defaults.query_timeout, undefined, 'Client-only timeout must not masquerade as SQL cancellation');
  assert.equal(typeof defaults.verify, 'function');
  for (const value of [undefined, '', '0', '-1', 'junk', '30seconds', '600001']) {
    assert.equal(getStatementDeadlineMs({PG_STATEMENT_TIMEOUT_MS: value}), 30000);
  }
  assert.equal(getStatementDeadlineMs({PG_STATEMENT_TIMEOUT_MS: '60000'}), 60000);
});

test('pool verification awaits the server deadline configuration and preserves stricter settings', async () => {
  const options = buildPoolOptions({PG_STATEMENT_TIMEOUT_MS: '30000'});
  let finish; let verified = false; let config;
  const client = {query(query) { config=query; return new Promise(resolve => {finish=resolve;}); }};
  const done = new Promise((resolve,reject) => options.verify(client, error => {
    verified=true; if(error) reject(error); else resolve();
  }));
  assert.equal(verified, false);
  assert.match(config.text, /LEAST/);
  assert.match(config.text, /statement_timeout/);
  assert.deepEqual(config.values, ['30000']);
  assert.equal(config.query_timeout, 5000);
  finish({rows:[{}]}); await done; assert.equal(verified, true);
});

test('configuration failure rejects pool verification so an unbounded client is not handed out', async () => {
  const failure = new Error('connection lost');
  const options = buildPoolOptions({});
  await assert.rejects(new Promise((resolve,reject) => {
    options.verify({query: async () => {throw failure;}}, error => error ? reject(error) : resolve());
  }), error => error === failure);
});
