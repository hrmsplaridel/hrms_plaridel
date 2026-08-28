const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createSignatureAsset,
  listSavedSignatureAssets,
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
