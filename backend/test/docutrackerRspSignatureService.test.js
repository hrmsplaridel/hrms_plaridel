const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getSourceSignatures,
  getRspSourceSignatures,
  listLdSignatureRequests,
  listRspSignatureRequests,
  assignRspSourceSigner,
  signRspSourceSlot,
} = require('../src/services/docutrackerRspSignatureService');

const formId = '11111111-1111-4111-8111-111111111111';
const adminId = '22222222-2222-4222-8222-222222222222';
const signerId = '33333333-3333-4333-8333-333333333333';
const otherId = '44444444-4444-4444-8444-444444444444';
const assetId = '55555555-5555-4555-8555-555555555555';

function sourceRow() {
  return { rowCount: 1, rows: [{ id: formId }] };
}

function signatureRow(overrides = {}) {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    slot_key: 'prepared_by',
    label: 'Prepared by',
    assigned_signer_id: signerId,
    assigned_signer_name: 'Prepared Person',
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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

test('completed source signature requests are omitted', async () => {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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

  assert.deepEqual(result, []);
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
      if (sql.includes('SELECT id FROM "idp_entries"')) {
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
      if (sql.includes('SELECT id FROM "idp_entries"')) return sourceRow();
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
        return sourceRow();
      }
      if (sql.includes('FROM docutracker_rsp_source_signatures s')) {
        return { rowCount: responseRows.length, rows: responseRows };
      }
      if (sql.includes('SELECT id, full_name FROM users')) {
        return { rowCount: 1, rows: [{ id: signerId, full_name: 'Prepared Person' }] };
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
      if (sql.includes('SELECT id FROM "selection_lineup_entries"')) {
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
