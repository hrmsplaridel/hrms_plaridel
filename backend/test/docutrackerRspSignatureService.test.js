const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getSourceSignatures,
  getRspSourceSignatures,
  listLdSignatureRequests,
  listRspSignatureRequests,
  assignRspSourceSigner,
  signRspSourceSlot,
  initializeCreatorSourceSignatures,
  reResolveAutomaticSourceSignatures,
} = require('../src/services/docutrackerRspSignatureService');

const formId = '11111111-1111-4111-8111-111111111111';
const adminId = '22222222-2222-4222-8222-222222222222';
const signerId = '33333333-3333-4333-8333-333333333333';
const otherId = '44444444-4444-4444-8444-444444444444';
const assetId = '55555555-5555-4555-8555-555555555555';

function sourceRow(overrides = {}) {
  return { rowCount: 1, rows: [{ id: formId, created_by: null, ...overrides }] };
}

function signatureRow(overrides = {}) {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    slot_key: 'prepared_by',
    label: 'Prepared by',
    assigned_signer_id: signerId,
    assigned_signer_name: 'Prepared Person',
    assignment_source: 'manual',
    recovery_remarks: null,
    signature_asset_id: null,
    signed_by: null,
    signer_name_snapshot: null,
    signed_at: null,
    mime_type: null,
    signature_image_base64: null,
    ...overrides,
  };
}

test('only an assigned RSP signer or admin can load signature fields', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 1, rows: [signatureRow()] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  await assert.rejects(
    getRspSourceSignatures(
      pool,
      { id: otherId, role: 'employee' },
      'rsp',
      'selection_lineup_entries',
      formId
    ),
    (error) => error.code === 'FORBIDDEN'
  );

  const assigned = await getRspSourceSignatures(
    pool,
    { id: signerId, role: 'employee' },
    'rsp',
    'selection_lineup_entries',
    formId
  );
  assert.equal(assigned.can_assign, false);
  assert.equal(assigned.signatures[0].can_sign, true);

  const admin = await getRspSourceSignatures(
    pool,
    { id: adminId, role: 'admin' },
    'rsp',
    'selection_lineup_entries',
    formId
  );
  assert.equal(admin.can_assign, true);
  assert.equal(admin.signatures[0].can_sign, false);
});

test('creator-owned Prepared by fields cannot be casually reassigned', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      queries.push(sql);
      if (['BEGIN', 'ROLLBACK'].includes(sql)) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow({ created_by: signerId });
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 1, rows: [signatureRow({ assignment_source: 'creator' })] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };
  const pool = { async connect() { return client; } };

  await assert.rejects(
    assignRspSourceSigner(
      pool,
      { id: adminId, role: 'admin' },
      'rsp',
      'selection_lineup_entries',
      formId,
      'prepared_by',
      { assigned_signer_id: otherId }
    ),
    (error) =>
      error.code === 'VALIDATION' &&
      error.message.includes('Recovery reassignment requires remarks')
  );
  assert.ok(queries.includes('ROLLBACK'));
});

test('creator-owned Prepared by fields expose creator assignment without an edit control', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow({ created_by: signerId });
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return {
          rowCount: 1,
          rows: [signatureRow({ assignment_source: 'creator' })],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getRspSourceSignatures(
    pool,
    { id: adminId, role: 'admin' },
    'rsp',
    'selection_lineup_entries',
    formId
  );

  assert.equal(result.can_assign, true);
  assert.equal(result.signatures[0].assignment_source, 'creator');
  assert.equal(result.signatures[0].can_assign, false);
  assert.equal(result.signatures[0].assigned_signer_name, 'Prepared Person');
});

test('new source forms assign Prepared by to the authenticated creator', async () => {
  const queries = [];
  const db = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (sql.includes('SELECT * FROM "selection_lineup_entries"')) {
        return sourceRow({ created_by: signerId });
      }
      if (sql.includes('FROM users') && sql.includes('is_active = true')) {
        return { rowCount: 1, rows: [{ id: signerId }] };
      }
      if (sql.includes('INSERT INTO docutracker_rsp_source_signatures')) {
        return { rowCount: 1, rows: [{ id: '77777777-7777-4777-8777-777777777777' }] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const initialized = await initializeCreatorSourceSignatures(
    db,
    { id: signerId, role: 'admin' },
    'selection_lineup_entries',
    formId
  );

  assert.equal(initialized, true);
  assert.ok(
    queries.some(({ sql, params }) =>
      sql.includes('ON CONFLICT') &&
      params[2] === 'prepared_by' &&
      params[4] === signerId &&
      params[5] === 'creator'
    )
  );
  assert.ok(
    queries.some(({ sql, params }) =>
      sql.includes('INSERT INTO docutracker_governance_audit') &&
      params.includes('source_signer_assigned')
    )
  );
});

test('signature request list returns only forms assigned to the current user', async () => {
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT DISTINCT source_table')) {
        assert.equal(params[0], signerId);
        assert.ok(params[1].includes('selection_lineup_entries'));
        return {
          rowCount: 1,
          rows: [{
            source_table: 'selection_lineup_entries',
            source_record_id: formId,
          }],
        };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 1, rows: [signatureRow()] };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        return {
          rowCount: 1,
          rows: [{
            source_record: {
              id: formId,
              vacant_position: 'Administrative Officer',
            },
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listRspSignatureRequests(pool, {
    id: signerId,
    role: 'employee',
  });

  assert.equal(result.length, 1);
  assert.equal(result[0].form_name, 'Selection Line-Up');
  assert.equal(result[0].title, 'Administrative Officer');
  assert.equal(result[0].signature_bundle.signatures[0].can_sign, true);
});

test('RSP admins can discover unassigned signature-bearing forms for setup', async () => {
  const pool = {
    async query(sql) {
      if (
        sql.includes('FROM "selection_lineup_entries"') &&
        sql.includes('ORDER BY updated_at')
      ) {
        return { rowCount: 1, rows: [{ source_record_id: formId }] };
      }
      if (sql.includes('ORDER BY updated_at')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        return {
          rowCount: 1,
          rows: [{
            source_record: {
              id: formId,
              vacant_position: 'Administrative Officer',
            },
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listRspSignatureRequests(pool, {
    id: adminId,
    role: 'admin',
  });

  assert.equal(result.length, 1);
  assert.equal(result[0].source_module, 'rsp');
  assert.equal(result[0].form_name, 'Selection Line-Up');
  assert.equal(result[0].title, 'Administrative Officer');
  assert.equal(result[0].requires_setup, true);
  assert.deepEqual(
    result[0].signature_bundle.signatures.map((slot) => slot.slot_key),
    ['prepared_by']
  );
});

test('completed source signature requests stay visible for the assigned signer', async () => {
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT DISTINCT source_table')) {
        assert.equal(params[0], signerId);
        return {
          rowCount: 1,
          rows: [{
            source_table: 'selection_lineup_entries',
            source_record_id: formId,
          }],
        };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return {
          rowCount: 1,
          rows: [
            signatureRow({
              signature_asset_id: assetId,
              signed_by: signerId,
              signer_name_snapshot: 'Prepared Person',
              signed_at: new Date('2026-09-16T01:00:00.000Z'),
              mime_type: 'image/png',
              signature_image_base64: 'c2lnbmF0dXJl',
            }),
          ],
        };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        return {
          rowCount: 1,
          rows: [{
            source_record: {
              id: formId,
              vacant_position: 'Administrative Officer',
            },
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listRspSignatureRequests(pool, {
    id: signerId,
    role: 'employee',
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].source_record_id, formId);
  assert.equal(result[0].signature_bundle.signatures[0].can_sign, true);
  assert.ok(result[0].signature_bundle.signatures[0].signed_at);
});

test('completed source signature requests are omitted for unrelated viewers', async () => {
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT DISTINCT source_table')) {
        assert.equal(params[0], otherId);
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listRspSignatureRequests(pool, {
    id: otherId,
    role: 'employee',
  });
  assert.equal(result.length, 0);
});

test('orphaned source signature rows for deleted forms are skipped', async () => {
  const missingFormId = '77777777-7777-4777-8777-777777777777';
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT DISTINCT source_table')) {
        return {
          rowCount: 2,
          rows: [
            {
              source_table: 'action_brainstorming_coaching_entries',
              source_record_id: missingFormId,
            },
            {
              source_table: 'action_brainstorming_coaching_entries',
              source_record_id: formId,
            },
          ],
        };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        if (params[0] === missingFormId) return { rowCount: 0, rows: [] };
        return {
          rowCount: 1,
          rows: [{
            source_record: {
              id: formId,
              department: 'HR Office',
              date: '2026-09-21',
            },
          }],
        };
      }
      if (
        sql.includes('SELECT id FROM "action_brainstorming_coaching_entries"') ||
        sql.includes('SELECT id, created_by FROM "action_brainstorming_coaching_entries"')
      ) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return {
          rowCount: 1,
          rows: [
            signatureRow({
              slot_key: 'certified_by',
              label: 'Certified by',
              assigned_signer_id: signerId,
              assigned_signer_name: 'Department Head',
              assignment_source: 'automatic',
            }),
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listLdSignatureRequests(pool, {
    id: signerId,
    role: 'employee',
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].source_table, 'action_brainstorming_coaching_entries');
  assert.equal(result[0].source_record_id, formId);
  assert.equal(result[0].signature_bundle.signatures[0].can_sign, true);
});

test('missing source form tables fail instead of appearing as no required actions', async () => {
  const missingTable = new Error('relation does not exist');
  missingTable.code = '42P01';
  const pool = {
    async query() {
      throw missingTable;
    },
  };

  await assert.rejects(
    listRspSignatureRequests(pool, { id: adminId, role: 'admin' }),
    (error) =>
      error.code === 'UNAVAILABLE' &&
      error.message === 'Source form e-signatures are not initialized'
  );
});

test('L&D admins can discover unassigned signature-bearing forms for setup', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM "idp_entries"') && sql.includes('ORDER BY updated_at')) {
        return { rowCount: 1, rows: [{ source_record_id: formId }] };
      }
      if (
        sql.includes('FROM "action_brainstorming_coaching_entries"') &&
        sql.includes('ORDER BY updated_at')
      ) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "idp_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        return {
          rowCount: 1,
          rows: [{
            source_record: {
              id: formId,
              name: 'Juan Dela Cruz',
              position: 'Administrative Officer',
            },
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await listLdSignatureRequests(pool, {
    id: adminId,
    role: 'admin',
  });

  assert.equal(result.length, 1);
  assert.equal(result[0].source_module, 'ld');
  assert.equal(result[0].form_name, 'Individual Development Plan');
  assert.equal(result[0].title, 'Juan Dela Cruz - Administrative Officer');
  assert.equal(result[0].requires_setup, true);
  assert.deepEqual(
    result[0].signature_bundle.signatures.map((slot) => slot.slot_key),
    ['prepared_by', 'reviewed_by', 'noted_by', 'approved_by']
  );
});

test('unassigned users cannot open L&D source signature fields directly', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('SELECT id, created_by FROM "idp_entries"')) return sourceRow();
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  await assert.rejects(
    getSourceSignatures(
      pool,
      { id: otherId, role: 'employee' },
      'ld',
      'idp_entries',
      formId
    ),
    (error) => error.code === 'FORBIDDEN'
  );
});

test('admin assignment is transactional and clears a different signer signature', async () => {
  const queries = [];
  let responseRows = [signatureRow({ assigned_signer_id: otherId })];
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: responseRows.length, rows: responseRows };
      }
      if (sql.includes('SELECT id, full_name FROM users')) {
        return { rowCount: 1, rows: [{ id: signerId, full_name: 'Prepared Person' }] };
      }
      if (sql.includes('SELECT full_name') && sql.includes('FROM users')) {
        return { rowCount: 1, rows: [{ full_name: 'Prepared Person' }] };
      }
      if (sql.includes('UPDATE "selection_lineup_entries"') && sql.includes('prepared_by_name')) {
        return { rowCount: 1, rows: [{ id: formId }] };
      }
      if (sql.includes('INSERT INTO docutracker_rsp_source_signatures')) {
        responseRows = [signatureRow()];
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected transaction query: ${sql}`);
    },
    release() {},
  };
  const pool = {
    async connect() {
      return client;
    },
    async query(sql) {
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: responseRows.length, rows: responseRows };
      }
      throw new Error(`Unexpected response query: ${sql}`);
    },
  };

  const result = await assignRspSourceSigner(
    pool,
    { id: adminId, role: 'admin' },
    'rsp',
    'selection_lineup_entries',
    formId,
    'prepared_by',
    { assigned_signer_id: signerId }
  );

  assert.equal(result.signatures[0].assigned_signer_id, signerId);
  assert.ok(queries.some(({ sql }) => sql === 'COMMIT'));
  assert.ok(
    queries.some(({ sql }) =>
      sql.includes('signature_asset_id = CASE WHEN')
    )
  );
  assert.ok(
    queries.some(({ sql, params }) =>
      sql.includes('INSERT INTO docutracker_governance_audit') &&
      params.includes('source_signer_assigned')
    )
  );
});

test('an RSP signature can only use an asset owned by the assigned signer', async () => {
  const client = {
    async query(sql) {
      if (['BEGIN', 'ROLLBACK'].includes(sql)) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 1, rows: [signatureRow()] };
      }
      if (sql.includes('FROM docutracker_signature_assets')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };
  const pool = { async connect() { return client; } };

  await assert.rejects(
    signRspSourceSlot(
      pool,
      { id: signerId, role: 'employee' },
      'rsp',
      'selection_lineup_entries',
      formId,
      'prepared_by',
      { signature_asset_id: assetId }
    ),
    (error) => error.code === 'FORBIDDEN'
  );
});

test('assigned signer can sign with an owned saved signature and the action is audited', async () => {
  const queries = [];
  let signed = false;
  const client = {
    async query(sql, params = []) {
      queries.push({ sql, params });
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: 1, rows: [signatureRow()] };
      }
      if (sql.includes('FROM docutracker_signature_assets')) {
        return { rowCount: 1, rows: [{ id: assetId }] };
      }
      if (sql.includes('SELECT full_name FROM users')) {
        return { rowCount: 1, rows: [{ full_name: 'Prepared Person' }] };
      }
      if (sql.includes('UPDATE docutracker_rsp_source_signatures')) {
        signed = true;
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected transaction query: ${sql}`);
    },
    release() {},
  };
  const pool = {
    async connect() {
      return client;
    },
    async query(sql) {
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return {
          rowCount: 1,
          rows: [
            signatureRow({
              signature_asset_id: assetId,
              signed_by: signerId,
              signer_name_snapshot: 'Prepared Person',
              signed_at: new Date('2026-09-15T04:00:00.000Z'),
              mime_type: 'image/png',
              signature_image_base64: 'aW1hZ2U=',
            }),
          ],
        };
      }
      throw new Error(`Unexpected response query: ${sql}`);
    },
  };

  const result = await signRspSourceSlot(
    pool,
    { id: signerId, role: 'employee' },
    'rsp',
    'selection_lineup_entries',
    formId,
    'prepared_by',
    { signature_asset_id: assetId }
  );

  assert.equal(signed, true);
  assert.equal(result.signatures[0].signature_asset_id, assetId);
  assert.ok(
    queries.some(({ sql, params }) =>
      sql.includes('INSERT INTO docutracker_governance_audit') &&
      params.includes('source_signed')
    )
  );
});

test('re-resolve backfill only inserts empty automatic slots', async () => {
  const formId2 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const inserts = [];
  const pool = {
    async query(sql, params = []) {
      if (sql.includes('SELECT id, created_by FROM "selection_lineup_entries"')) {
        return {
          rowCount: 2,
          rows: [
            { id: formId, created_by: signerId },
            { id: formId2, created_by: signerId },
          ],
        };
      }
      if (sql.includes('SELECT * FROM "selection_lineup_entries"')) {
        return {
          rowCount: 1,
          rows: [{ id: params[0], created_by: signerId, department: null }],
        };
      }
      if (sql.includes('FROM users') && sql.includes('is_active = true')) {
        return { rowCount: 1, rows: [{ id: params[0] }] };
      }
      if (sql.includes('INSERT INTO docutracker_rsp_source_signatures')) {
        // First form already has prepared_by → DO NOTHING; second inserts.
        if (params[1] === formId) {
          return { rowCount: 0, rows: [] };
        }
        inserts.push({ table: params[0], form: params[1], slot: params[2] });
        return { rowCount: 1, rows: [{ id: 'new-sig' }] };
      }
      if (sql.includes('UPDATE "selection_lineup_entries"')) {
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('SELECT to_jsonb(source_row)')) {
        return {
          rowCount: 1,
          rows: [{ source_record: { id: params[0], vacant_position: 'AO' } }],
        };
      }
      if (sql.includes('INSERT INTO notifications')) {
        return { rowCount: 1, rows: [] };
      }
      // Other RSP/L&D tables with automatic rules: empty.
      if (sql.includes('SELECT id, created_by FROM "')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await reResolveAutomaticSourceSignatures(
    pool,
    { id: adminId, role: 'admin' },
    'rsp'
  );
  assert.equal(result.processed, 2);
  assert.equal(result.assigned_forms, 1);
  assert.equal(result.skipped_forms, 1);
  assert.deepEqual(inserts, [
    { table: 'selection_lineup_entries', form: formId2, slot: 'prepared_by' },
  ]);
});

test('IDP create snapshots automatic reviewed/noted/approved signers when resolvable', async () => {
  const deptHeadId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const hrmdoId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const mayorId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const departmentId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  const assigned = [];
  const db = {
    async query(sql, params = []) {
      if (sql.includes('SELECT * FROM "idp_entries"')) {
        return {
          rowCount: 1,
          rows: [{ id: formId, created_by: signerId, department: 'Budget Office' }],
        };
      }
      if (sql.includes('FROM departments') && sql.includes('lower(btrim(name))')) {
        return { rowCount: 1, rows: [{ id: departmentId }] };
      }
      if (sql.includes('position_department_head_periods') && sql.includes('LIMIT 1')) {
        return {
          rowCount: 1,
          rows: [{ reviewer_id: deptHeadId, reviewer_name: 'Dept Head' }],
        };
      }
      if (sql.includes('FROM department_reviewer_backups')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('FROM docutracker_official_signatories')) {
        return {
          rowCount: 1,
          rows: [{
            id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            role_key: 'leave_credit_certifier',
            employee_id: hrmdoId,
            employee_name_snapshot: 'HRMDO Official',
            position_title_snapshot: 'HRMDO',
            department_name_snapshot: 'HRMDO',
            effective_from: '2020-01-01',
            effective_to: null,
            remarks: null,
            created_at: new Date(),
            updated_at: new Date(),
          }],
        };
      }
      if (sql.includes("LOWER(COALESCE(u.role, '')) = 'mayor'")) {
        return { rowCount: 1, rows: [{ employee_id: mayorId, name: 'Mayor' }] };
      }
      if (sql.includes('FROM users') && sql.includes('is_active = true')) {
        return { rowCount: 1, rows: [{ id: params[0] }] };
      }
      if (sql.includes('INSERT INTO docutracker_rsp_source_signatures')) {
        assigned.push({ slot: params[2], signer: params[4], source: params[5] });
        return { rowCount: 1, rows: [{ id: `slot-${params[2]}` }] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql.slice(0, 180)}`);
    },
  };

  const initialized = await initializeCreatorSourceSignatures(
    db,
    { id: signerId, role: 'employee' },
    'idp_entries',
    formId
  );

  assert.equal(initialized, true);
  const bySlot = Object.fromEntries(assigned.map((row) => [row.slot, row]));
  assert.equal(bySlot.prepared_by?.signer, signerId);
  assert.equal(bySlot.prepared_by?.source, 'creator');
  assert.equal(bySlot.reviewed_by?.signer, deptHeadId);
  assert.equal(bySlot.reviewed_by?.source, 'automatic');
  assert.equal(bySlot.noted_by?.signer, hrmdoId);
  assert.equal(bySlot.noted_by?.source, 'automatic');
  assert.equal(bySlot.approved_by?.signer, mayorId);
  assert.equal(bySlot.approved_by?.source, 'automatic');
});

test('unresolved automatic roles leave the slot empty for admin recovery', async () => {
  const assigned = [];
  const db = {
    async query(sql, params = []) {
      if (sql.includes('SELECT * FROM "applicants_profile_entries"')) {
        return { rowCount: 1, rows: [{ id: formId, created_by: signerId }] };
      }
      if (sql.includes('FROM docutracker_official_signatories')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('FROM users') && sql.includes('is_active = true')) {
        return { rowCount: 1, rows: [{ id: params[0] }] };
      }
      if (sql.includes('INSERT INTO docutracker_rsp_source_signatures')) {
        assigned.push(params[2]);
        return { rowCount: 1, rows: [{ id: 'slot-1' }] };
      }
      if (sql.includes('INSERT INTO docutracker_governance_audit')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql.slice(0, 160)}`);
    },
  };

  const initialized = await initializeCreatorSourceSignatures(
    db,
    { id: signerId, role: 'employee' },
    'applicants_profile_entries',
    formId
  );

  assert.equal(initialized, true);
  assert.deepEqual(assigned, ['prepared_by']);
});

test('overriding an automatic assignment requires recovery remarks', async () => {
  const queries = [];
  const client = {
    async query(sql) {
      queries.push(sql);
      if (['BEGIN', 'ROLLBACK'].includes(sql)) return { rowCount: 0, rows: [] };
      if (sql.includes('SELECT id, created_by FROM "applicants_profile_entries"')) {
        return sourceRow({ created_by: signerId });
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return {
          rowCount: 1,
          rows: [
            signatureRow({
              slot_key: 'checked_by',
              label: 'Checked by',
              assignment_source: 'automatic',
            }),
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };
  const pool = { async connect() { return client; } };

  await assert.rejects(
    assignRspSourceSigner(
      pool,
      { id: adminId, role: 'admin' },
      'rsp',
      'applicants_profile_entries',
      formId,
      'checked_by',
      { assigned_signer_id: otherId }
    ),
    (error) =>
      error.code === 'VALIDATION' &&
      error.message.includes('assigned automatically')
  );
  assert.ok(queries.includes('ROLLBACK'));
});
