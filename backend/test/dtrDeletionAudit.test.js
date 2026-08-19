const test = require('node:test');
const assert = require('node:assert/strict');
const {
  dtrDeletionKey,
  getDeletedDtrDateKeys,
} = require('../src/services/dtrDeletionAudit');

test('deleted DTR dates produce biometric-processing suppression keys', async () => {
  const db = {
    async query(sql, params) {
      assert.match(sql, /FROM dtr_daily_summary_deletions/i);
      assert.match(sql, /restored_at IS NULL/i);
      assert.deepEqual(params, [
        ['5b9fe943-4700-4ff6-a84e-66ef793ecfc4'],
        '2026-06-01',
        '2026-06-30',
      ]);
      return {
        rows: [
          {
            employee_id: '5b9fe943-4700-4ff6-a84e-66ef793ecfc4',
            attendance_date: '2026-06-16',
          },
        ],
      };
    },
  };

  const keys = await getDeletedDtrDateKeys(
    db,
    ['5b9fe943-4700-4ff6-a84e-66ef793ecfc4'],
    '2026-06-01',
    '2026-06-30',
  );

  assert.equal(
    keys.has(
      dtrDeletionKey(
        '5b9fe943-4700-4ff6-a84e-66ef793ecfc4',
        '2026-06-16',
      ),
    ),
    true,
  );
});

test('deleted DTR lookup skips the database when its scope is incomplete', async () => {
  const db = {
    async query() {
      assert.fail('database should not be queried');
    },
  };

  assert.deepEqual(await getDeletedDtrDateKeys(db, [], '2026-06-01', '2026-06-30'), new Set());
});
