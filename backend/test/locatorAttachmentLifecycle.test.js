const test = require('node:test');
const assert = require('node:assert/strict');

const {
  deleteLocatorAttachment,
  replaceLocatorAttachment,
} = require('../src/services/locatorAttachmentLifecycle');

const SLIP_ID = '00000000-0000-4000-8000-000000000001';
const EMPLOYEE_ID = '00000000-0000-4000-8000-000000000002';
const OLD_PATH = 'locator-attachments/old.pdf';
const NEW_PATH = 'locator-attachments/new.pdf';

function createHarness({
  row = {
    id: SLIP_ID,
    employee_id: EMPLOYEE_ID,
    status: 'returned_for_correction',
    attachment_path: OLD_PATH,
  },
  failUpdate = false,
  failConnect = false,
} = {}) {
  const events = [];
  const removed = [];
  const client = {
    async query(sql) {
      const text = String(sql).trim();
      events.push(text);
      if (text.startsWith('SELECT')) {
        return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
      }
      if (text.startsWith('UPDATE') && failUpdate) {
        throw new Error('database update failed');
      }
      return { rows: [], rowCount: 1 };
    },
    release() {
      events.push('RELEASE');
    },
  };
  const dbPool = {
    async connect() {
      events.push('CONNECT');
      if (failConnect) throw new Error('database unavailable');
      return client;
    },
  };
  const removeFile = (filePath) => {
    removed.push(filePath);
    events.push(`REMOVE ${filePath}`);
  };
  return { dbPool, events, removed, removeFile };
}

const canModifyStatus = (status) => status === 'returned_for_correction';
const attachment = {
  name: 'new.pdf',
  path: NEW_PATH,
  mimeType: 'application/pdf',
};

test('replacement locks the row and removes the old file only after commit', async () => {
  const harness = createHarness();

  const result = await replaceLocatorAttachment({
    dbPool: harness.dbPool,
    slipId: SLIP_ID,
    employeeId: EMPLOYEE_ID,
    attachment,
    canModifyStatus,
    removeFile: harness.removeFile,
  });

  const select = harness.events.find((event) => event.startsWith('SELECT'));
  assert.match(select, /FOR UPDATE/);
  assert.ok(
    harness.events.indexOf('COMMIT') <
      harness.events.indexOf(`REMOVE ${OLD_PATH}`)
  );
  assert.deepEqual(harness.removed, [OLD_PATH]);
  assert.equal(result.attachment_path, NEW_PATH);
});

test('failed replacement rolls back and removes only the new upload', async () => {
  const harness = createHarness({ failUpdate: true });

  await assert.rejects(
    () =>
      replaceLocatorAttachment({
        dbPool: harness.dbPool,
        slipId: SLIP_ID,
        employeeId: EMPLOYEE_ID,
        attachment,
        canModifyStatus,
        removeFile: harness.removeFile,
      }),
    /database update failed/
  );

  assert.equal(harness.events.includes('ROLLBACK'), true);
  assert.equal(harness.events.includes('COMMIT'), false);
  assert.deepEqual(harness.removed, [NEW_PATH]);
});

test('connection failure still removes the newly uploaded file', async () => {
  const harness = createHarness({ failConnect: true });

  await assert.rejects(
    () =>
      replaceLocatorAttachment({
        dbPool: harness.dbPool,
        slipId: SLIP_ID,
        employeeId: EMPLOYEE_ID,
        attachment,
        canModifyStatus,
        removeFile: harness.removeFile,
      }),
    /database unavailable/
  );

  assert.deepEqual(harness.removed, [NEW_PATH]);
});

test('locked requests reject replacement and clean the new upload', async () => {
  const harness = createHarness({
    row: {
      id: SLIP_ID,
      employee_id: EMPLOYEE_ID,
      status: 'pending_hr',
      attachment_path: OLD_PATH,
    },
  });

  await assert.rejects(
    () =>
      replaceLocatorAttachment({
        dbPool: harness.dbPool,
        slipId: SLIP_ID,
        employeeId: EMPLOYEE_ID,
        attachment,
        canModifyStatus,
        removeFile: harness.removeFile,
      }),
    (error) => error.statusCode === 409
  );

  assert.equal(harness.events.includes('ROLLBACK'), true);
  assert.deepEqual(harness.removed, [NEW_PATH]);
});

test('attachment deletion commits before removing the physical file', async () => {
  const harness = createHarness();

  await deleteLocatorAttachment({
    dbPool: harness.dbPool,
    slipId: SLIP_ID,
    employeeId: EMPLOYEE_ID,
    canModifyStatus,
    removeFile: harness.removeFile,
  });

  const select = harness.events.find((event) => event.startsWith('SELECT'));
  assert.match(select, /FOR UPDATE/);
  assert.ok(
    harness.events.indexOf('COMMIT') <
      harness.events.indexOf(`REMOVE ${OLD_PATH}`)
  );
  assert.deepEqual(harness.removed, [OLD_PATH]);
});
