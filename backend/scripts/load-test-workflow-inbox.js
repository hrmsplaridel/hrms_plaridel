'use strict';
// Local, disposable PostgreSQL + real HTTP/auth/rate-limit stack. Never targets production.
const {Client, Pool} = require('pg');
const express = require('express');
const jwt = require('jsonwebtoken');
const {randomBytes} = require('node:crypto');
const {performance, monitorEventLoopDelay} = require('node:perf_hooks');
const {seed} = require('../test/helpers/workflowInboxFixture');
const {listInbox} = require('../src/services/sharedWorkflowInbox');
const {buildPoolOptions} = require('../src/config/databasePoolOptions');

function percentile(values, fraction) {return values[Math.min(values.length-1, Math.ceil(values.length*fraction)-1)] || 0;}
async function main() {
  require('dotenv').config({path: require('node:path').resolve(__dirname, '../.env'), quiet: true});
  const source = new URL(process.env.WORKFLOW_LOAD_TEST_DATABASE_URL || process.env.DATABASE_URL);
  if (!['localhost','127.0.0.1'].includes(source.hostname) || source.port !== '5433' || source.pathname !== '/hrms_plaridel')
    throw Error('Load test requires the local localhost:5433/hrms_plaridel connection for disposable-database creation.');
  const name = 'hrms_inbox_load_' + randomBytes(8).toString('hex');
  const maintenance = new Client({connectionString: source.toString()});
  let pool, server, created = false;
  const oldSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = randomBytes(32).toString('hex');
  try {
    await maintenance.connect();
    await maintenance.query(`CREATE DATABASE "${name}" TEMPLATE template0`); created = true;
    const testUrl = new URL(source); testUrl.pathname = '/' + name;
    pool = new Pool(buildPoolOptions({...process.env, DATABASE_URL: testUrl.toString(), PG_POOL_MAX: '20'}));
    const verification = require('node:child_process').spawnSync(process.execPath,
      ['--test', require('node:path').resolve(__dirname, '../test/workflowInboxPostgres.integration.test.js'),
        require('node:path').resolve(__dirname, '../test/workflowRoutingAuditPostgres.integration.test.js')],
      {env: {...process.env, WORKFLOW_INBOX_TEST_DATABASE_URL: testUrl.toString(), WORKFLOW_AUDIT_TEST_DATABASE_URL: testUrl.toString()}, encoding: 'utf8', timeout: 120000});
    process.stdout.write(verification.stdout || '');
    if (verification.status !== 0) throw Error('PostgreSQL correctness checks failed: ' + (verification.stderr || '').slice(0, 1000));
    const actors = await seed(pool);
    let queryCount = 0, maxWaiting = 0;
    const db = {query: (...args) => {queryCount++; maxWaiting = Math.max(maxWaiting, pool.waitingCount); return pool.query(...args);}};
    const {createApiRateLimits} = require('../src/middleware/rateLimiters');
    const {createAuthMiddleware} = require('../src/middleware/auth');
    const app = express();
    app.use('/api', ...createApiRateLimits({db}));
    app.get('/api/approval-workflows/inbox', createAuthMiddleware(db), async (req,res) => {
      try {res.json(await listInbox(db, req.user, {paginated: req.query.paginated === 'true', includeHistory: true, limit: 50}));}
      catch (error) {res.status(error.statusCode || 500).json({error: 'Load-test request failed'});}
    });
    server = await new Promise(resolve => {const s = app.listen(0, '127.0.0.1', () => resolve(s));});
    const base = `http://127.0.0.1:${server.address().port}/api/approval-workflows/inbox`;
    const tokens = actors.map(actor => jwt.sign({id: actor.id, typ: 'access', auth_version: 0}, process.env.JWT_SECRET, {expiresIn: '10m'}));
    const phases = [];
    const eventLoop = monitorEventLoopDelay({resolution: 10}); eventLoop.enable();
    for (const users of [10,25,50]) {
      const latencies = [], statuses = {}, bytes = [];
      queryCount = 0; maxWaiting = 0;
      const started = performance.now();
      for (let wave = 0; wave < 10; wave++) {
        await Promise.all(tokens.slice(0, users).map(async token => {
          const start = performance.now();
          const response = await fetch(base + '?paginated=true', {headers: {Authorization: 'Bearer ' + token}, signal: AbortSignal.timeout(45000)});
          const text = await response.text();
          latencies.push(performance.now() - start);
          statuses[response.status] = (statuses[response.status] || 0) + 1;
          bytes.push(Buffer.byteLength(text));
          if (response.ok) {
            const data = JSON.parse(text);
            if (!Array.isArray(data.items) || data.items.length > 100) throw Error('Unbounded or invalid paged response');
          }
        }));
      }
      const elapsed = performance.now() - started;
      latencies.sort((a,b) => a-b);
      const phase = {users, requests: latencies.length, statuses, duration_ms: Math.round(elapsed),
        requests_per_second: +(latencies.length*1000/elapsed).toFixed(1),
        p50_ms: +percentile(latencies,.5).toFixed(1),p95_ms: +percentile(latencies,.95).toFixed(1),
        p99_ms: +percentile(latencies,.99).toFixed(1),queries_per_request: +(queryCount/latencies.length).toFixed(1),
        mean_response_bytes: Math.round(bytes.reduce((a,b)=>a+b,0)/bytes.length),max_pool_waiting: maxWaiting};
      phases.push(phase); console.log(JSON.stringify(phase));
    }
    const actor = actors[0]; let queries = 0;
    const counted = {query: (...args) => {queries++; return pool.query(...args);}};
    const all = await listInbox(counted, actor, {includeHistory: true});
    const counts = (await pool.query('SELECT (SELECT count(*)::int FROM leave_requests) AS leave,(SELECT count(*)::int FROM locator_slips) AS locator')).rows[0];
    const report = {target: 'disposable local database',same_network: 'all requests originate from 127.0.0.1',
      pool_max: 20, synthetic_reviewers: actors.length, synthetic_requests: counts, phases,
      legacy_comparison: {rows: all.length,bytes: Buffer.byteLength(JSON.stringify(all)),queries},
      event_loop_p95_ms: +(eventLoop.percentile(95)/1e6).toFixed(1),peak_rss_mb: +(process.resourceUsage().maxRSS/1024).toFixed(1),
      limitations: 'Loopback API benchmark; excludes Ubuntu hardware, Nginx/Cloudflare, Flutter rendering and other endpoints.'};
    eventLoop.disable();
    console.log(JSON.stringify({summary: report}));
    if (phases.some(phase => Object.keys(phase.statuses).some(status => status !== '200'))) process.exitCode = 1;
  } finally {
    if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
    if (pool) await pool.end();
    if (created && /^hrms_inbox_load_[a-f0-9]{16}$/.test(name)) await maintenance.query(`DROP DATABASE "${name}" WITH (FORCE)`);
    await maintenance.end();
    if (oldSecret === undefined) delete process.env.JWT_SECRET; else process.env.JWT_SECRET = oldSecret;
  }
}
if (require.main === module) main().catch(error => {console.error(error.message.replace(/postgres(?:ql)?:\/\/\S+/g, '[database URL]'));process.exitCode=1;});
module.exports = {percentile};
