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

function leaveBalanceAdjustmentError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function normalizeLeaveBalanceAdjustment(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw leaveBalanceAdjustmentError('adjustment_days must be a number');
  }
  const rounded = Math.round((parsed + Number.EPSILON) * 1000) / 1000;
  if (rounded === 0) {
    throw leaveBalanceAdjustmentError('adjustment_days must not be zero');
  }
  return rounded;
}

function normalizeLeaveBalanceAdjustmentReason(value) {
  const reason = String(value || '').trim();
  if (!reason) {
    throw leaveBalanceAdjustmentError('A reason is required for every balance adjustment');
  }
  if (reason.length > 500) {
    throw leaveBalanceAdjustmentError('Adjustment reason must be 500 characters or less');
  }
  return reason;
}

function buildLeaveBalanceHistoryFilters({
  scopeAllUsers = false,
  scopedUserId = null,
  leaveType = '',
  action = '',
  from = '',
  to = '',
  affectedBucket = '',
}) {
  const summaryWhere = [];
  const summaryParams = [];

  function addSummaryFilter(sql, value) {
    const parameter = summaryParams.length + 1;
    summaryWhere.push(sql.replace('$?', `$${parameter}`));
    summaryParams.push(value);
  }

  if (!scopeAllUsers) {
    addSummaryFilter('l.user_id = $?::uuid', scopedUserId);
  }
  if (leaveType) addSummaryFilter('l.leave_type = $?', leaveType);
  if (action) addSummaryFilter('l.action = $?', action);
  if (from && /^\d{4}-\d{2}-\d{2}$/.test(from)) {
    addSummaryFilter('l.created_at >= $?::date', from);
  }
  if (to && /^\d{4}-\d{2}-\d{2}$/.test(to)) {
    addSummaryFilter("l.created_at < ($?::date + interval '1 day')", to);
  }

  const summaryWhereSql = summaryWhere.length > 0
    ? summaryWhere.join(' AND ')
    : 'true';
  const where = [...summaryWhere];
  const params = [...summaryParams];
  if (affectedBucket) {
    const parameter = params.length + 1;
    where.push(`LOWER(l.affected_bucket) = $${parameter}`);
    params.push(affectedBucket);
  }

  return {
    summaryWhereSql,
    summaryParams,
    whereSql: where.length > 0 ? where.join(' AND ') : 'true',
    params,
    nextParameter: params.length + 1,
  };
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

function balanceSnapshot(row) {
  return {
    earned_days: parseFloat(row?.earned_days || 0),
    used_days: parseFloat(row?.used_days || 0),
    pending_days: parseFloat(row?.pending_days || 0),
    adjusted_days: parseFloat(row?.adjusted_days || 0),
  };
}

function availableFromSnapshot(snapshot) {
  return (
    snapshot.earned_days -
    snapshot.used_days +
    snapshot.adjusted_days -
    snapshot.pending_days
  );
}

async function applyAdminLeaveBalanceAdjustment(client, input) {
  const daysChanged = normalizeLeaveBalanceAdjustment(input.daysChanged);
  const remarks = normalizeLeaveBalanceAdjustmentReason(input.remarks);

  await client.query(
    `INSERT INTO leave_balances (
       user_id, leave_type, earned_days, used_days, pending_days,
       adjusted_days, as_of_date, created_at, updated_at
     ) VALUES ($1::uuid, $2::text, 0, 0, 0, 0, COALESCE($3::date, CURRENT_DATE), now(), now())
     ON CONFLICT (user_id, leave_type) DO NOTHING`,
    [input.userId, input.leaveType, input.asOfDate || null]
  );

  const locked = await client.query(
    `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     FOR UPDATE`,
    [input.userId, input.leaveType]
  );
  if (locked.rows.length === 0) {
    throw new Error('Failed to lock leave balance for adjustment');
  }
  const before = balanceSnapshot(locked.rows[0]);

  const updated = await client.query(
    `UPDATE leave_balances
     SET adjusted_days = ROUND((COALESCE(adjusted_days, 0) + $3::numeric)::numeric, 3),
         as_of_date = COALESCE($4::date, CURRENT_DATE),
         updated_at = now()
     WHERE user_id = $1::uuid AND leave_type = $2::text
     RETURNING *`,
    [input.userId, input.leaveType, daysChanged, input.asOfDate || null]
  );
  if (updated.rows.length === 0) {
    throw new Error('Failed to apply leave balance adjustment');
  }

  const row = updated.rows[0];
  const after = balanceSnapshot(row);
  await insertLeaveBalanceLedger(client, {
    userId: input.userId,
    leaveType: input.leaveType,
    action: 'admin_adjustment',
    affectedBucket: 'adjusted',
    daysChanged,
    oldValue: before.adjusted_days,
    newValue: after.adjusted_days,
    actorUserId: input.actorUserId || null,
    actorKind: input.actorKind || 'admin',
    remarks,
    metadataJson: {
      before,
      after,
      available_before: availableFromSnapshot(before),
      available_after: availableFromSnapshot(after),
      as_of_date: input.asOfDate || null,
    },
  });

  return { row, before, after, daysChanged };
}

module.exports = {
  applyAdminLeaveBalanceAdjustment,
  buildLeaveBalanceHistoryFilters,
  initLeaveBalanceLedger,
  insertLeaveBalanceLedger,
  fetchBalanceSnapshot,
  normalizeLeaveBalanceAdjustment,
  normalizeLeaveBalanceAdjustmentReason,
  /** @type {typeof _ensurePromise} */
  _ensurePromise: () => _ensurePromise,
};
