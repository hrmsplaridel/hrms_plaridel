'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  ROLE_KEYS,
  configureOfficialSignatory,
  resolveOfficialSignatory,
  resolveDtrReportSignatories,
} = require('../src/services/officialSignatoryService');
const {
  resolveMemoSignatories,
  assertMemoSignatoryAccountsDistinct,
  enforceMemoOfficialSignatoryFields,
} = require('../src/services/docutrackerDocumentBuilderService');

const HR = '11111111-1111-4111-8111-111111111111';
const OFFICE = '22222222-2222-4222-8222-222222222222';
const MAYOR = '33333333-3333-4333-8333-333333333333';
const ACTOR = '44444444-4444-4444-8444-444444444444';

function period(role, employeeId) {
  return {
    id: `period-${role}`,
    role_key: role,
    employee_id: employeeId,
    employee_name_snapshot: role,
    position_title_snapshot: `${role} title`,
    department_name_snapshot: 'Office',
    effective_from: '2026-01-01',
    effective_to: null,
  };
}

function memoClient({ periods = {}, identities = {}, automatic = {} } = {}) {
  const calls = [];
  return {
    calls,
    async query(sql, params) {
      calls.push(sql);
      if (/\b(INSERT|UPDATE|DELETE)\b/i.test(sql)) {
        throw new Error('memorandum viewing must not write rows');
      }
      if (sql.includes('docutracker_official_signatories')) {
        const row = periods[params[0]] || null;
        return { rows: row ? [row] : [] };
      }
      if (sql.includes('mayor_office_staff')) {
        return { rows: automatic.officeId ? [{ id: automatic.officeId }] : [] };
      }
      if (sql.includes('FROM departments')) {
        return { rows: [] };
      }
      if (sql.includes('u.id = $1::uuid')) {
        const row = identities[params[0]];
        return { rows: row ? [row] : [] };
      }
      if (sql.includes("WHERE LOWER(COALESCE(u.role, '')) = 'mayor'")) {
        return { rows: automatic.mayor ? [automatic.mayor] : [] };
      }
      throw new Error(`Unexpected memorandum query: ${sql}`);
    },
  };
}

function identity(name) {
  return { full_name: name, signer_position: 'Stored title', signer_role: 'employee' };
}

test('memorandum role keys join the allowlist without changing Leave or DTR keys', () => {
  assert.deepEqual(Object.values(ROLE_KEYS), [
    'leave_credit_certifier',
    'dtr_office_hours_verifier',
    'dtr_hr_officer',
    'memo_prepared_by',
    'memo_noted_by',
    'memo_approved_by',
  ]);
});

test('DTR report resolution still exposes only the two DTR roles', async () => {
  const result = await resolveDtrReportSignatories(
    { query: async () => ({ rows: [] }) },
    '2026-11-10'
  );
  assert.deepEqual(Object.keys(result).sort(), [
    'dtr_hr_officer',
    'dtr_office_hours_verifier',
  ]);
});

test('a memorandum role is a valid official signatory lookup', async () => {
  const result = await resolveOfficialSignatory(
    { query: async () => ({ rows: [] }) },
    ROLE_KEYS.MEMO_APPROVED_BY,
    '2026-11-10'
  );
  assert.equal(result, null);
});

test('incomplete memorandum configuration keeps automatic signatories', async () => {
  const client = memoClient({
    periods: {
      [ROLE_KEYS.MEMO_PREPARED_BY]: period(ROLE_KEYS.MEMO_PREPARED_BY, HR),
      [ROLE_KEYS.MEMO_NOTED_BY]: period(ROLE_KEYS.MEMO_NOTED_BY, OFFICE),
    },
    identities: {
      [HR]: identity('HR Head'),
      [OFFICE]: identity("Mayor's Office"),
    },
    automatic: {
      officeId: OFFICE,
      mayor: {
        employee_id: OFFICE,
        name: "Mayor's Office",
        position_title: 'Municipal Mayor',
      },
    },
  });
  const result = await resolveMemoSignatories(client, { document_type: 'memo' });
  assert.equal(result.configuration.mode, 'automatic');
  assert.equal(result.configuration.ready, false);
  assert.deepEqual(result.configuration.missing, ['Approved by']);
  assert.equal(result.prepared_by, null);
  assert.equal(result.approved_by, null);
  assert.equal(result.noted_by.id, OFFICE);
  assert.equal(result.noted_by.position, "Mayor's Office");
  assert.ok(client.calls.some((sql) => sql.includes('FROM departments')));
  assert.ok(!client.calls.some((sql) => /\b(INSERT|UPDATE|DELETE)\b/i.test(sql)));
});

test('the same account for Noted by and Approved by does not switch new memorandums', async () => {
  const client = memoClient({
    periods: {
      [ROLE_KEYS.MEMO_PREPARED_BY]: period(ROLE_KEYS.MEMO_PREPARED_BY, HR),
      [ROLE_KEYS.MEMO_NOTED_BY]: period(ROLE_KEYS.MEMO_NOTED_BY, OFFICE),
      [ROLE_KEYS.MEMO_APPROVED_BY]: period(ROLE_KEYS.MEMO_APPROVED_BY, OFFICE),
    },
    identities: {
      [HR]: identity('HR Head'),
      [OFFICE]: identity("Mayor's Office"),
    },
  });
  const result = await resolveMemoSignatories(client, { document_type: 'memo' });
  assert.equal(result.configuration.mode, 'automatic');
  assert.match(result.configuration.conflict, /same account/);
  assert.equal(result.prepared_by, null);
  assert.equal(result.approved_by, null);
});

test('all three distinct memorandum assignments replace automatic resolution together', async () => {
  const client = memoClient({
    periods: {
      [ROLE_KEYS.MEMO_PREPARED_BY]: period(ROLE_KEYS.MEMO_PREPARED_BY, HR),
      [ROLE_KEYS.MEMO_NOTED_BY]: period(ROLE_KEYS.MEMO_NOTED_BY, OFFICE),
      [ROLE_KEYS.MEMO_APPROVED_BY]: period(ROLE_KEYS.MEMO_APPROVED_BY, MAYOR),
    },
    identities: {
      [HR]: identity('HR Head'),
      [OFFICE]: identity("Mayor's Office"),
      [MAYOR]: identity('Municipal Mayor'),
    },
  });
  const result = await resolveMemoSignatories(client, { document_type: 'memo' });
  assert.equal(result.configuration.mode, 'configured');
  assert.equal(result.configuration.ready, true);
  assert.deepEqual(result.configuration.missing, []);
  assert.equal(result.prepared_by.id, HR);
  assert.equal(result.prepared_by.position, `${ROLE_KEYS.MEMO_PREPARED_BY} title`);
  assert.equal(result.noted_by.id, OFFICE);
  assert.equal(result.approved_by.id, MAYOR);
  assert.equal(result.approved_by.full_name, 'Municipal Mayor');
  assert.ok(!client.calls.some((sql) => sql.includes('FROM departments')));
  assert.ok(!client.calls.some((sql) => sql.includes('mayor_office_staff')));
});

test('an inactive configured signer keeps the memorandum on automatic resolution', async () => {
  const client = memoClient({
    periods: {
      [ROLE_KEYS.MEMO_PREPARED_BY]: period(ROLE_KEYS.MEMO_PREPARED_BY, HR),
      [ROLE_KEYS.MEMO_NOTED_BY]: period(ROLE_KEYS.MEMO_NOTED_BY, OFFICE),
      [ROLE_KEYS.MEMO_APPROVED_BY]: period(ROLE_KEYS.MEMO_APPROVED_BY, MAYOR),
    },
    identities: {
      [HR]: identity('HR Head'),
      [OFFICE]: identity("Mayor's Office"),
    },
  });
  const result = await resolveMemoSignatories(client, { document_type: 'memo' });
  assert.equal(result.configuration.mode, 'automatic');
  assert.deepEqual(result.configuration.missing, ['Approved by']);
  assert.equal(result.prepared_by, null);
});

test('Noted by and Approved by cannot be configured to the same account', async () => {
  const db = {
    async query(sql, params) {
      assert.equal(params[0], ROLE_KEYS.MEMO_APPROVED_BY);
      assert.equal(params[1], '2026-11-10');
      return { rows: [{ employee_id: OFFICE }] };
    },
  };
  await assert.rejects(
    () => assertMemoSignatoryAccountsDistinct(db, {
      roleKey: ROLE_KEYS.MEMO_NOTED_BY,
      employeeId: OFFICE,
      effectiveFrom: '2026-11-10',
      effectiveTo: null,
    }),
    (error) => error.code === 'VALIDATION' && /same account/.test(error.message)
  );
});

test('Leave and DTR configuration does not use the memorandum same-account rule', async () => {
  let queried = false;
  const db = {
    async query() {
      queried = true;
      return { rows: [] };
    },
  };
  await assertMemoSignatoryAccountsDistinct(db, {
    roleKey: ROLE_KEYS.LEAVE_CREDIT_CERTIFIER,
    employeeId: OFFICE,
    effectiveFrom: '2026-11-10',
  });
  await assertMemoSignatoryAccountsDistinct(db, {
    roleKey: ROLE_KEYS.DTR_HR_OFFICER,
    employeeId: OFFICE,
    effectiveFrom: '2026-11-10',
  });
  assert.equal(queried, false);
});

test('a different Approved by account is allowed beside Noted by', async () => {
  const db = {
    async query() {
      return { rows: [{ employee_id: MAYOR }] };
    },
  };
  await assertMemoSignatoryAccountsDistinct(db, {
    roleKey: ROLE_KEYS.MEMO_NOTED_BY,
    employeeId: OFFICE,
    effectiveFrom: '2026-11-01',
    effectiveTo: '2026-12-31',
  });
});

function field(label, signerId, id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') {
  return {
    id,
    pageNumber: 1,
    x: 0.1,
    y: 0.2,
    width: 0.3,
    height: 0.08,
    assignedSignerId: signerId,
    label,
  };
}

test('a new memorandum rejects a forged official signer and stores the configured signer', () => {
  assert.throws(
    () => enforceMemoOfficialSignatoryFields({
      initialSave: true,
      existingFields: [],
      incomingFields: [field('Prepared by', OFFICE)],
      authoritative: { prepared_by: { id: HR }, noted_by: null, approved_by: null },
    }),
    (error) => error.code === 'VALIDATION' && /Prepared by/.test(error.message)
  );

  const saved = enforceMemoOfficialSignatoryFields({
    initialSave: true,
    existingFields: [],
    incomingFields: [field('Signature', '99999999-9999-4999-8999-999999999999', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')],
    authoritative: { prepared_by: { id: HR }, noted_by: { id: OFFICE }, approved_by: null },
  });
  const prepared = saved.find((item) => item.label === 'Prepared by');
  const noted = saved.find((item) => item.label === 'Noted by');
  assert.equal(prepared.assignedSignerId, HR);
  assert.equal(prepared.x, 0.13);
  assert.equal(noted.assignedSignerId, OFFICE);
  assert.equal(saved.some((item) => item.label === 'Approved by'), false);
  assert.equal(saved.some((item) => item.label === 'Signature'), true);
});

test('an existing memorandum keeps stored official signers and rejects reassignment', () => {
  const stored = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    label: 'Prepared by',
    assigned_signer_id: HR,
  };
  const kept = enforceMemoOfficialSignatoryFields({
    initialSave: false,
    existingFields: [stored],
    incomingFields: [field('Prepared by', HR)],
    authoritative: { prepared_by: { id: MAYOR } },
  });
  assert.equal(kept.find((item) => item.label === 'Prepared by').assignedSignerId, HR);

  assert.throws(
    () => enforceMemoOfficialSignatoryFields({
      initialSave: false,
      existingFields: [stored],
      incomingFields: [field('Prepared by', MAYOR)],
      authoritative: { prepared_by: { id: MAYOR } },
    }),
    (error) => /cannot be reassigned/.test(error.message)
  );

  assert.throws(
    () => enforceMemoOfficialSignatoryFields({
      initialSave: false,
      existingFields: [],
      incomingFields: [field('Noted by', OFFICE, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')],
      authoritative: { noted_by: { id: OFFICE } },
    }),
    (error) => /cannot be added to an existing memorandum/.test(error.message)
  );
});

function configurationPool({ employee, overlap = false }) {
  const client = {
    async query(sql) {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return { rows: [] };
      if (sql.includes('pg_advisory_xact_lock')) return { rows: [] };
      if (sql.includes('FROM users u')) return { rows: [employee], rowCount: 1 };
      if (sql.includes('effective_from = $2')) return { rows: [], rowCount: 0 };
      if (sql.includes('effective_from < $2')) return { rows: [], rowCount: 0 };
      if (sql.includes('INSERT INTO docutracker_official_signatories')) {
        if (overlap) {
          const error = new Error('overlap');
          error.code = '23P01';
          throw error;
        }
        return {
          rows: [{
            id: '77777777-7777-4777-8777-777777777777',
            role_key: ROLE_KEYS.MEMO_PREPARED_BY,
            employee_id: employee.id,
            employee_name_snapshot: employee.full_name,
            position_title_snapshot: employee.position_title,
            department_name_snapshot: employee.department_name,
            effective_from: '2026-11-10',
            effective_to: null,
          }],
        };
      }
      if (sql.includes('docutracker_governance_audit')) return { rows: [] };
      return { rows: [], rowCount: 0 };
    },
    release() {},
  };
  return { connect: async () => client };
}

test('an administrator can save a memorandum signatory for an active employee', async () => {
  const saved = await configureOfficialSignatory(configurationPool({
    employee: {
      id: HR,
      full_name: 'HR Head',
      role: 'hr',
      is_active: true,
      position_title: 'HR Department Head',
      department_name: 'HR Office',
    },
  }), {
    roleKey: ROLE_KEYS.MEMO_PREPARED_BY,
    employeeId: HR,
    effectiveFrom: '2026-11-10',
    actorId: ACTOR,
  });
  assert.equal(saved.role_key, ROLE_KEYS.MEMO_PREPARED_BY);
  assert.equal(saved.employee_id, HR);
});

test('an inactive employee cannot be saved as a memorandum signatory', async () => {
  await assert.rejects(
    () => configureOfficialSignatory(configurationPool({
      employee: {
        id: MAYOR,
        full_name: 'Former Mayor',
        role: 'mayor',
        is_active: false,
        position_title: 'Municipal Mayor',
        department_name: "Mayor's Office",
      },
    }), {
      roleKey: ROLE_KEYS.MEMO_APPROVED_BY,
      employeeId: MAYOR,
      effectiveFrom: '2026-11-10',
      actorId: ACTOR,
    }),
    (error) => error.status === 400 && /inactive employee/i.test(error.message)
  );
});

test('overlapping memorandum effective dates use the existing conflict response', async () => {
  await assert.rejects(
    () => configureOfficialSignatory(configurationPool({
      employee: {
        id: HR,
        full_name: 'HR Head',
        role: 'hr',
        is_active: true,
        position_title: 'HR Department Head',
        department_name: 'HR Office',
      },
      overlap: true,
    }), {
      roleKey: ROLE_KEYS.MEMO_PREPARED_BY,
      employeeId: HR,
      effectiveFrom: '2026-11-10',
      effectiveTo: '2026-12-31',
      actorId: ACTOR,
    }),
    (error) => error.status === 409 && /overlaps/.test(error.message)
  );
});

test('Leave configuration still accepts the leave credit certifier role', async () => {
  const saved = await configureOfficialSignatory(configurationPool({
    employee: {
      id: HR,
      full_name: 'Leave Certifier',
      role: 'hr',
      is_active: true,
      position_title: 'Administrative Officer IV',
      department_name: 'Human Resources',
    },
  }), {
    roleKey: ROLE_KEYS.LEAVE_CREDIT_CERTIFIER,
    employeeId: HR,
    effectiveFrom: '2026-11-10',
    actorId: ACTOR,
  });
  assert.equal(saved.employee_id, HR);
});

test('the official signatory route remains admin-only', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '../src/routes/docutracker.js'),
    'utf8'
  );
  const start = route.indexOf("'/official-signatories/:roleKey'");
  const block = route.slice(start, start + 900);
  assert.match(block, /requireAdmin/);
  assert.match(block, /configureOfficialSignatory/);
});

test('memorandum signatory resolution is a read-only admin request', () => {
  const route = fs.readFileSync(
    path.join(__dirname, '../src/routes/docutracker.js'),
    'utf8'
  );
  const start = route.indexOf("'/official-signatories/memorandum'");
  assert.notEqual(start, -1);
  const block = route.slice(start, start + 700);
  assert.match(block, /requireAdmin/);
  assert.match(block, /resolveMemoSignatories\(pool, \{ document_type: 'memo' \}\)/);
  assert.doesNotMatch(block, /\b(INSERT|UPDATE|DELETE)\b/i);
});

test('fresh initialization and the forward migration allow the same six roles', () => {
  const root = path.resolve(__dirname, '..');
  const init = fs.readFileSync(path.join(root, 'scripts/init-schema.sql'), 'utf8');
  const migration = fs.readFileSync(
    path.join(root, 'scripts/migrations/docutracker/migrate-docutracker-memo-official-signatories-v1.sql'),
    'utf8'
  );
  for (const role of Object.values(ROLE_KEYS)) {
    assert.match(init, new RegExp(`'${role}'`));
    assert.match(migration, new RegExp(`'${role}'`));
  }
  assert.doesNotMatch(migration, /\bDELETE\s+FROM\s+docutracker_official_signatories\b/i);
  assert.doesNotMatch(migration, /\bUPDATE\s+docutracker_documents\b/i);
});
