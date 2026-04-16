// Leave request history (audit trail) helper.
// Table is created idempotently (IF NOT EXISTS).

let _ensurePromise = null;

async function ensureLeaveRequestHistoryTable(db) {
  // Required for uuid_generate_v4() default.
  await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  await db.query(
    `
      CREATE TABLE IF NOT EXISTS leave_request_history (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        leave_request_id UUID NOT NULL REFERENCES leave_requests(id) ON DELETE CASCADE,
        action TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT NOT NULL,
        acted_by UUID REFERENCES users(id) ON DELETE SET NULL,
        acted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        remarks TEXT,
        metadata_json JSONB
      );
    `
  );

  await db.query(
    `
      CREATE INDEX IF NOT EXISTS idx_leave_request_history_leave_request_id
        ON leave_request_history(leave_request_id);
    `
  );
}

function initLeaveRequestHistory(dbPool) {
  if (_ensurePromise) return _ensurePromise;
  _ensurePromise = ensureLeaveRequestHistoryTable(dbPool).catch((err) => {
    // Let routes fail with a clearer error if history insert fails later.
    console.error('[leaveRequestHistory] Failed to ensure history table', err);
    throw err;
  });
  return _ensurePromise;
}

async function insertLeaveRequestHistory(
  dbOrClient,
  {
    leaveRequestId,
    action,
    fromStatus,
    toStatus,
    actedBy,
    remarks,
    metadataJson,
  }
) {
  if (_ensurePromise) await _ensurePromise;

  return dbOrClient.query(
    `
      INSERT INTO leave_request_history (
        leave_request_id,
        action,
        from_status,
        to_status,
        acted_by,
        remarks,
        metadata_json,
        acted_at
      )
      VALUES ($1::uuid, $2::text, $3::text, $4::text, $5::uuid, $6::text, $7::jsonb, now())
    `,
    [
      leaveRequestId,
      action,
      fromStatus,
      toStatus,
      actedBy,
      remarks,
      metadataJson,
    ]
  );
}

module.exports = {
  initLeaveRequestHistory,
  insertLeaveRequestHistory,
};

