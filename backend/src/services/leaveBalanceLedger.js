/**
 * Append-only leave balance ledger (auditable movements on leave_balances buckets).
 * Distinct from leave_request_history (workflow) and legacy leave_balance_deduction_history.
 */

let _ensurePromise = null;

async function ensureLeaveBalanceLedgerTable(db) {
  await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await db.query(`
    CREATE TABLE IF NOT EXISTS leave_balance_ledger (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      leave_type TEXT NOT NULL,
      action TEXT NOT NULL,
      affected_bucket TEXT NOT NULL,
      days_changed NUMERIC NOT NULL DEFAULT 0,
      old_value NUMERIC,
      new_value NUMERIC,
      related_leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,
      actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
      actor_kind TEXT NOT NULL DEFAULT 'user',
      remarks TEXT,
      metadata_json JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_user_created
      ON leave_balance_ledger(user_id, created_at DESC);
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_action
      ON leave_balance_ledger(action);
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_leave_request
      ON leave_balance_ledger(related_leave_request_id)
      WHERE related_leave_request_id IS NOT NULL;
  `);
}

function initLeaveBalanceLedger(dbPool) {
  if (_ensurePromise) return _ensurePromise;
  _ensurePromise = ensureLeaveBalanceLedgerTable(dbPool).catch((err) => {
    console.error('[leaveBalanceLedger] ensure table failed', err);
    throw err;
  });
  return _ensurePromise;
}

/**
 * @param {import('pg').PoolClient} client
 * @param {object} row
 */
async function insertLeaveBalanceLedger(client, row) {
  if (_ensurePromise) await _ensurePromise;
  const {
    userId,
    leaveType,
    action,
    affectedBucket,
    daysChanged = 0,
    oldValue = null,
    newValue = null,
    relatedLeaveRequestId = null,
    actorUserId = null,
    actorKind = 'user',
    remarks = null,
    metadataJson = null,
  } = row;

  return client.query(
    `
      INSERT INTO leave_balance_ledger (
        user_id, leave_type, action, affected_bucket, days_changed,
        old_value, new_value, related_leave_request_id,
        actor_user_id, actor_kind, remarks, metadata_json
      )
      VALUES (
        $1::uuid, $2::text, $3::text, $4::text, $5::numeric,
        $6::numeric, $7::numeric, $8::uuid,
        $9::uuid, $10::text, $11::text, $12::jsonb
      )
    `,
    [
      userId,
      leaveType,
      action,
      affectedBucket,
      daysChanged,
      oldValue,
      newValue,
      relatedLeaveRequestId,
      actorUserId,
      actorKind,
      remarks,
      metadataJson,
    ]
  );
}

/**
 * Snapshot one row from leave_balances (numeric fields as floats).
 */
async function fetchBalanceSnapshot(client, userId, ledgerType) {
  const r = await client.query(
    `SELECT COALESCE(earned_days, 0)::numeric AS earned_days,
            COALESCE(used_days, 0)::numeric AS used_days,
            COALESCE(pending_days, 0)::numeric AS pending_days,
            COALESCE(adjusted_days, 0)::numeric AS adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     LIMIT 1`,
    [userId, ledgerType]
  );
  if (r.rows.length === 0) {
    return { earned_days: 0, used_days: 0, pending_days: 0, adjusted_days: 0 };
  }
  const x = r.rows[0];
  return {
    earned_days: parseFloat(x.earned_days),
    used_days: parseFloat(x.used_days),
    pending_days: parseFloat(x.pending_days),
    adjusted_days: parseFloat(x.adjusted_days),
  };
}

module.exports = {
  initLeaveBalanceLedger,
  insertLeaveBalanceLedger,
  fetchBalanceSnapshot,
  /** @type {typeof _ensurePromise} */
  _ensurePromise: () => _ensurePromise,
};
