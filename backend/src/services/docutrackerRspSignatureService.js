const { createSignatureAsset } = require('./docutrackerDocumentBuilderService');
const { writeGovernanceAudit } = require('./docutrackerGovernanceAudit');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOURCE_SIGNATURE_CONFIGS = Object.freeze({
  rsp: Object.freeze({
    label: 'RSP',
    includeUnassignedForAdmin: true,
    slots: Object.freeze({
      applicants_profile_entries: Object.freeze({
        prepared_by: 'Prepared by',
        checked_by: 'Checked by',
      }),
      selection_lineup_entries: Object.freeze({ prepared_by: 'Prepared by' }),
      computation_of_points_entries: Object.freeze({ prepared_by: 'Prepared by' }),
      work_experience_sheet_entries: Object.freeze({ applicant: 'Signature of Applicant' }),
      turn_around_time_entries: Object.freeze({
        prepared_by: 'Prepared by',
        noted_by: 'Noted by',
      }),
    }),
    formNames: Object.freeze({
      applicants_profile_entries: 'Applicants Profile',
      selection_lineup_entries: 'Selection Line-Up',
      computation_of_points_entries: 'Computation of Points',
      work_experience_sheet_entries: 'Work Experience Sheet',
      turn_around_time_entries: 'Turn Around Time',
    }),
  }),
  ld: Object.freeze({
    label: 'L&D',
    includeUnassignedForAdmin: true,
    slots: Object.freeze({
      idp_entries: Object.freeze({
        prepared_by: 'Prepared by',
        reviewed_by: 'Reviewed by',
        noted_by: 'Noted by',
        approved_by: 'Approved by',
      }),
      action_brainstorming_coaching_entries: Object.freeze({
        certified_by: 'Certified by',
      }),
    }),
    formNames: Object.freeze({
      idp_entries: 'Individual Development Plan',
      action_brainstorming_coaching_entries: 'Action Brainstorming and Coaching',
    }),
  }),
});

const RSP_SIGNATURE_SLOTS = SOURCE_SIGNATURE_CONFIGS.rsp.slots;
const LD_SIGNATURE_SLOTS = SOURCE_SIGNATURE_CONFIGS.ld.slots;

function serviceError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function sourceConfig(sourceModule, sourceTable, sourceRecordId, slotKey = null) {
  const normalizedModule = String(sourceModule || '').trim().toLowerCase();
  const moduleConfig = SOURCE_SIGNATURE_CONFIGS[normalizedModule];
  if (!moduleConfig || !Object.hasOwn(moduleConfig.slots, sourceTable)) {
    throw serviceError('NOT_FOUND', 'Source form signature fields were not found');
  }
  if (!UUID_RE.test(String(sourceRecordId || ''))) {
    throw serviceError('NOT_FOUND', 'Source form was not found');
  }
  if (slotKey != null && !Object.hasOwn(moduleConfig.slots[sourceTable], slotKey)) {
    throw serviceError('NOT_FOUND', 'Source signature field was not found');
  }
  return {
    sourceModule: normalizedModule,
    moduleConfig,
    slots: moduleConfig.slots[sourceTable],
    formName: moduleConfig.formNames[sourceTable],
  };
}

async function loadContext(db, user, sourceModule, sourceTable, sourceRecordId, { forUpdate = false } = {}) {
  const config = sourceConfig(sourceModule, sourceTable, sourceRecordId);
  const source = await db.query(
    `SELECT id FROM "${sourceTable}" WHERE id = $1::uuid${forUpdate ? ' FOR UPDATE' : ''}`,
    [sourceRecordId]
  );
  if (!source.rowCount) throw serviceError('NOT_FOUND', `${config.moduleConfig.label} form was not found`);
  const rows = await db.query(
    `SELECT s.id, s.slot_key, s.label, s.assigned_signer_id,
            assigned.full_name AS assigned_signer_name,
            s.signature_asset_id, s.signed_by, s.signer_name_snapshot,
            s.signed_at, a.mime_type,
            encode(a.image_bytes, 'base64') AS signature_image_base64
     FROM docutracker_rsp_source_signatures s
     JOIN users assigned ON assigned.id = s.assigned_signer_id
     LEFT JOIN docutracker_signature_assets a ON a.id = s.signature_asset_id
     WHERE s.source_table = $1 AND s.source_record_id = $2::uuid
     ORDER BY s.created_at, s.slot_key`,
    [sourceTable, sourceRecordId]
  );
  const isAdmin = String(user.role || '').toLowerCase() === 'admin';
  const isAssigned = rows.rows.some(
    (row) => String(row.assigned_signer_id) === String(user.id)
  );
  if (!isAdmin && !isAssigned) {
    throw serviceError('FORBIDDEN', 'Only an assigned signer can open these signature fields');
  }
  return { ...config, rows: rows.rows, isAdmin };
}

function serialize(context, user, sourceTable, sourceRecordId) {
  return {
    source_module: context.sourceModule,
    source_table: sourceTable,
    source_record_id: sourceRecordId,
    source_status: 'saved',
    can_assign: context.isAdmin,
    signatures: Object.entries(context.slots).map(([slotKey, label]) => {
      const row = context.rows.find((candidate) => candidate.slot_key === slotKey);
      return {
        id: row?.id || null,
        slot_key: slotKey,
        label,
        assigned_signer_id: row?.assigned_signer_id || '',
        assigned_signer_name: row?.assigned_signer_name || null,
        can_sign: String(row?.assigned_signer_id || '') === String(user.id),
        signature_asset_id: row?.signature_asset_id || null,
        signature_image_base64: row?.signature_image_base64 || null,
        mime_type: row?.mime_type || null,
        signed_by: row?.signed_by || null,
        signer_name_snapshot: row?.signer_name_snapshot || null,
        signed_at: row?.signed_at || null,
      };
    }),
  };
}

async function getSourceSignatures(pool, user, sourceModule, sourceTable, sourceRecordId) {
  try {
    const context = await loadContext(pool, user, sourceModule, sourceTable, sourceRecordId);
    return serialize(context, user, sourceTable, sourceRecordId);
  } catch (error) {
    if (error?.code === '42P01') {
      throw serviceError('UNAVAILABLE', 'Source form e-signatures are not initialized');
    }
    throw error;
  }
}

function requestTitle(sourceModule, sourceTable, record) {
  const candidates = {
    applicants_profile_entries: record.position_applied_for,
    selection_lineup_entries: record.vacant_position,
    computation_of_points_entries: record.position,
    work_experience_sheet_entries:
      record.applicant_name && record.position_applied_for
        ? `${record.applicant_name} - ${record.position_applied_for}`
        : record.applicant_name || record.position_applied_for,
    turn_around_time_entries: record.position,
    idp_entries:
      record.name && record.position
        ? `${record.name} - ${record.position}`
        : record.name || record.position,
    action_brainstorming_coaching_entries:
      record.department && record.date
        ? `${record.department} - ${record.date}`
        : record.department || record.date,
  };
  const config = sourceConfig(sourceModule, sourceTable, record.id);
  return String(candidates[sourceTable] || config.formName).trim();
}

async function listSourceSignatureRequests(pool, user, sourceModule) {
  try {
    const normalizedModule = String(sourceModule || '').trim().toLowerCase();
    const moduleConfig = SOURCE_SIGNATURE_CONFIGS[normalizedModule];
    if (!moduleConfig) throw serviceError('NOT_FOUND', 'Source signature requests were not found');
    const isAdmin = String(user.role || '').toLowerCase() === 'admin';
    const assignedRows = [];
    if (isAdmin && moduleConfig.includeUnassignedForAdmin) {
      for (const sourceTable of Object.keys(moduleConfig.slots)) {
        const sourceRows = await pool.query(
          `SELECT id AS source_record_id
           FROM "${sourceTable}"
           ORDER BY updated_at DESC NULLS LAST, id`
        );
        assignedRows.push(...sourceRows.rows.map((row) => ({
          source_table: sourceTable,
          source_record_id: row.source_record_id,
        })));
      }
    } else {
      const assigned = await pool.query(
        `SELECT DISTINCT source_table, source_record_id
         FROM docutracker_rsp_source_signatures
         WHERE assigned_signer_id = $1::uuid
           AND source_table = ANY($2::text[])
         ORDER BY source_table, source_record_id`,
        [user.id, Object.keys(moduleConfig.slots)]
      );
      assignedRows.push(...assigned.rows);
    }
    const requests = [];
    for (const assignment of assignedRows) {
      sourceConfig(normalizedModule, assignment.source_table, assignment.source_record_id);
      const context = await loadContext(
        pool,
        user,
        normalizedModule,
        assignment.source_table,
        assignment.source_record_id
      );
      const source = await pool.query(
        `SELECT to_jsonb(source_row) AS source_record
         FROM "${assignment.source_table}" source_row
         WHERE id = $1::uuid`,
        [assignment.source_record_id]
      );
      if (!source.rowCount) continue;
      const record = source.rows[0].source_record;
      const signatureBundle = serialize(
        context,
        user,
        assignment.source_table,
        assignment.source_record_id
      );
      const requiresSetup =
        context.isAdmin &&
        signatureBundle.signatures.some((signature) => !signature.assigned_signer_id);
      const hasPendingSignature = signatureBundle.signatures.some(
        (signature) =>
          signature.can_sign &&
          !(signature.signature_asset_id && signature.signed_at)
      );
      if (!requiresSetup && !hasPendingSignature) continue;
      requests.push({
        source_module: normalizedModule,
        source_table: assignment.source_table,
        source_record_id: assignment.source_record_id,
        form_name: moduleConfig.formNames[assignment.source_table],
        title: requestTitle(normalizedModule, assignment.source_table, record),
        source_record: record,
        requires_setup: requiresSetup,
        signature_bundle: signatureBundle,
      });
    }
    return requests;
  } catch (error) {
    if (error?.code === '42P01') {
      throw serviceError(
        'UNAVAILABLE',
        'Source form e-signatures are not initialized'
      );
    }
    throw error;
  }
}

async function assignSourceSigner(pool, user, sourceModule, sourceTable, sourceRecordId, slotKey, input) {
  const config = sourceConfig(sourceModule, sourceTable, sourceRecordId, slotKey);
  if (String(user.role || '').toLowerCase() !== 'admin') {
    throw serviceError('FORBIDDEN', 'Only an administrator can assign source form signers');
  }
  const signerId = String(input.assigned_signer_id || '').trim();
  if (!UUID_RE.test(signerId)) throw serviceError('VALIDATION', 'Select an active signer');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const context = await loadContext(client, user, sourceModule, sourceTable, sourceRecordId, { forUpdate: true });
    const active = await client.query(
      'SELECT id, full_name FROM users WHERE id = $1::uuid AND is_active = true',
      [signerId]
    );
    if (!active.rowCount) throw serviceError('VALIDATION', 'Select an active signer');
    const previous = context.rows.find((row) => row.slot_key === slotKey) || null;
    const label = context.slots[slotKey];
    await client.query(
      `INSERT INTO docutracker_rsp_source_signatures
         (source_table, source_record_id, slot_key, label, assigned_signer_id, created_by)
       VALUES ($1, $2::uuid, $3, $4, $5::uuid, $6::uuid)
       ON CONFLICT (source_table, source_record_id, slot_key) DO UPDATE SET
         label = EXCLUDED.label,
         assigned_signer_id = EXCLUDED.assigned_signer_id,
         signature_asset_id = CASE WHEN docutracker_rsp_source_signatures.assigned_signer_id = EXCLUDED.assigned_signer_id THEN docutracker_rsp_source_signatures.signature_asset_id ELSE NULL END,
         signed_by = CASE WHEN docutracker_rsp_source_signatures.assigned_signer_id = EXCLUDED.assigned_signer_id THEN docutracker_rsp_source_signatures.signed_by ELSE NULL END,
         signer_name_snapshot = CASE WHEN docutracker_rsp_source_signatures.assigned_signer_id = EXCLUDED.assigned_signer_id THEN docutracker_rsp_source_signatures.signer_name_snapshot ELSE NULL END,
         signed_at = CASE WHEN docutracker_rsp_source_signatures.assigned_signer_id = EXCLUDED.assigned_signer_id THEN docutracker_rsp_source_signatures.signed_at ELSE NULL END,
         updated_at = now()`,
      [sourceTable, sourceRecordId, slotKey, label, signerId, user.id]
    );
    await writeGovernanceAudit(client, {
      actorId: user.id,
      eventType: 'source_signer_assigned',
      entityType: `${config.sourceModule}_source_signature`,
      entityId: sourceRecordId,
      documentType: config.sourceModule,
      targetUserId: signerId,
      beforeState: previous && { slot_key: slotKey, assigned_signer_id: previous.assigned_signer_id },
      afterState: { source_table: sourceTable, slot_key: slotKey, assigned_signer_id: signerId },
    });
    await client.query('COMMIT');
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
  return getSourceSignatures(pool, user, sourceModule, sourceTable, sourceRecordId);
}

async function signSourceSlot(pool, user, sourceModule, sourceTable, sourceRecordId, slotKey, input) {
  const config = sourceConfig(sourceModule, sourceTable, sourceRecordId, slotKey);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const context = await loadContext(client, user, sourceModule, sourceTable, sourceRecordId, { forUpdate: true });
    const current = context.rows.find((row) => row.slot_key === slotKey);
    if (!current || String(current.assigned_signer_id) !== String(user.id)) {
      throw serviceError('FORBIDDEN', 'Only the assigned person can sign this field');
    }
    let assetId = String(input.signature_asset_id || '').trim();
    if (assetId) {
      if (!UUID_RE.test(assetId)) throw serviceError('VALIDATION', 'Saved signature is invalid');
      const owned = await client.query(
        'SELECT id FROM docutracker_signature_assets WHERE id = $1::uuid AND owner_user_id = $2::uuid',
        [assetId, user.id]
      );
      if (!owned.rowCount) throw serviceError('FORBIDDEN', 'Saved signature not found');
    } else {
      assetId = (await createSignatureAsset(client, user, input)).id;
    }
    const active = await client.query(
      'SELECT full_name FROM users WHERE id = $1::uuid AND is_active = true',
      [user.id]
    );
    if (!active.rowCount) throw serviceError('FORBIDDEN', 'Only an active assigned signer can sign');
    const signerName = active.rows[0].full_name;
    await client.query(
      `UPDATE docutracker_rsp_source_signatures
       SET signature_asset_id = $1::uuid, signed_by = $2::uuid,
           signer_name_snapshot = $3, signed_at = now(), updated_at = now()
       WHERE source_table = $4 AND source_record_id = $5::uuid AND slot_key = $6`,
      [assetId, user.id, signerName, sourceTable, sourceRecordId, slotKey]
    );
    await writeGovernanceAudit(client, {
      actorId: user.id,
      eventType: current.signature_asset_id ? 'source_signature_replaced' : 'source_signed',
      entityType: `${config.sourceModule}_source_signature`,
      entityId: sourceRecordId,
      documentType: config.sourceModule,
      targetUserId: user.id,
      beforeState: current.signature_asset_id ? { slot_key: slotKey, signature_asset_id: current.signature_asset_id } : null,
      afterState: { source_table: sourceTable, slot_key: slotKey, signer_name: signerName },
    });
    await client.query('COMMIT');
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
  return getSourceSignatures(pool, user, sourceModule, sourceTable, sourceRecordId);
}

const getRspSourceSignatures = getSourceSignatures;
const assignRspSourceSigner = assignSourceSigner;
const signRspSourceSlot = signSourceSlot;

function listRspSignatureRequests(pool, user) {
  return listSourceSignatureRequests(pool, user, 'rsp');
}

function listLdSignatureRequests(pool, user) {
  return listSourceSignatureRequests(pool, user, 'ld');
}

module.exports = {
  RSP_SIGNATURE_SLOTS,
  LD_SIGNATURE_SLOTS,
  getSourceSignatures,
  getRspSourceSignatures,
  listSourceSignatureRequests,
  listRspSignatureRequests,
  listLdSignatureRequests,
  assignSourceSigner,
  assignRspSourceSigner,
  signSourceSlot,
  signRspSourceSlot,
};
