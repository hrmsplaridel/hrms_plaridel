const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const exportDirectory = fs.mkdtempSync(
  path.join(os.tmpdir(), 'hrms-dtr-assistant-export-test-')
);
process.env.DTR_ASSISTANT_EXPORT_DIR = exportDirectory;

const exportServicePath = require.resolve(
  '../src/services/dtrAssistant/dtrAssistantExportService'
);
let exportService = require(exportServicePath);

const completeContext = {
  date_range: {
    startDate: '2026-08-01',
    endDate: '2026-08-02',
  },
  data_completeness: {
    dtr_records: { complete: true },
    dtr_calendar_days: { complete: true },
    dtr_export: { complete: true },
  },
  dtr_records: [
    {
      attendance_date: '2026-08-01',
      status: 'present',
      time_in: '2026-08-01T08:00:00+08:00',
      time_out: '2026-08-01T17:00:00+08:00',
    },
  ],
  dtr_calendar_days: [
    { attendance_date: '2026-08-01', shift_id: 'shift-1' },
    { attendance_date: '2026-08-02', shift_id: 'shift-1' },
  ],
};

function configure(limits = {}) {
  exportService.__test.setExportStore({
    directory: exportDirectory,
    limits: {
      ttlMs: 15 * 60 * 1000,
      maxEntries: 20,
      maxBytes: 10 * 1024 * 1024,
      maxPerUser: 10,
      ...limits,
    },
  });
}

function clearExports() {
  for (const filename of fs.readdirSync(exportDirectory)) {
    fs.unlinkSync(path.join(exportDirectory, filename));
  }
}

test.after(() => {
  clearExports();
  fs.rmdirSync(exportDirectory);
  delete process.env.DTR_ASSISTANT_EXPORT_DIR;
});

test.beforeEach(() => {
  clearExports();
  configure();
});

test('DTR export store survives a service reload and enforces ownership', () => {
  const attachment = exportService.createDtrExportAttachment(
    completeContext,
    'employee-1',
    'csv'
  );

  delete require.cache[exportServicePath];
  exportService = require(exportServicePath);

  const restored = exportService.getDtrExport(attachment.id, 'employee-1');
  assert.ok(restored);
  assert.match(restored.buffer.toString('utf8'), /2026-08-01/);
  assert.equal(exportService.getDtrExport(attachment.id, 'employee-2'), null);
});

test('separate backend processes share the configured export directory', () => {
  const childEnvironment = {
    ...process.env,
    DTR_ASSISTANT_EXPORT_DIR: exportDirectory,
    DTR_ASSISTANT_EXPORT_TTL_MS: String(15 * 60 * 1000),
  };
  const createScript = `
    const service = require(process.env.EXPORT_SERVICE_PATH);
    const context = JSON.parse(process.env.EXPORT_CONTEXT);
    const attachment = service.createDtrExportAttachment(
      context,
      'employee-process-test',
      'csv'
    );
    process.stdout.write(JSON.stringify(attachment));
  `;
  const created = spawnSync(process.execPath, ['-e', createScript], {
    cwd: __dirname,
    encoding: 'utf8',
    env: {
      ...childEnvironment,
      EXPORT_SERVICE_PATH: exportServicePath,
      EXPORT_CONTEXT: JSON.stringify(completeContext),
    },
  });
  assert.equal(created.status, 0, created.stderr);
  const attachment = JSON.parse(created.stdout);

  const readScript = `
    const service = require(process.env.EXPORT_SERVICE_PATH);
    const stored = service.getDtrExport(
      process.env.EXPORT_TOKEN,
      'employee-process-test'
    );
    process.stdout.write(JSON.stringify({
      found: Boolean(stored),
      content: stored ? stored.buffer.toString('utf8') : null,
    }));
  `;
  const restored = spawnSync(process.execPath, ['-e', readScript], {
    cwd: __dirname,
    encoding: 'utf8',
    env: {
      ...childEnvironment,
      EXPORT_SERVICE_PATH: exportServicePath,
      EXPORT_TOKEN: attachment.id,
    },
  });
  assert.equal(restored.status, 0, restored.stderr);
  const result = JSON.parse(restored.stdout);

  assert.equal(result.found, true);
  assert.match(result.content, /2026-08-01/);
});

test('DTR export store evicts the oldest per-user and global entries', async () => {
  configure({ maxEntries: 3, maxPerUser: 2 });
  const first = exportService.createDtrExportAttachment(
    completeContext,
    'employee-1',
    'csv'
  );
  await new Promise((resolve) => setTimeout(resolve, 3));
  const second = exportService.createDtrExportAttachment(
    completeContext,
    'employee-1',
    'csv'
  );
  await new Promise((resolve) => setTimeout(resolve, 3));
  const third = exportService.createDtrExportAttachment(
    completeContext,
    'employee-1',
    'csv'
  );

  assert.equal(exportService.getDtrExport(first.id, 'employee-1'), null);
  assert.ok(exportService.getDtrExport(second.id, 'employee-1'));
  assert.ok(exportService.getDtrExport(third.id, 'employee-1'));

  await new Promise((resolve) => setTimeout(resolve, 3));
  exportService.createDtrExportAttachment(completeContext, 'employee-2', 'csv');
  await new Promise((resolve) => setTimeout(resolve, 3));
  exportService.createDtrExportAttachment(completeContext, 'employee-3', 'csv');

  assert.equal(exportService.__test.listStoredExports().length, 3);
  assert.equal(exportService.getDtrExport(second.id, 'employee-1'), null);
});

test('DTR export store removes expired files and rejects oversized exports', () => {
  configure({ ttlMs: 1000 });
  const attachment = exportService.createDtrExportAttachment(
    completeContext,
    'employee-1',
    'csv'
  );
  exportService.__test.pruneExpiredExports(Date.now() + 2000);
  assert.equal(exportService.getDtrExport(attachment.id, 'employee-1'), null);

  configure({ maxBytes: 10 });
  assert.throws(
    () =>
      exportService.createDtrExportAttachment(
        completeContext,
        'employee-1',
        'csv'
      ),
    (error) =>
      error.statusCode === 413 &&
      error.code === 'DTR_ASSISTANT_EXPORT_TOO_LARGE'
  );
});

test('DTR export store removes stale interrupted-write files', () => {
  const orphanData = path.join(exportDirectory, `${'a'.repeat(48)}.data`);
  const temporaryFile = path.join(
    exportDirectory,
    `${'b'.repeat(48)}.data.123.partial.tmp`
  );
  fs.writeFileSync(orphanData, 'orphan');
  fs.writeFileSync(temporaryFile, 'partial');
  const oldTime = new Date(Date.now() - 10 * 60 * 1000);
  fs.utimesSync(orphanData, oldTime, oldTime);
  fs.utimesSync(temporaryFile, oldTime, oldTime);

  exportService.__test.pruneStaleOrphans();

  assert.equal(fs.existsSync(orphanData), false);
  assert.equal(fs.existsSync(temporaryFile), false);
});
