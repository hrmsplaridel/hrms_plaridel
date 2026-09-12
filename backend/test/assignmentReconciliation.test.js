const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

const {
  affectedAssignmentDateRange,
} = require('../src/services/assignmentReconciliation');

test('historical assignment changes cover the union of old and new effective periods', () => {
  const range = affectedAssignmentDateRange(
    { effective_from: '2026-06-16', effective_to: '2026-07-31' },
    { effective_from: '2026-07-01', effective_to: null },
    { today: '2026-08-28' }
  );

  assert.deepEqual(range, {
    dateFrom: '2026-06-16',
    dateTo: '2026-08-28',
  });
});

test('future-only assignment changes do not rebuild DTR or queue month-end work', () => {
  const range = affectedAssignmentDateRange(
    { effective_from: '2026-09-01', effective_to: null },
    { effective_from: '2026-10-01', effective_to: null },
    { today: '2026-08-28' }
  );

  assert.equal(range, null);
});

async function withRebuildService({ fail = false } = {}, callback) {
  const calls = [];
  const restore = withMockedModule('../src/services/biometricProcessing', {
    processBiometricLogsToSummary: async (...args) => {
      calls.push(['rebuild', ...args]);
      if (fail) throw new Error('Simulated rebuild failure');
      return { inserted: 1, updated: 2 };
    },
  });
  const restoreCache = withMockedModule('../src/services/attendancePolicyCache', {
    invalidateAttendancePolicyCache: (options) => calls.push(['clear', options]),
  });
  const path = '../src/services/assignmentReconciliation';
  clearModule(path);
  try {
    await callback(require(path), calls);
  } finally {
    clearModule(path);
    restoreCache();
    restore();
  }
}

const queuedCorrection = {
  range: { dateFrom: '2026-07-01', dateTo: '2026-07-31' },
  count: 1,
  months: ['2026-07'],
};

test('saved historical assignment rebuild clears cached policy before processing the affected range', async () => {
  await withRebuildService({}, async (service, calls) => {
    const result = await service.rebuildAfterAssignmentCommit('employee-1', queuedCorrection);
    assert.deepEqual(calls, [
      ['clear', { employeeId: 'employee-1', ...queuedCorrection.range }],
      ['rebuild', ['employee-1'], '2026-07-01', '2026-07-31'],
    ]);
    assert.equal(result.dtr_rows_inserted, 1);
    assert.equal(result.dtr_rows_rebuilt, 2);
    assert.equal(result.required, true);
    assert.deepEqual(result.queued_months, ['2026-07']);
  });
});

test('failed immediate rebuild retains queued reconciliation and returns a warning', async () => {
  await withRebuildService({ fail: true }, async (service) => {
    const result = await service.rebuildAfterAssignmentCommit('employee-1', queuedCorrection);
    assert.equal(result.required, true);
    assert.deepEqual(result.queued_months, ['2026-07']);
    assert.match(result.warning, /retry during reconciliation/);
  });
});

test('no affected assignment range skips cache clearing and biometric rebuilding', async () => {
  await withRebuildService({}, async (service, calls) => {
    const result = await service.rebuildAfterAssignmentCommit('employee-1', { range: null });
    assert.deepEqual(result, { required: false, queued_months: [] });
    assert.deepEqual(calls, []);
  });
});
