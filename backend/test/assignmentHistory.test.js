const test = require('node:test');
const assert = require('node:assert/strict');

const {
  AssignmentHistoryError,
  deactivateAssignmentRecord,
  permanentlyDeleteFutureAssignment,
  repairPrimaryPredecessorAfterFutureChange,
} = require('../src/services/assignmentHistory');

const ACTOR_ID = '11111111-1111-4111-8111-111111111111';
const RECORD_ID = '22222222-2222-4222-8222-222222222222';

test('primary assignment deactivation preserves the row and writes before/after audit data', async () => {
  const calls = [];
  const before = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-06-01',
    effective_to: '2026-06-30',
    is_active: true,
  };
  const after = { ...before, is_active: false };
  const db = {
    async query(sql, params) {
      calls.push({ sql: String(sql), params });
      if (/^\s*SELECT \*/i.test(sql)) return { rowCount: 1, rows: [before] };
      if (/^\s*UPDATE assignments/i.test(sql)) {
        return { rowCount: 1, rows: [after] };
      }
      if (/^\s*INSERT INTO audit_logs/i.test(sql)) {
        return { rowCount: 1, rows: [] };
      }
      if (/AS is_future/i.test(sql)) {
        return { rowCount: 1, rows: [{ is_future: false }] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };

  const result = await deactivateAssignmentRecord(db, {
    actorId: ACTOR_ID,
    recordType: 'primary',
    recordId: RECORD_ID,
    reason: 'Incorrect assignment was selected.',
  });

  assert.equal(result.changed, true);
  assert.equal(result.record.is_active, false);
  assert.equal(calls.some(({ sql }) => /DELETE FROM/i.test(sql)), false);
  assert.match(calls[1].sql, /SET is_active = false/i);
  assert.equal(calls[2].params[0], ACTOR_ID);
  assert.equal(calls[2].params[1], 'assignment_deactivated');
  const details = JSON.parse(calls[2].params[4]);
  assert.equal(details.reason, 'Incorrect assignment was selected.');
  assert.deepEqual(details.before, before);
  assert.deepEqual(details.after, after);
});

test('additional-position deactivation uses the same non-destructive audit workflow', async () => {
  const calls = [];
  const before = { id: RECORD_ID, is_active: true, position_id: ACTOR_ID };
  const after = { ...before, is_active: false };
  const db = {
    async query(sql, params) {
      calls.push({ sql: String(sql), params });
      if (/^\s*SELECT \*/i.test(sql)) return { rowCount: 1, rows: [before] };
      if (/^\s*UPDATE employee_other_positions/i.test(sql)) {
        return { rowCount: 1, rows: [after] };
      }
      return { rowCount: 1, rows: [] };
    },
  };

  await deactivateAssignmentRecord(db, {
    actorId: ACTOR_ID,
    recordType: 'additional',
    recordId: RECORD_ID,
    reason: 'Duplicate additional designation.',
  });

  assert.equal(calls.some(({ sql }) => /DELETE FROM/i.test(sql)), false);
  assert.match(calls[1].sql, /UPDATE employee_other_positions/i);
  assert.equal(calls[2].params[1], 'employee_other_position_deactivated');
});

test('assignment deactivation rejects a missing reason before changing data', async () => {
  let queryCount = 0;
  const db = {
    async query() {
      queryCount += 1;
      return { rowCount: 0, rows: [] };
    },
  };

  await assert.rejects(
    deactivateAssignmentRecord(db, {
      actorId: ACTOR_ID,
      recordType: 'primary',
      recordId: RECORD_ID,
      reason: '  ',
    }),
    (error) =>
      error instanceof AssignmentHistoryError && error.statusCode === 400
  );
  assert.equal(queryCount, 0);
});

test('already inactive assignment is not changed or audited again', async () => {
  const calls = [];
  const before = { id: RECORD_ID, is_active: false };
  const db = {
    async query(sql, params) {
      calls.push({ sql: String(sql), params });
      return { rowCount: 1, rows: [before] };
    },
  };

  const result = await deactivateAssignmentRecord(db, {
    actorId: ACTOR_ID,
    recordType: 'primary',
    recordId: RECORD_ID,
    reason: 'Already inactive retry.',
  });

  assert.equal(result.changed, false);
  assert.equal(calls.length, 1);
});

test('unused future primary assignment can be deleted and its predecessor is restored', async () => {
  const calls = [];
  const target = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-10-01',
    effective_to: null,
    is_active: true,
  };
  const predecessor = {
    id: '44444444-4444-4444-8444-444444444444',
    employee_id: target.employee_id,
    effective_from: '2026-01-01',
    effective_to: '2026-09-30',
    is_active: true,
  };
  const restored = { ...predecessor, effective_to: null };
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ sql: text, params });
      if (/SELECT \* FROM assignments WHERE id/i.test(text)) {
        return { rowCount: 1, rows: [target] };
      }
      if (/AS is_future/i.test(text)) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (/AS has_dtr/i.test(text)) {
        return {
          rowCount: 1,
          rows: [{ has_dtr: false, has_leave: false, has_locator: false }],
        };
      }
      if (/^\s*DELETE FROM assignments/i.test(text)) {
        return { rowCount: 1, rows: [] };
      }
      if (/effective_to = \(\$3::date - INTERVAL/i.test(text)) {
        return { rowCount: 1, rows: [predecessor] };
      }
      if (/^\s*UPDATE assignments/i.test(text)) {
        return { rowCount: 1, rows: [restored] };
      }
      if (/^\s*INSERT INTO audit_logs/i.test(text)) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await permanentlyDeleteFutureAssignment(db, {
    actorId: ACTOR_ID,
    recordType: 'primary',
    recordId: RECORD_ID,
    reason: 'Future transfer was entered for the wrong employee.',
  });

  assert.equal(result.deleted.id, RECORD_ID);
  assert.deepEqual(result.restoredPredecessor.after, restored);
  assert.equal(
    calls.filter(({ sql }) => /^\s*INSERT INTO audit_logs/i.test(sql)).length,
    2
  );
  assert.ok(calls.some(({ sql }) => /^\s*DELETE FROM assignments/i.test(sql)));
});

test('future primary assignment with dependent leave is not permanently deleted', async () => {
  const calls = [];
  const target = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-10-01',
    effective_to: null,
    is_active: true,
  };
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ sql: text, params });
      if (/SELECT \* FROM assignments WHERE id/i.test(text)) {
        return { rowCount: 1, rows: [target] };
      }
      if (/AS is_future/i.test(text)) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (/AS has_dtr/i.test(text)) {
        return {
          rowCount: 1,
          rows: [{ has_dtr: false, has_leave: true, has_locator: false }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await assert.rejects(
    permanentlyDeleteFutureAssignment(db, {
      actorId: ACTOR_ID,
      recordType: 'primary',
      recordId: RECORD_ID,
      reason: 'Mistaken future assignment.',
    }),
    (error) =>
      error instanceof AssignmentHistoryError &&
      error.statusCode === 409 &&
      /leave requests/i.test(error.message)
  );
  assert.equal(calls.some(({ sql }) => /^\s*DELETE FROM/i.test(sql)), false);
});

test('started assignment cannot be permanently deleted', async () => {
  const target = {
    id: RECORD_ID,
    effective_from: '2026-08-01',
    is_active: true,
  };
  let queryIndex = 0;
  const db = {
    async query() {
      queryIndex += 1;
      if (queryIndex === 1) return { rowCount: 1, rows: [target] };
      return { rowCount: 1, rows: [{ is_future: false }] };
    },
  };

  await assert.rejects(
    permanentlyDeleteFutureAssignment(db, {
      actorId: ACTOR_ID,
      recordType: 'additional',
      recordId: RECORD_ID,
      reason: 'Incorrect row.',
    }),
    (error) =>
      error instanceof AssignmentHistoryError && error.statusCode === 409
  );
  assert.equal(queryIndex, 2);
});

test('moving an open-ended future transfer later extends its predecessor to the new boundary', async () => {
  const previous = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-09-01',
    effective_to: null,
    is_active: true,
  };
  const replacement = { ...previous, effective_from: '2026-10-01' };
  const predecessor = {
    id: '44444444-4444-4444-8444-444444444444',
    employee_id: previous.employee_id,
    effective_from: '2026-01-01',
    effective_to: '2026-08-31',
    is_active: true,
  };
  const calls = [];
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (/AS is_future/i.test(text)) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (/effective_to = \(\$3::date - INTERVAL/i.test(text)) {
        return { rowCount: 1, rows: [predecessor] };
      }
      if (/^\s*UPDATE assignments/i.test(text)) {
        return {
          rowCount: 1,
          rows: [{ ...predecessor, effective_to: '2026-09-30' }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await repairPrimaryPredecessorAfterFutureChange(db, {
    previousRecord: previous,
    replacementRecord: replacement,
  });

  assert.equal(result.after.effective_to, '2026-09-30');
  const update = calls.find(({ text }) => /^\s*UPDATE assignments/i.test(text));
  assert.equal(update.params[1], '2026-09-30');
});

test('moving a future transfer earlier does not restore the old boundary', async () => {
  const previous = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-10-01',
    effective_to: null,
    is_active: true,
  };
  const calls = [];
  const db = {
    async query(sql) {
      calls.push(String(sql));
      return { rowCount: 1, rows: [{ is_future: true }] };
    },
  };

  const result = await repairPrimaryPredecessorAfterFutureChange(db, {
    previousRecord: previous,
    replacementRecord: { ...previous, effective_from: '2026-09-01' },
  });

  assert.equal(result, null);
  assert.equal(calls.length, 1);
});

test('deactivating an open-ended future transfer reopens its predecessor', async () => {
  const previous = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-10-01',
    effective_to: null,
    is_active: true,
  };
  const predecessor = {
    id: '44444444-4444-4444-8444-444444444444',
    employee_id: previous.employee_id,
    effective_from: '2026-01-01',
    effective_to: '2026-09-30',
    is_active: true,
  };
  const calls = [];
  const db = {
    async query(sql, params) {
      const text = String(sql);
      calls.push({ text, params });
      if (/AS is_future/i.test(text)) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (/effective_to = \(\$3::date - INTERVAL/i.test(text)) {
        return { rowCount: 1, rows: [predecessor] };
      }
      if (/^\s*UPDATE assignments/i.test(text)) {
        return {
          rowCount: 1,
          rows: [{ ...predecessor, effective_to: null }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  const result = await repairPrimaryPredecessorAfterFutureChange(db, {
    previousRecord: previous,
    replacementRecord: { ...previous, is_active: false },
  });

  assert.equal(result.after.effective_to, null);
  const update = calls.find(({ text }) => /^\s*UPDATE assignments/i.test(text));
  assert.equal(update.params[1], null);
});

test('moving a bounded future assignment restores only its original coverage', async () => {
  const previous = {
    id: RECORD_ID,
    employee_id: '33333333-3333-4333-8333-333333333333',
    effective_from: '2026-09-01',
    effective_to: '2026-09-15',
    is_active: true,
  };
  const predecessor = {
    id: '44444444-4444-4444-8444-444444444444',
    employee_id: previous.employee_id,
    effective_from: '2026-01-01',
    effective_to: '2026-08-31',
    is_active: true,
  };
  let restoredTo;
  const db = {
    async query(sql, params) {
      const text = String(sql);
      if (/AS is_future/i.test(text)) {
        return { rowCount: 1, rows: [{ is_future: true }] };
      }
      if (/effective_to = \(\$3::date - INTERVAL/i.test(text)) {
        return { rowCount: 1, rows: [predecessor] };
      }
      if (/^\s*UPDATE assignments/i.test(text)) {
        restoredTo = params[1];
        return {
          rowCount: 1,
          rows: [{ ...predecessor, effective_to: restoredTo }],
        };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    },
  };

  await repairPrimaryPredecessorAfterFutureChange(db, {
    previousRecord: previous,
    replacementRecord: {
      ...previous,
      effective_from: '2026-10-01',
      effective_to: '2026-10-15',
    },
  });

  assert.equal(restoredTo, '2026-09-15');
});
