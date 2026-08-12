const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createLocatorSubmissionService,
} = require('../src/services/locatorSubmissionService');

const EMPLOYEE_ID = '00000000-0000-0000-0000-000000000101';
const DEPARTMENT_ID = '00000000-0000-0000-0000-000000000201';
const HEAD_ID = '00000000-0000-0000-0000-000000000301';

function createHarness() {
  const state = {
    queries: [],
    inserts: [],
    notifications: [],
    broadcasts: [],
    history: [],
    reviewSnapshotDates: [],
    released: 0,
    nextId: 1,
  };
  const client = {
    async query(sql, params = []) {
      const text = String(sql);
      state.queries.push(text);
      if (text.includes('INSERT INTO locator_slips')) {
        const row = {
          id: 'locator-' + state.nextId++,
          employee_id: params[0],
          department_id: params[1],
          slip_date: params[2],
          am_in: params[3],
          am_out: params[4],
          pm_in: params[5],
          pm_out: params[6],
          request_type: params[7],
          request_type_label_snapshot: params[15],
          request_type_short_label_snapshot: params[16],
          request_type_location_label_snapshot: params[17],
          request_type_location_hint_snapshot: params[18],
          request_type_dtr_slot_label_snapshot: params[19],
          request_type_dtr_print_label_snapshot: params[20],
          request_type_requires_attachment_snapshot: params[21],
          request_type_coverage_mode_snapshot: params[22],
          office: params[8],
          reason: params[9],
          attachment_name: params[10],
          attachment_path: params[11],
          attachment_mime_type: params[12],
          status: params[13],
          assigned_department_head_id: params[14],
        };
        state.inserts.push({ params, row });
        return { rows: [row], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
    release() {
      state.released += 1;
    },
  };
  const dbPool = {
    async connect() {
      return client;
    },
    async query() {
      return { rows: [], rowCount: 0 };
    },
  };
  const service = createLocatorSubmissionService({
    dbPool,
    getReviewSnapshot: async (_client, _employeeId, effectiveDate) => {
      state.reviewSnapshotDates.push(effectiveDate);
      return {
        departmentId: DEPARTMENT_ID,
        departmentHeadUserId: HEAD_ID,
      };
    },
    validateWorkingDay: async () => ({ ok: true }),
    getLocatorTypeByCode: async (_client, code) => ({
      code,
      label:
        code === 'work_from_home'
          ? 'Work From Home'
          : 'Locator / Official Business',
      short_label: code === 'work_from_home' ? 'WFH' : 'Locator',
      location_label:
        code === 'work_from_home' ? 'Work Location' : 'Office / Destination',
      location_hint:
        code === 'work_from_home'
          ? 'Enter work location'
          : 'Enter office or destination',
      dtr_slot_label: code === 'work_from_home' ? 'WFH' : 'On Field',
      dtr_print_label: code === 'work_from_home' ? 'WFH' : 'ON FIELD',
      requires_attachment: code === 'work_from_home',
      coverage_mode: code === 'work_from_home' ? 'wfh' : 'manual',
    }),
    findConflicts: async () => ({
      ok: true,
      code: null,
      message: null,
      conflicts: {},
    }),
    fetchSlipDetails: async (_pool, id) => {
      const inserted = state.inserts.find((entry) => entry.row.id === id)?.row;
      return inserted
        ? { ...inserted, employee_name: 'Test Employee' }
        : null;
    },
    mapInsertedRow: (row) => row,
    notifyAfterSubmit: async (_pool, payload) => {
      state.notifications.push(payload);
    },
    broadcastSubmitted: (row) => {
      state.broadcasts.push(row);
    },
    recordHistory: async (_client, event) => {
      state.history.push(event);
    },
    nowProvider: () => new Date('2026-08-11T00:00:00.000Z'),
    logger: { error() {} },
  });
  return { service, state };
}

function validInput(overrides = {}) {
  return {
    employeeUserId: EMPLOYEE_ID,
    slipDate: '2026-08-12',
    office: 'Municipal Hall',
    reason: 'Official meeting',
    requestType: 'locator',
    amIn: true,
    amOut: true,
    pmIn: false,
    pmOut: false,
    ...overrides,
  };
}

test('plain and multipart locator submissions share reviewer notifications', async () => {
  const { service, state } = createHarness();

  await service.submit(validInput());
  await service.submit(validInput({
    requestType: 'work_from_home',
    attachment: {
      name: 'support.pdf',
      path: 'locator-attachments/support.pdf',
      mimeType: 'application/pdf',
    },
  }));

  assert.equal(state.inserts.length, 2);
  assert.equal(state.notifications.length, 2);
  assert.equal(state.broadcasts.length, 2);
  assert.equal(state.history.length, 2);
  assert.equal(state.released, 2);
  assert.deepEqual(
    state.notifications.map((item) => item.status),
    ['pending_department_head', 'pending_department_head']
  );
  assert.deepEqual(
    state.notifications.map((item) => item.departmentHeadUserId),
    [HEAD_ID, HEAD_ID]
  );
  assert.deepEqual(
    state.history.map((item) => ({
      action: item.action,
      toStatus: item.toStatus,
      actorId: item.actorId,
      actorRole: item.actorRole,
    })),
    [
      {
        action: 'submitted',
        toStatus: 'pending_department_head',
        actorId: EMPLOYEE_ID,
        actorRole: 'employee',
      },
      {
        action: 'submitted',
        toStatus: 'pending_department_head',
        actorId: EMPLOYEE_ID,
        actorRole: 'employee',
      },
    ]
  );
  assert.equal(state.inserts[0].row.attachment_path, null);
  assert.equal(
    state.inserts[0].row.assigned_department_head_id,
    HEAD_ID
  );
  assert.deepEqual(state.reviewSnapshotDates, [
    '2026-08-12',
    '2026-08-12',
  ]);
  assert.equal(
    state.inserts[1].row.attachment_path,
    'locator-attachments/support.pdf'
  );
  assert.equal(
    state.inserts[0].row.request_type_label_snapshot,
    'Locator / Official Business'
  );
  assert.equal(
    state.inserts[0].row.request_type_dtr_print_label_snapshot,
    'ON FIELD'
  );
  assert.equal(
    state.inserts[0].row.request_type_requires_attachment_snapshot,
    false
  );
  assert.equal(
    state.inserts[1].row.request_type_label_snapshot,
    'Work From Home'
  );
  assert.equal(
    state.inserts[1].row.request_type_coverage_mode_snapshot,
    'wfh'
  );
  assert.equal(
    state.queries.filter((sql) => sql === 'COMMIT').length,
    2
  );
});

test('attachment-required locator types still fail before insertion without a file', async () => {
  const { service, state } = createHarness();

  await assert.rejects(
    () => service.submit(validInput({ requestType: 'work_from_home' })),
    (error) =>
      error.statusCode === 400 &&
      error.payload?.error === 'Attachment is required for this locator type.'
  );

  assert.equal(state.inserts.length, 0);
  assert.equal(state.notifications.length, 0);
  assert.equal(state.broadcasts.length, 0);
  assert.equal(state.queries.includes('ROLLBACK'), true);
});

test('employee submission blocks past dates before opening a transaction', async () => {
  const { service, state } = createHarness();

  await assert.rejects(
    () => service.submit(validInput({ slipDate: '2026-08-10' })),
    (error) =>
      error.statusCode === 409 &&
      error.payload?.code === 'locator_past_date_not_allowed'
  );

  assert.equal(state.inserts.length, 0);
  assert.equal(state.queries.length, 0);
});
