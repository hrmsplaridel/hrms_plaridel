const {
  createSignatureAsset,
} = require('./docutrackerDocumentBuilderService');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPLICANT_SLOT = 'applicant';
const APPLICANT_SIGNABLE_STATUSES = new Set([
  'draft',
  'returned',
  'pending',
  'pending_department_head',
  'pending_hr',
]);

function serviceError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function isUuid(value) {
  return UUID_RE.test(String(value || '').trim());
}

function canApplicantSignStatus(status) {
  return APPLICANT_SIGNABLE_STATUSES.has(
    String(status || '').trim().toLowerCase()
  );
}

function assertSupportedLeaveSource(sourceModule, sourceTable) {
  if (sourceModule !== 'dtr' || sourceTable !== 'leave_requests') {
    throw serviceError('NOT_FOUND', 'Linked source document not found');
  }
}

async function loadLeaveContext(db, leaveRequestId, user, { forUpdate = false } = {}) {
  if (!isUuid(leaveRequestId)) {
    throw serviceError('NOT_FOUND', 'Leave request not found');
  }
  const result = await db.query(
    `SELECT lr.id,
            lr.status,
            COALESCE(lr.user_id, lr.employee_id) AS employee_user_id,
            employee.full_name AS employee_name,
            lr.assigned_department_head_id,
            EXISTS (
              SELECT 1
              FROM leave_request_department_reviewers lrr
              WHERE lrr.leave_request_id = lr.id
                AND lrr.reviewer_id = $2::uuid
            ) AS is_snapshotted_reviewer,
            EXISTS (
              SELECT 1
              FROM leave_request_history h
              WHERE h.leave_request_id = lr.id
                AND h.acted_by = $2::uuid
                AND h.action IN (
                  'department_head_approved',
                  'department_head_rejected',
                  'department_head_returned'
                )
            ) AS was_department_reviewer
     FROM leave_requests lr
     LEFT JOIN users employee
       ON employee.id = COALESCE(lr.user_id, lr.employee_id)
     WHERE lr.id = $1::uuid
     ${forUpdate ? 'FOR UPDATE OF lr' : ''}`,
    [leaveRequestId, user.id]
  );
  const row = result.rows[0];
  if (!row) throw serviceError('NOT_FOUND', 'Leave request not found');

  const userId = String(user.id || '');
  const role = String(user.role || '').toLowerCase();
  const isOwner = String(row.employee_user_id || '') === userId;
  const isHrOrAdmin = role === 'admin' || role === 'hr';
  const isReviewer =
    String(row.assigned_department_head_id || '') === userId ||
    row.is_snapshotted_reviewer === true ||
    row.was_department_reviewer === true;
  if (!isOwner && !isHrOrAdmin && !isReviewer) {
    throw serviceError('FORBIDDEN', 'You do not have access to this leave form');
  }
  return { ...row, isOwner, isHrOrAdmin, isReviewer };
}

function mapApplicantSignature(context, row, user) {
  const canSign =
    context.isOwner &&
    String(context.employee_user_id || '') === String(user.id || '') &&
    canApplicantSignStatus(context.status);
  return {
    id: row?.id || null,
    slot_key: APPLICANT_SLOT,
    label: 'Signature of Applicant',
    assigned_signer_id: context.employee_user_id,
    assigned_signer_name: context.employee_name || null,
    can_sign: canSign,
    signature_asset_id: row?.signature_asset_id || null,
    signature_image_base64: row?.signature_image_base64 || null,
    mime_type: row?.mime_type || null,
    signed_by: row?.signed_by || null,
    signer_name_snapshot: row?.signer_name_snapshot || null,
    signed_at: row?.signed_at || null,
  };
}

async function getLeaveSourceSignatures(
  pool,
  user,
  sourceModule,
  sourceTable,
  leaveRequestId
) {
  assertSupportedLeaveSource(sourceModule, sourceTable);
  const context = await loadLeaveContext(pool, leaveRequestId, user);
  let result;
  try {
    result = await pool.query(
      `SELECT s.id,
              s.slot_key,
              s.signature_asset_id,
              s.signed_by,
              s.signer_name_snapshot,
              s.signed_at,
              a.mime_type,
              encode(a.image_bytes, 'base64') AS signature_image_base64
       FROM docutracker_leave_signatures s
       JOIN docutracker_signature_assets a ON a.id = s.signature_asset_id
       WHERE s.leave_request_id = $1::uuid
         AND s.slot_key = $2
       LIMIT 1`,
      [leaveRequestId, APPLICANT_SLOT]
    );
  } catch (error) {
    if (error?.code === '42P01') {
      throw serviceError(
        'UNAVAILABLE',
        'Leave e-signatures are not initialized. Apply the DocuTracker leave-signature migration.'
      );
    }
    throw error;
  }
  return {
    source_module: sourceModule,
    source_table: sourceTable,
    source_record_id: leaveRequestId,
    source_status: context.status,
    signatures: [mapApplicantSignature(context, result.rows[0], user)],
  };
}

async function signLeaveSourceApplicant(
  pool,
  user,
  sourceModule,
  sourceTable,
  leaveRequestId,
  input
) {
  assertSupportedLeaveSource(sourceModule, sourceTable);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const context = await loadLeaveContext(client, leaveRequestId, user, {
      forUpdate: true,
    });
    if (!context.isOwner) {
      throw serviceError('FORBIDDEN', 'Only the applicant can sign this field');
    }
    if (!canApplicantSignStatus(context.status)) {
      throw serviceError(
        'CONFLICT',
        'This leave request can no longer change the applicant signature'
      );
    }

    let assetId = String(input.signature_asset_id || '').trim();
    if (assetId) {
      if (!isUuid(assetId)) {
        throw serviceError('VALIDATION', 'Saved signature is invalid');
      }
      const owned = await client.query(
        `SELECT id
         FROM docutracker_signature_assets
         WHERE id = $1::uuid AND owner_user_id = $2::uuid`,
        [assetId, user.id]
      );
      if (!owned.rowCount) {
        throw serviceError('FORBIDDEN', 'Saved signature not found');
      }
    } else {
      const asset = await createSignatureAsset(client, user, input);
      assetId = asset.id;
    }

    const activeUser = await client.query(
      `SELECT full_name
       FROM users
       WHERE id = $1::uuid AND is_active = true`,
      [user.id]
    );
    if (!activeUser.rowCount) {
      throw serviceError('FORBIDDEN', 'Only an active applicant can sign');
    }
    const signerName = activeUser.rows[0].full_name;
    const previous = await client.query(
      `SELECT id, signature_asset_id
       FROM docutracker_leave_signatures
       WHERE leave_request_id = $1::uuid AND slot_key = $2
       FOR UPDATE`,
      [leaveRequestId, APPLICANT_SLOT]
    );
    const isReplacement = previous.rowCount > 0;

    await client.query(
      `INSERT INTO docutracker_leave_signatures
         (leave_request_id, slot_key, assigned_signer_id, signature_asset_id,
          signed_by, signer_name_snapshot, signed_at, created_by)
       VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $3::uuid, $5, now(), $3::uuid)
       ON CONFLICT (leave_request_id, slot_key) DO UPDATE SET
         assigned_signer_id = EXCLUDED.assigned_signer_id,
         signature_asset_id = EXCLUDED.signature_asset_id,
         signed_by = EXCLUDED.signed_by,
         signer_name_snapshot = EXCLUDED.signer_name_snapshot,
         signed_at = now(),
         updated_at = now()`,
      [leaveRequestId, APPLICANT_SLOT, user.id, assetId, signerName]
    );
    await client.query(
      `INSERT INTO leave_request_history
         (leave_request_id, action, from_status, to_status, acted_by, remarks,
          metadata_json, acted_at)
       VALUES ($1::uuid, $2, $3, $3, $4::uuid, $5, $6::jsonb, now())`,
      [
        leaveRequestId,
        isReplacement ? 'signature_replaced' : 'signed',
        context.status,
        user.id,
        isReplacement
          ? 'Applicant replaced the e-signature'
          : 'Applicant added an e-signature',
        JSON.stringify({ slot_key: APPLICANT_SLOT, source_module: 'dtr' }),
      ]
    );
    await client.query('COMMIT');
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      // Preserve the original error.
    }
    if (error?.code === '42P01') {
      throw serviceError(
        'UNAVAILABLE',
        'Leave e-signatures are not initialized. Apply the DocuTracker leave-signature migration.'
      );
    }
    throw error;
  } finally {
    client.release();
  }
  return getLeaveSourceSignatures(
    pool,
    user,
    sourceModule,
    sourceTable,
    leaveRequestId
  );
}

module.exports = {
  APPLICANT_SLOT,
  canApplicantSignStatus,
  getLeaveSourceSignatures,
  signLeaveSourceApplicant,
};
