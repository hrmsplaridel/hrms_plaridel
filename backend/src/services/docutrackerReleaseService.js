const { mapDocumentRow, normalizeStatus } = require('./docutrackerDocumentMapper');
const { RELEASE_ACTION } = require('./docutrackerSystemAccessActions');
const {
  canUserPerformDocumentAction,
  hasReleasePermission,
  isReleaseTrackedDocument,
  resolveUserSpecificPermissionFromRows,
  canReleaseDocument,
} = require('./docutrackerWorkflowService');
const { sameEntityId } = require('../utils/sameEntityId');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REMARKS_LENGTH = 2000;

function serviceError(code, message) {
  const err = new Error(message);
  err.code = code;
  return err;
}

async function listActiveDepartments(client) {
  const result = await client.query(
    `SELECT d.id::text AS id, d.name
     FROM departments d
     WHERE COALESCE(d.is_active, true) = true
     ORDER BY d.name ASC`
  );
  return result.rows.map((row) => ({ id: row.id, name: row.name }));
}

/**
 * Release dialog data. Departments are returned only to users who may release
 * now; nobody else needs the list.
 */
async function getReleaseOptions(pool, user, documentId) {
  const docRes = await pool.query('SELECT * FROM docutracker_documents WHERE id = $1', [documentId]);
  const doc = docRes.rows[0];
  if (!doc) throw serviceError('NOT_FOUND', 'Document not found');
  if (!(await canUserPerformDocumentAction(pool, { user, document: doc, action: 'view' }))) {
    throw serviceError('FORBIDDEN', 'You do not have access to this document');
  }
  const canRelease = await canReleaseDocument(pool, { user, document: doc });
  return {
    release_required: doc.release_required === true && !doc.source_module,
    released: Boolean(doc.released_at),
    can_release: canRelease,
    suggested_department_id: null,
    departments: canRelease ? await listActiveDepartments(pool) : [],
  };
}

/**
 * Active members of [departmentId] without a user-specific view deny for
 * [documentType], excluding [excludeUserId]: the users who can open the
 * released document. One query for members, one for their user view rows.
 */
async function listReleaseRecipients(client, { departmentId, documentType, excludeUserId }) {
  const membersRes = await client.query(
    `SELECT DISTINCT u.id::text AS user_id
     FROM assignments a
     JOIN users u ON u.id = a.employee_id
     WHERE a.department_id = $1::uuid
       AND COALESCE(a.is_active, true) = true
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       AND COALESCE(u.is_active, true) = true`,
    [departmentId, todayInHrmsTimezone()]
  );
  const members = membersRes.rows.filter((m) => !sameEntityId(m.user_id, excludeUserId));
  if (!members.length) return [];

  const permRes = await client.query(
    `SELECT user_id::text AS user_id, role_id, document_type, granted
     FROM docutracker_permissions
     WHERE action = 'view'
       AND (document_type = $1 OR document_type = '*')
       AND user_id = ANY($2::uuid[])`,
    [documentType, members.map((m) => m.user_id)]
  );

  return members
    .filter(
      (member) =>
        resolveUserSpecificPermissionFromRows(permRes.rows, {
          userId: member.user_id,
          documentType,
        }) !== false
    )
    .map((member) => member.user_id);
}

async function insertReleaseNotifications(client, { document, departmentName, recipientIds }) {
  if (!recipientIds.length) return 0;
  const result = await client.query(
    `INSERT INTO docutracker_notifications
       (document_id, user_id, type, event_key, title, body)
     SELECT $1::uuid, recipient.user_id, 'released', $2, $3, $4
     FROM unnest($5::uuid[]) AS recipient(user_id)
     ON CONFLICT (document_id, user_id, type, event_key)
     WHERE event_key IS NOT NULL
     DO NOTHING`,
    [
      document.id,
      `released:doc:${document.id}`,
      'Document released to your department',
      `${document.title} was released to ${departmentName}.`,
      recipientIds,
    ]
  );
  return result.rowCount || 0;
}

/**
 * Releases an approved, release-required native document to one department.
 * Transactional and idempotent: a repeat release to the same department is a
 * safe no-op; a different department is a conflict (no re-release/correction).
 */
async function releaseDocument(pool, user, documentId, payload = {}) {
  const departmentId = String(payload.department_id || '').trim();
  const remarks = typeof payload.remarks === 'string' ? payload.remarks.trim() : '';
  const idempotencyKey =
    typeof payload.idempotency_key === 'string' && payload.idempotency_key.trim()
      ? payload.idempotency_key.trim()
      : null;
  if (!UUID_RE.test(departmentId)) {
    throw serviceError('VALIDATION', 'Select the department to release this document to.');
  }
  if (remarks.length > MAX_REMARKS_LENGTH) {
    throw serviceError('VALIDATION', `Release remarks must be ${MAX_REMARKS_LENGTH} characters or fewer.`);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const docRes = await client.query(
      'SELECT * FROM docutracker_documents WHERE id = $1 FOR UPDATE',
      [documentId]
    );
    const doc = docRes.rows[0];
    if (!doc) throw serviceError('NOT_FOUND', 'Document not found');
    if (!(await canUserPerformDocumentAction(client, { user, document: doc, action: 'view' }))) {
      throw serviceError('FORBIDDEN', 'You do not have access to this document');
    }

    if (idempotencyKey) {
      const previous = await client.query(
        `SELECT actor_id, response_payload
         FROM docutracker_transition_requests
         WHERE document_id = $1 AND action = $2 AND idempotency_key = $3
         LIMIT 1`,
        [documentId, RELEASE_ACTION, idempotencyKey]
      );
      if (previous.rowCount > 0) {
        if (previous.rows[0].actor_id && !sameEntityId(previous.rows[0].actor_id, user.id)) {
          throw serviceError('FORBIDDEN', 'Idempotency key already used by a different actor');
        }
        await client.query('COMMIT');
        return previous.rows[0].response_payload;
      }
    }

    if (doc.source_module || doc.release_required !== true) {
      throw serviceError('VALIDATION', 'This document does not require a release.');
    }
    if (!(await hasReleasePermission(client, { user, documentType: doc.document_type }))) {
      throw serviceError('FORBIDDEN', 'You are not authorized to release this document.');
    }
    if (normalizeStatus(doc.status) !== 'approved') {
      throw serviceError('CONFLICT', 'This document can be released only after final approval.');
    }
    if (doc.released_at) {
      if (sameEntityId(doc.released_to_department_id, departmentId)) {
        await client.query('COMMIT');
        return { document: mapDocumentRow(doc), already_released: true };
      }
      throw serviceError(
        'CONFLICT',
        `This document was already released to ${doc.released_to_department_name || 'another department'}. A release cannot be changed.`
      );
    }
    if (!isReleaseTrackedDocument(doc) || !(await canReleaseDocument(client, { user, document: doc }))) {
      throw serviceError('FORBIDDEN', 'You are not authorized to release this document.');
    }

    const deptRes = await client.query(
      `SELECT id::text AS id, name
       FROM departments
       WHERE id = $1::uuid AND COALESCE(is_active, true) = true
       LIMIT 1`,
      [departmentId]
    );
    const department = deptRes.rows[0];
    if (!department) {
      throw serviceError('VALIDATION', 'Select an active department to release this document to.');
    }
    const actorRes = await client.query('SELECT full_name FROM users WHERE id = $1 LIMIT 1', [user.id]);
    const actorName = actorRes.rows[0]?.full_name || null;

    const updateRes = await client.query(
      `UPDATE docutracker_documents
       SET released_to_department_id = $2::uuid,
           released_to_department_name = $3,
           released_by = $4::uuid,
           released_by_name = $5,
           released_at = now(),
           release_remarks = $6,
           updated_at = now()
       WHERE id = $1
         AND released_at IS NULL
         AND release_required = true
         AND status = 'approved'
       RETURNING *`,
      [documentId, department.id, department.name, user.id, actorName, remarks || null]
    );
    const updated = updateRes.rows[0];
    if (!updated) throw serviceError('CONFLICT', 'This document was already released.');

    await client.query(
      `INSERT INTO docutracker_document_history
         (document_id, action, actor_id, actor_name, from_step, to_step,
          from_status, to_status, remarks, metadata)
       VALUES ($1, 'released', $2, $3, $4, $4, 'approved', 'approved', $5, $6::jsonb)`,
      [
        documentId,
        user.id,
        actorName,
        updated.current_step || null,
        remarks || null,
        JSON.stringify({
          released_to_department_id: department.id,
          released_to_department_name: department.name,
        }),
      ]
    );

    const recipientIds = await listReleaseRecipients(client, {
      departmentId: department.id,
      documentType: doc.document_type,
      excludeUserId: user.id,
    });
    await insertReleaseNotifications(client, {
      document: updated,
      departmentName: department.name,
      recipientIds,
    });

    const response = { document: mapDocumentRow(updated), already_released: false };
    if (idempotencyKey) {
      await client.query(
        `INSERT INTO docutracker_transition_requests
           (document_id, action, idempotency_key, actor_id, response_payload)
         VALUES ($1, $2, $3, $4, $5::jsonb)
         ON CONFLICT (document_id, action, idempotency_key) DO NOTHING`,
        [documentId, RELEASE_ACTION, idempotencyKey, user.id, JSON.stringify(response)]
      );
    }
    await client.query('COMMIT');
    return response;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** Release policy for every configured native document type. */
async function listReleasePolicies(client) {
  const result = await client.query(
    `SELECT rc.document_type,
            COALESCE(dt.requires_release, false) AS requires_release
     FROM docutracker_routing_configs rc
     LEFT JOIN docutracker_document_types dt ON dt.document_type = rc.document_type
     ORDER BY rc.document_type ASC`
  );
  return result.rows.map((row) => ({
    document_type: row.document_type,
    requires_release: row.requires_release === true,
  }));
}

/**
 * Admin-only. Applies to documents reaching final approval afterwards;
 * existing approved documents keep their release state.
 */
async function setReleasePolicy(pool, actor, documentType, requiresRelease, { writeAudit } = {}) {
  const type = String(documentType || '').trim();
  if (typeof requiresRelease !== 'boolean') {
    throw serviceError('VALIDATION', 'requires_release must be true or false.');
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const configured = await client.query(
      'SELECT 1 FROM docutracker_routing_configs WHERE document_type = $1 LIMIT 1',
      [type]
    );
    if (!type || configured.rowCount === 0) {
      throw serviceError('NOT_FOUND', 'Document type is not configured in DocuTracker.');
    }
    const before = await client.query(
      'SELECT requires_release FROM docutracker_document_types WHERE document_type = $1',
      [type]
    );
    const previous = before.rows[0]?.requires_release === true;
    await client.query(
      `INSERT INTO docutracker_document_types (document_type, display_name, requires_release)
       VALUES ($1, $1, $2)
       ON CONFLICT (document_type)
       DO UPDATE SET requires_release = EXCLUDED.requires_release, updated_at = now()`,
      [type, requiresRelease]
    );
    if (writeAudit && previous !== requiresRelease) {
      await writeAudit(client, {
        actorId: actor.id,
        eventType: 'release_policy_updated',
        entityType: 'document_type',
        entityId: type,
        documentType: type,
        beforeState: { requires_release: previous },
        afterState: { requires_release: requiresRelease },
      });
    }
    await client.query('COMMIT');
    return { document_type: type, requires_release: requiresRelease };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  getReleaseOptions,
  listReleasePolicies,
  listReleaseRecipients,
  releaseDocument,
  setReleasePolicy,
};
