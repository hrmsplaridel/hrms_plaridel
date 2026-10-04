'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { HealthMonitor, createProbe, cpuUsage, diskUsage, warningsFor } = require('../src/services/systemHealth');

test('CPU measures elapsed busy time and handles missing/reset counters', () => {
  assert.equal(cpuUsage({ idle: 100, total: 200 }, { idle: 125, total: 300 }), 75);
  assert.equal(cpuUsage(null, { idle: 125, total: 300 }), null);
  assert.equal(cpuUsage({ idle: 100, total: 200 }, { idle: 0, total: 0 }), null);
});

test('disk reports available space separately from used blocks', () => {
  assert.deepEqual(diskUsage({ bsize: 10, blocks: 100, bfree: 30, bavail: 20 }), {
    totalBytes: 1000, usedBytes: 700, availableBytes: 200, percent: 70,
  });
  assert.equal(diskUsage({ bsize: 10, blocks: 0 }), null);
});

test('unavailable readings and database failures generate warnings, never healthy zeroes', () => {
  const warnings = warningsFor({ cpuPercent: null, memory: null, disk: null, database: { online: false } });
  assert.equal(warnings.length, 4);
  assert.ok(warnings.some((w) => w.includes('Database')));
});

test('samples survive restart, expire after seven days, and remain available after probe failure', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hrms-health-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  let time = Date.parse('2026-10-03T00:00:00Z');
  const probe = async () => ({ cpuPercent: 25, memory: { percent: 50 }, disk: { percent: 60 }, database: { online: true, latencyMs: 2 } });
  const monitor = new HealthMonitor({ directory, probe, now: () => time });
  await monitor.initialize();
  await monitor.collect();
  time += 60000;
  await monitor.collect();
  const restarted = new HealthMonitor({ directory, probe, now: () => time });
  await restarted.initialize();
  assert.equal(restarted.snapshot(24).sampleCount, 2);
  time += 8 * 86400000;
  await restarted.collect();
  assert.equal(restarted.snapshot(168).sampleCount, 1);
  restarted.probe = async () => { throw new Error('failed'); };
  time += 180000;
  await restarted.collect();
  assert.equal(restarted.snapshot(24).stale, true);
  assert.equal(restarted.snapshot(24).current.cpuPercent, 25);
});

test('overlapping collection skips a second probe and storage failures are visible', async () => {
  let finish;
  let calls = 0;
  const monitor = new HealthMonitor({ directory: __filename, probe: () => {
    calls++;
    return new Promise((resolve) => { finish = resolve; });
  } });
  const first = monitor.collect();
  await monitor.collect();
  assert.equal(calls, 1);
  finish({ cpuPercent: 10, database: { online: true } });
  await first;
  assert.equal(monitor.snapshot(24).storageHealthy, false);
  assert.equal(monitor.snapshot(24).sampleCount, 1);
});

test('probe records database outage while still measuring host resources', async () => {
  const probe = createProbe({ query: async () => { throw new Error('offline'); } }, __dirname);
  const sample = await probe();
  assert.equal(sample.database.online, false);
  assert.equal(sample.database.latencyMs, null);
  assert.ok(sample.memory.totalBytes > 0);
  assert.ok(sample.disk.totalBytes > 0);
  assert.equal(sample.cpuPercent, null);
});

test('history responses are bounded and preserve missing time buckets', () => {
  const now = Date.now();
  const monitor = new HealthMonitor({ directory: __dirname, probe: async () => ({}), now: () => now });
  monitor.samples = Array.from({ length: 10080 }, (_, i) => ({
    timestamp: now - (10079 - i) * 60000, cpuPercent: 50, warnings: [],
  })).filter((s) => s.timestamp < now - 3 * 3600000 || s.timestamp > now - 3600000);
  const result = monitor.snapshot(168);
  assert.ok(result.history.length <= 337);
  assert.ok(result.history.some((point, i) => i > 0 && point.timestamp - result.history[i - 1].timestamp > result.bucketMs * 1.5));
});

test('health API enforces authentication, super-admin role, ranges, and no-cache', async (t) => {
  const express = require('express');
  const { createSystemHealthRouter } = require('../src/routes/systemHealth');
  const { createAuthMiddleware } = require('../src/middleware/auth');
  const jwt = require('jsonwebtoken');
  const previousSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = 'health-test-only-secret';
  t.after(() => {
    if (previousSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = previousSecret;
  });
  let role = 'employee';
  const authenticate = createAuthMiddleware({ query: async () => ({ rows: [{ id: 'test', role, is_active: true }] }) });
  const app = express();
  app.use('/health', createSystemHealthRouter({ snapshot: (hours) => ({ hours }) }, authenticate));
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/health`;
  assert.equal((await fetch(url)).status, 401);
  const headers = { Authorization: `Bearer ${jwt.sign({ id: 'test' }, process.env.JWT_SECRET)}` };
  for (role of ['employee', 'admin', 'hr']) assert.equal((await fetch(url, { headers })).status, 403);
  role = 'super_admin';
  assert.equal((await fetch(`${url}?hours=999`, { headers })).status, 400);
  for (const hours of [1, 24, 168]) {
    const response = await fetch(`${url}?hours=${hours}`, { headers });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), { hours });
  }
});
