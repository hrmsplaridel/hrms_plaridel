'use strict';
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { performance } = require('node:perf_hooks');

const RETENTION_MS = 7 * 86400000;
const SAMPLE_MS = 60000;
const percent = (used, total) => Math.round(Math.max(0, Math.min(100, used / total * 100)) * 10) / 10;

function cpuCounters() {
  const cpus = os.cpus();
  if (!cpus.length) return null;
  return cpus.reduce((sum, cpu) => ({
    idle: sum.idle + cpu.times.idle,
    total: sum.total + Object.values(cpu.times).reduce((a, b) => a + b, 0),
  }), { idle: 0, total: 0 });
}

function cpuUsage(previous, current) {
  if (!previous || !current || current.total <= previous.total || current.idle < previous.idle) return null;
  const elapsed = current.total - previous.total;
  return percent(elapsed - (current.idle - previous.idle), elapsed);
}

function diskUsage(stats) {
  const totalBytes = stats.bsize * stats.blocks;
  if (!Number.isFinite(totalBytes) || totalBytes <= 0) return null;
  const usedBytes = stats.bsize * (stats.blocks - stats.bfree);
  return { totalBytes, usedBytes, availableBytes: stats.bsize * stats.bavail, percent: percent(usedBytes, totalBytes) };
}

function warningsFor(sample) {
  const warnings = [];
  for (const [name, value, threshold] of [
    ['CPU', sample.cpuPercent, 85], ['Memory', sample.memory?.percent, 90], ['Disk', sample.disk?.percent, 85],
  ]) {
    if (value == null) warnings.push(`${name} reading unavailable`);
    else if (value >= threshold) warnings.push(`${name} usage is ${value}%`);
  }
  if (sample.disk?.totalBytes > 0 && sample.disk.availableBytes / sample.disk.totalBytes < 0.1) {
    warnings.push('Disk available space is below 10%');
  }
  if (!sample.database?.online) warnings.push('Database connection failed');
  else if (sample.database.latencyMs >= 1000) warnings.push('Database response is slow');
  return warnings;
}

function createProbe(database, diskPath) {
  let previous = null;
  return async () => {
    const counters = cpuCounters();
    const cpuPercent = cpuUsage(previous, counters);
    previous = counters;
    const totalBytes = os.totalmem();
    const usedBytes = totalBytes - os.freemem();
    const memory = totalBytes > 0 ? { totalBytes, usedBytes, percent: percent(usedBytes, totalBytes) } : null;
    const [disk, db] = await Promise.all([
      fs.statfs(diskPath).then(diskUsage).catch(() => null),
      (async () => {
        const start = performance.now();
        try {
          await database.query('SELECT 1');
          return { online: true, latencyMs: Math.round((performance.now() - start) * 10) / 10 };
        } catch {
          return { online: false, latencyMs: null };
        }
      })(),
    ]);
    return { cpuPercent, memory, disk, database: db, uptimeSeconds: Math.floor(process.uptime()) };
  };
}

class HealthMonitor {
  constructor({ directory, probe, now = Date.now }) {
    this.directory = directory;
    this.file = path.join(directory, 'samples.json');
    this.probe = probe;
    this.now = now;
    this.samples = [];
    this.storageHealthy = true;
    this.collecting = false;
  }

  prune() {
    const now = this.now();
    this.samples = this.samples.filter((s) => s.timestamp > now - RETENTION_MS && s.timestamp <= now).slice(-10081);
  }

  async initialize() {
    try {
      const stored = JSON.parse(await fs.readFile(this.file, 'utf8'));
      if (!Array.isArray(stored)) throw new Error('Invalid health history');
      this.samples = stored.filter((s) => s && Number.isFinite(s.timestamp) && s.database && Array.isArray(s.warnings));
      this.samples.sort((a, b) => a.timestamp - b.timestamp);
      this.prune();
    } catch (error) {
      if (error.code !== 'ENOENT') this.storageHealthy = false;
    }
  }

  async collect() {
    if (this.collecting) return;
    this.collecting = true;
    try {
      const reading = await this.probe();
      this.samples.push({ ...reading, timestamp: this.now(), warnings: warningsFor(reading) });
      this.prune();
      try {
        await fs.mkdir(this.directory, { recursive: true });
        await fs.writeFile(`${this.file}.tmp`, JSON.stringify(this.samples), { mode: 0o600 });
        await fs.rename(`${this.file}.tmp`, this.file);
        this.storageHealthy = true;
      } catch {
        this.storageHealthy = false;
      }
    } catch {
      // Preserve the last reading; snapshot marks it stale instead of inventing healthy data.
    } finally {
      this.collecting = false;
    }
  }

  async start() {
    await this.initialize();
    await this.collect();
    this.timer = setInterval(() => void this.collect(), SAMPLE_MS);
    this.timer.unref();
  }

  stop() { clearInterval(this.timer); }

  snapshot(hours) {
    this.prune();
    const now = this.now();
    const selected = this.samples.filter((s) => s.timestamp >= now - hours * 3600000);
    // Bounded response: average each time bucket, leaving absent buckets as gaps in the UI.
    const bucketMs = Math.max(SAMPLE_MS, hours * 3600000 / 336);
    const buckets = new Map();
    for (const sample of selected) {
      const key = Math.floor(sample.timestamp / bucketMs) * bucketMs;
      if (!buckets.has(key)) buckets.set(key, []);
      buckets.get(key).push(sample);
    }
    const average = (rows, read) => {
      const values = rows.map(read).filter(Number.isFinite);
      return values.length ? Math.round(values.reduce((a, b) => a + b, 0) / values.length * 10) / 10 : null;
    };
    const history = [...buckets].map(([timestamp, rows]) => ({
      timestamp,
      cpuPercent: average(rows, (s) => s.cpuPercent),
      memoryPercent: average(rows, (s) => s.memory?.percent),
      diskPercent: average(rows, (s) => s.disk?.percent),
    }));
    const current = this.samples.at(-1) || null;
    return {
      current, history, bucketMs, sampleCount: selected.length,
      stale: !current || now - current.timestamp > SAMPLE_MS * 2,
      storageHealthy: this.storageHealthy,
      recentWarnings: selected.filter((s) => s.warnings.length).slice(-20).reverse()
        .map((s) => ({ timestamp: s.timestamp, messages: s.warnings })),
      generatedAt: now,
    };
  }
}

module.exports = { HealthMonitor, createProbe, cpuUsage, diskUsage, warningsFor };
