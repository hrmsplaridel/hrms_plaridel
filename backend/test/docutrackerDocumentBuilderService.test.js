const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createSignatureAsset,
  listSavedSignatureAssets,
  signDocumentField,
  moveSignedDocumentField,
} = require('../src/services/docutrackerDocumentBuilderService');

const onePixelPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);

test('createSignatureAsset validates and stores a current-user PNG', async () => {
  let queryArgs;
  const pool = {
    async query(sql, params) {
      queryArgs = { sql, params };
      return {
        rows: [{
          id: 'asset-1',
          owner_user_id: 'user-1',
          mime_type: 'image/png',
          source_type: 'drawn',
          is_saved: true,
          image_base64: onePixelPng.toString('base64'),
        }],
      };
    },
  };

  const result = await createSignatureAsset(pool, { id: 'user-1' }, {
    image_base64: onePixelPng.toString('base64'),
    mime_type: 'image/png',
    source_type: 'drawn',
    is_saved: true,
  });

  assert.equal(result.id, 'asset-1');
  assert.equal(queryArgs.params[0], 'user-1');
  assert.deepEqual(queryArgs.params[1], onePixelPng);
});

test('createSignatureAsset rejects mismatched image content before database write', async () => {
  const pool = {
    async query() {
      throw new Error('database should not be called');
    },
  };

  await assert.rejects(
    createSignatureAsset(pool, { id: 'user-1' }, {
      image_base64: Buffer.from('not a png').toString('base64'),
      mime_type: 'image/png',
      source_type: 'uploaded',
    }),
    (error) => error.code === 'VALIDATION'
  );
});

test('saved signature lookup is scoped to the authenticated owner', async () => {
  let params;
  const pool = {
    async query(_sql, queryParams) {
      params = queryParams;
      return { rows: [] };
    },
  };

  await listSavedSignatureAssets(pool, { id: 'owner-7' });
  assert.deepEqual(params, ['owner-7']);
});

test('assigned signer can replace a locked signature with a new audit entry', async () => {
  const documentId = '11111111-1111-4111-8111-111111111111';
  const fieldId = '22222222-2222-4222-8222-222222222222';
  const userId = '33333333-3333-4333-8333-333333333333';
  const previousAssetId = '44444444-4444-4444-8444-444444444444';
  const replacementAssetId = '55555555-5555-4555-8555-555555555555';
  const document = {
    id: documentId,
    document_type: 'memo',
    status: 'pending',
    created_by: userId,
  };
  const lockedField = {
    id: fieldId,
    document_id: documentId,
    page_number: 1,
    position_x: 0.1,
    position_y: 0.7,
    width: 0.3,
    height: 0.12,
    assigned_signer_id: userId,
    label: 'Sign Here',
    signature_asset_id: previousAssetId,
    signed_at: new Date('2026-08-30T00:00:00.000Z'),
    locked_at: new Date('2026-08-30T00:00:00.000Z'),
  };
  let historyParams;
  let updateParams;

  const client = {
    async query(sql, params = []) {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return { rowCount: 1, rows: [document] };
      }
      if (sql.includes('SELECT * FROM docutracker_signature_fields')) {
        return { rowCount: 1, rows: [lockedField] };
      }
      if (sql.includes('SELECT id FROM docutracker_signature_assets')) {
        return { rowCount: 1, rows: [{ id: replacementAssetId }] };
      }
      if (sql.includes('SELECT full_name FROM users')) {
        return { rowCount: 1, rows: [{ full_name: 'Assigned Signer' }] };
      }
      if (sql.includes('UPDATE docutracker_signature_fields SET')) {
        updateParams = params;
        return { rowCount: 1, rows: [{ ...lockedField }] };
      }
      if (sql.includes('INSERT INTO docutracker_document_history')) {
        historyParams = params;
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
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return { rowCount: 1, rows: [document] };
      }
      if (sql.includes('SELECT pages, revision')) {
        return { rowCount: 1, rows: [{ pages: [[{ insert: '\n' }]], revision: 1 }] };
      }
      if (sql.includes('SELECT f.*')) {
        return {
          rowCount: 1,
          rows: [{
            ...lockedField,
            signature_asset_id: replacementAssetId,
            assigned_signer_name: 'Assigned Signer',
            signature_image_base64: onePixelPng.toString('base64'),
          }],
        };
      }
      throw new Error(`Unexpected response query: ${sql}`);
    },
  };

  const result = await signDocumentField(
    pool,
    { id: userId, role: 'admin' },
    documentId,
    fieldId,
    { signature_asset_id: replacementAssetId }
  );

  assert.deepEqual(updateParams, [
    replacementAssetId,
    userId,
    'Assigned Signer',
    fieldId,
    documentId,
  ]);
  assert.equal(historyParams[3], 'Replaced signature field: Sign Here');
  assert.equal(result.signature_fields[0].can_sign, true);
});

test('user who is not the assigned signer cannot replace a locked signature', async () => {
  const documentId = '11111111-1111-4111-8111-111111111111';
  const fieldId = '22222222-2222-4222-8222-222222222222';
  const assignedSignerId = '33333333-3333-4333-8333-333333333333';
  const otherUserId = '66666666-6666-4666-8666-666666666666';
  let rolledBack = false;
  const client = {
    async query(sql) {
      if (sql === 'BEGIN') return { rowCount: 0, rows: [] };
      if (sql === 'ROLLBACK') {
        rolledBack = true;
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return {
          rowCount: 1,
          rows: [{ id: documentId, document_type: 'memo', status: 'pending' }],
        };
      }
      if (sql.includes('SELECT * FROM docutracker_signature_fields')) {
        return {
          rowCount: 1,
          rows: [{
            id: fieldId,
            document_id: documentId,
            assigned_signer_id: assignedSignerId,
            locked_at: new Date('2026-08-30T00:00:00.000Z'),
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };

  await assert.rejects(
    signDocumentField(
      { connect: async () => client },
      { id: otherUserId, role: 'admin' },
      documentId,
      fieldId,
      { signature_asset_id: '55555555-5555-4555-8555-555555555555' }
    ),
    (error) => error.code === 'FORBIDDEN'
  );
  assert.equal(rolledBack, true);
});

test('assigned signer can move a signed field with a metadata audit entry', async () => {
  const documentId = '11111111-1111-4111-8111-111111111111';
  const fieldId = '22222222-2222-4222-8222-222222222222';
  const userId = '33333333-3333-4333-8333-333333333333';
  const assetId = '44444444-4444-4444-8444-444444444444';
  const document = {
    id: documentId,
    document_type: 'memo',
    status: 'pending',
    created_by: userId,
  };
  const signedField = {
    id: fieldId,
    document_id: documentId,
    page_number: 1,
    position_x: 0.1,
    position_y: 0.7,
    width: 0.3,
    height: 0.12,
    assigned_signer_id: userId,
    label: 'Sign Here',
    signature_asset_id: assetId,
    signed_at: new Date('2026-08-30T00:00:00.000Z'),
    locked_at: new Date('2026-08-30T00:00:00.000Z'),
  };
  let updateParams;
  let historyParams;
  const client = {
    async query(sql, params = []) {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return { rowCount: 1, rows: [document] };
      }
      if (sql.includes('SELECT * FROM docutracker_signature_fields')) {
        return { rowCount: 1, rows: [signedField] };
      }
      if (sql.includes('UPDATE docutracker_signature_fields SET')) {
        updateParams = params;
        return { rowCount: 1, rows: [{ ...signedField }] };
      }
      if (sql.includes('SELECT full_name FROM users')) {
        return { rowCount: 1, rows: [{ full_name: 'Assigned Signer' }] };
      }
      if (sql.includes('INSERT INTO docutracker_document_history')) {
        historyParams = params;
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
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return { rowCount: 1, rows: [document] };
      }
      if (sql.includes('SELECT pages, revision')) {
        return { rowCount: 1, rows: [{ pages: [[{ insert: '\n' }]], revision: 1 }] };
      }
      if (sql.includes('SELECT f.*')) {
        return {
          rowCount: 1,
          rows: [{
            ...signedField,
            position_x: 0.4,
            position_y: 0.5,
            assigned_signer_name: 'Assigned Signer',
            signature_image_base64: onePixelPng.toString('base64'),
          }],
        };
      }
      throw new Error(`Unexpected response query: ${sql}`);
    },
  };

  const result = await moveSignedDocumentField(
    pool,
    { id: userId, role: 'admin' },
    documentId,
    fieldId,
    { position_x: 0.4, position_y: 0.5 }
  );

  assert.deepEqual(updateParams, [0.4, 0.5, fieldId, documentId, userId]);
  assert.equal(historyParams[3], 'Moved signed field: Sign Here');
  assert.equal(result.signature_fields[0].position_x, 0.4);
  assert.equal(result.signature_fields[0].position_y, 0.5);
});

test('user who is not the assigned signer cannot move a signed field', async () => {
  const documentId = '11111111-1111-4111-8111-111111111111';
  const fieldId = '22222222-2222-4222-8222-222222222222';
  const assignedSignerId = '33333333-3333-4333-8333-333333333333';
  const otherUserId = '66666666-6666-4666-8666-666666666666';
  let rolledBack = false;
  const client = {
    async query(sql) {
      if (sql === 'BEGIN') return { rowCount: 0, rows: [] };
      if (sql === 'ROLLBACK') {
        rolledBack = true;
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('SELECT * FROM docutracker_documents')) {
        return {
          rowCount: 1,
          rows: [{ id: documentId, document_type: 'memo', status: 'pending' }],
        };
      }
      if (sql.includes('SELECT * FROM docutracker_signature_fields')) {
        return {
          rowCount: 1,
          rows: [{
            id: fieldId,
            document_id: documentId,
            assigned_signer_id: assignedSignerId,
            signature_asset_id: '44444444-4444-4444-8444-444444444444',
            signed_at: new Date('2026-08-30T00:00:00.000Z'),
            locked_at: new Date('2026-08-30T00:00:00.000Z'),
          }],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
    release() {},
  };

  await assert.rejects(
    moveSignedDocumentField(
      { connect: async () => client },
      { id: otherUserId, role: 'admin' },
      documentId,
      fieldId,
      { position_x: 0.4, position_y: 0.5 }
    ),
    (error) => error.code === 'FORBIDDEN'
  );
  assert.equal(rolledBack, true);
});
