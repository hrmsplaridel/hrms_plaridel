class AssignmentHistoryError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AssignmentHistoryError';
    this.statusCode = statusCode;
  }
}

const ASSIGNMENT_RECORD_TYPES = Object.freeze({
  primary: {
    table: 'assignments',
    entityType: 'assignment',
    notFoundMessage: 'Assignment not found',
  },
  additional: {
    table: 'employee_other_positions',
    entityType: 'employee_other_position',
    notFoundMessage: 'Employee other position not found',
  },
});

function normalizeChangeReason(value) {
  const reason = String(value || '').trim();
  if (!reason) {
    throw new AssignmentHistoryError('A reason is required to deactivate an assignment');
  }
  if (reason.length > 1000) {
    throw new AssignmentHistoryError('Assignment change reason must not exceed 1000 characters');
  }
  return reason;
}

function configFor(recordType) {
  const config = ASSIGNMENT_RECORD_TYPES[recordType];
  if (!config) throw new Error(`Unsupported assignment record type: ${recordType}`);
  return config;
}

async function writeAssignmentHistoryAudit(
  db,
  { actorId, recordType, recordId, action, reason, before, after }
) {
  const config = configFor(recordType);
  await db.query(
    `INSERT INTO audit_logs (
       user_id, action, entity_type, entity_id, details
     ) VALUES ($1::uuid, $2, $3, $4::uuid, $5)`,
    [
      actorId || null,
      action,
      config.entityType,
      recordId,
      JSON.stringify({ reason, before, after }),
    ]
  );
}

async function deactivateAssignmentRecord(
  db,
  { actorId, recordType, recordId, reason }
) {
  const config = configFor(recordType);
  const normalizedReason = normalizeChangeReason(reason);
  const existing = await db.query(
    `SELECT * FROM ${config.table} WHERE id = $1::uuid FOR UPDATE`,
    [recordId]
  );
  if (existing.rowCount === 0) {
    throw new AssignmentHistoryError(config.notFoundMessage, 404);
  }

  const before = existing.rows[0];
  if (before.is_active === false) {
    return { changed: false, record: before };
  }

  const updated = await db.query(
    `UPDATE ${config.table}
        SET is_active = false,
            updated_at = now()
      WHERE id = $1::uuid
      RETURNING *`,
    [recordId]
  );
  const after = updated.rows[0];
  await writeAssignmentHistoryAudit(db, {
    actorId,
    recordType,
    recordId,
    action: `${config.entityType}_deactivated`,
    reason: normalizedReason,
    before,
    after,
  });
  return { changed: true, record: after };
}

async function findPrimaryAssignmentDependencies(db, record) {
  const result = await db.query(
    `SELECT
       EXISTS (
         SELECT 1
           FROM dtr_daily_summary
          WHERE assignment_id = $1::uuid
       ) AS has_dtr,
       EXISTS (
         SELECT 1
           FROM leave_requests
          WHERE employee_id = $2::uuid
            AND end_date >= $3::date
            AND start_date <= COALESCE($4::date, 'infinity'::date)
       ) AS has_leave,
       EXISTS (
         SELECT 1
           FROM locator_slips
          WHERE employee_id = $2::uuid
            AND slip_date >= $3::date
            AND slip_date <= COALESCE($4::date, 'infinity'::date)
       ) AS has_locator`,
    [record.id, record.employee_id, record.effective_from, record.effective_to]
  );
  return result.rows[0] || {};
}

function dependencyMessage(dependencies) {
  const labels = [];
  if (dependencies.has_dtr) labels.push('DTR records');
  if (dependencies.has_leave) labels.push('leave requests');
  if (dependencies.has_locator) labels.push('locator requests');
  return labels.length > 0
    ? `This assignment cannot be permanently deleted because it is already used by ${labels.join(', ')}`
    : null;
}

async function restorePrimaryPredecessor(db, deletedRecord) {
  if (deletedRecord.is_active === false) return null;
  const predecessor = await db.query(
    `SELECT *
       FROM assignments
      WHERE employee_id = $1::uuid
        AND id <> $2::uuid
        AND is_active = true
        AND effective_from < $3::date
        AND effective_to = ($3::date - INTERVAL '1 day')::date
      ORDER BY effective_from DESC, created_at DESC, id DESC
      LIMIT 1
      FOR UPDATE`,
    [deletedRecord.employee_id, deletedRecord.id, deletedRecord.effective_from]
  );
  if (predecessor.rowCount === 0) return null;

  const before = predecessor.rows[0];
  const restored = await db.query(
    `UPDATE assignments
        SET effective_to = $2::date,
            updated_at = now()
      WHERE id = $1::uuid
      RETURNING *`,
    [before.id, deletedRecord.effective_to || null]
  );
  return { before, after: restored.rows[0] };
}

async function permanentlyDeleteFutureAssignment(
  db,
  { actorId, recordType, recordId, reason }
) {
  const config = configFor(recordType);
  const normalizedReason = normalizeChangeReason(reason);
  const existing = await db.query(
    `SELECT * FROM ${config.table} WHERE id = $1::uuid FOR UPDATE`,
    [recordId]
  );
  if (existing.rowCount === 0) {
    throw new AssignmentHistoryError(config.notFoundMessage, 404);
  }

  const record = existing.rows[0];
  const futureCheck = await db.query(
    `SELECT $1::date > (now() AT TIME ZONE 'Asia/Manila')::date AS is_future`,
    [record.effective_from]
  );
  if (futureCheck.rows[0]?.is_future !== true) {
    throw new AssignmentHistoryError(
      'Only an assignment that has not started can be permanently deleted',
      409
    );
  }

  if (recordType === 'primary') {
    const dependencyError = dependencyMessage(
      await findPrimaryAssignmentDependencies(db, record)
    );
    if (dependencyError) {
      throw new AssignmentHistoryError(dependencyError, 409);
    }
  }

  await db.query(`DELETE FROM ${config.table} WHERE id = $1::uuid`, [recordId]);
  const restoredPredecessor = recordType === 'primary'
    ? await restorePrimaryPredecessor(db, record)
    : null;
  await writeAssignmentHistoryAudit(db, {
    actorId,
    recordType,
    recordId,
    action: `${config.entityType}_mistake_deleted`,
    reason: normalizedReason,
    before: record,
    after: null,
  });
  if (restoredPredecessor) {
    await writeAssignmentHistoryAudit(db, {
      actorId,
      recordType: 'primary',
      recordId: restoredPredecessor.after.id,
      action: 'assignment_predecessor_restored',
      reason: normalizedReason,
      before: restoredPredecessor.before,
      after: restoredPredecessor.after,
    });
  }

  return { deleted: record, restoredPredecessor };
}

module.exports = {
  AssignmentHistoryError,
  deactivateAssignmentRecord,
  normalizeChangeReason,
  permanentlyDeleteFutureAssignment,
  writeAssignmentHistoryAudit,
};
