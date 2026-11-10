const { v4: uuidv4 } = require('uuid');
const {
  canUserPerformDocumentAction,
  canAddOwnSignatureToDocument,
  hasUserSignedDocument,
  nativeDocumentContentLockMessage,
} = require('./docutrackerWorkflowService');

const MAX_PAGES = 50;
const MAX_CONTENT_BYTES = 2 * 1024 * 1024;
const MAX_SIGNATURE_BYTES = 2 * 1024 * 1024;
const DEFAULT_FORMAT_VERSION = 2;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function serviceError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function validationError(message) {
  return serviceError('VALIDATION', message);
}

function forbiddenError(message) {
  return serviceError('FORBIDDEN', message);
}

function notFoundError(message) {
  return serviceError('NOT_FOUND', message);
}

function conflictError(message) {
  return serviceError('CONFLICT', message);
}

function isUuid(value) {
  return UUID_RE.test(String(value || '').trim());
}

function normalizePages(value) {
  if (!Array.isArray(value) || value.length === 0) {
    return [[{ insert: '\n' }]];
  }
  if (value.length > MAX_PAGES) {
    throw validationError(`A document can contain at most ${MAX_PAGES} pages`);
  }
  const pages = value.map((page, pageIndex) => {
    if (!Array.isArray(page)) {
      throw validationError(`Page ${pageIndex + 1} content is invalid`);
    }
    return page.map((operation) => {
      if (!operation || typeof operation !== 'object' || Array.isArray(operation)) {
        throw validationError(`Page ${pageIndex + 1} contains an invalid operation`);
      }
      return operation;
    });
  });
  if (Buffer.byteLength(JSON.stringify(pages), 'utf8') > MAX_CONTENT_BYTES) {
    throw validationError('Document content is too large');
  }
  return pages;
}

function numberInRange(value, min, max, name) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    throw validationError(`${name} is outside the allowed range`);
  }
  return parsed;
}

function normalizeField(raw, pageCount) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw validationError('A signature field is invalid');
  }
  const pageNumber = Math.trunc(numberInRange(raw.page_number, 1, pageCount, 'Page number'));
  const x = numberInRange(raw.position_x, 0, 1, 'Horizontal position');
  const y = numberInRange(raw.position_y, 0, 1, 'Vertical position');
  const width = numberInRange(raw.width, 0.03, 1, 'Signature width');
  const height = numberInRange(raw.height, 0.03, 1, 'Signature height');
  if (x + width > 1.000001 || y + height > 1.000001) {
    throw validationError('A signature field extends outside its A4 page');
  }
  const assignedSignerId = String(raw.assigned_signer_id || '').trim();
  if (!isUuid(assignedSignerId)) {
    throw validationError('Select a valid signer for every signature field');
  }
  const label = String(raw.label || 'Sign Here').trim();
  if (!label || label.length > 80) {
    throw validationError('Signature labels must contain 1 to 80 characters');
  }
  return {
    id: isUuid(raw.id) ? String(raw.id) : uuidv4(),
    pageNumber,
    x,
    y,
    width,
    height,
    assignedSignerId,
    label,
  };
}

function decodeSignatureImage(imageBase64, mimeType) {
  if (mimeType !== 'image/png' && mimeType !== 'image/jpeg') {
    throw validationError('Signature images must be PNG or JPEG');
  }
  const raw = String(imageBase64 || '').replace(/^data:image\/(png|jpeg);base64,/i, '');
  if (!raw) throw validationError('Signature image is required');
  const bytes = Buffer.from(raw, 'base64');
  if (!bytes.length || bytes.length > MAX_SIGNATURE_BYTES) {
    throw validationError('Signature image must be no larger than 2 MB');
  }
  const isPng = bytes.length >= 8 && bytes.subarray(0, 8).toString('hex') === '89504e470d0a1a0a';
  const isJpeg = bytes.length >= 3 && bytes.subarray(0, 3).toString('hex') === 'ffd8ff';
  if ((mimeType === 'image/png' && !isPng) || (mimeType === 'image/jpeg' && !isJpeg)) {
    throw validationError('Signature image content does not match its file type');
  }
  return bytes;
}

async function getDocumentForUpdate(client, documentId, forUpdate = false) {
  if (!isUuid(documentId)) throw notFoundError('Document not found');
  const result = await client.query(
    `SELECT * FROM docutracker_documents WHERE id = $1${forUpdate ? ' FOR UPDATE' : ''}`,
    [documentId]
  );
  if (!result.rowCount) throw notFoundError('Document not found');
  return result.rows[0];
}

async function canReadBuilder(client, document, user) {
  if (await canUserPerformDocumentAction(client, { user, document, action: 'view' })) {
    return true;
  }
  const assigned = await client.query(
    `SELECT 1 FROM docutracker_signature_fields
     WHERE document_id = $1 AND assigned_signer_id = $2::uuid
     LIMIT 1`,
    [document.id, user.id]
  );
  return assigned.rowCount > 0;
}

async function canEditBuilder(client, document, user) {
  return canUserPerformDocumentAction(client, { user, document, action: 'edit' });
}

// Printed signatory identity for a user row aliased `userAlias`: role plus the
// position of their current assignment. The Mayor falls back to the title used
// by resolveActiveMayor. Requires signerIdentityJoinSql(userAlias) in FROM.
function signerIdentitySelectSql(userAlias, outputPrefix) {
  return `LOWER(COALESCE(${userAlias}.role, '')) AS ${outputPrefix}_role,
            CASE
              WHEN LOWER(COALESCE(${userAlias}.role, '')) = 'mayor'
                THEN COALESCE(NULLIF(current_assignment.position_name, ''), 'Municipal Mayor')
              ELSE NULLIF(current_assignment.position_name, '')
            END AS ${outputPrefix}_position`;
}

function signerIdentityJoinSql(userAlias) {
  return `LEFT JOIN LATERAL (
       SELECT p.name AS position_name
       FROM assignments a
       LEFT JOIN positions p ON p.id = a.position_id
       WHERE a.employee_id = ${userAlias}.id
         AND (a.is_active IS NULL OR a.is_active = true)
         AND a.effective_from <= CURRENT_DATE
         AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     ) current_assignment ON true`;
}

async function memoSignerIdentity(client, userId, positionOverride) {
  const identity = await client.query(
    `SELECT u.full_name,
            ${signerIdentitySelectSql('u', 'signer')}
     FROM users u
     ${signerIdentityJoinSql('u')}
     WHERE u.id = $1::uuid`,
    [userId]
  );
  const row = identity.rows[0];
  if (!row) return null;
  const position = positionOverride || row.signer_position || null;
  return {
    id: String(userId),
    full_name: row.full_name,
    position,
    role: row.signer_role || null,
  };
}

/**
 * Memorandum signatories are offices, not the employee who typed the draft.
 * Prepared by is the HR department head. Noted by is the Mayor's Office.
 * Approved by is the Municipal Mayor when that account is not the office login.
 */
async function resolveMemoSignatories(client, document) {
  if (String(document?.document_type || '') !== 'memo') return null;
  try {
    const { resolveDepartmentReviewers } = require('./departmentReviewerService');
    const { resolveActiveMayor } = require('./officialSignatoryService');
    const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
    const date = todayInHrmsTimezone();

    const hr = await client.query(
      `SELECT id
       FROM departments
       WHERE (is_active IS NULL OR is_active = true)
         AND (
           name ILIKE '%human resource%'
           OR name ILIKE '%hr office%'
           OR name ILIKE '%hrmo%'
           OR name ILIKE 'hr'
         )
       ORDER BY CASE WHEN name ILIKE 'hr office' THEN 0 ELSE 1 END, name
       LIMIT 1`
    );
    let preparedBy = null;
    if (hr.rows[0]?.id) {
      const resolved = await resolveDepartmentReviewers(client, {
        departmentId: hr.rows[0].id,
        effectiveDate: date,
      });
      const headId = resolved.primary?.reviewerId;
      if (headId) preparedBy = await memoSignerIdentity(client, headId);
    }

    const officeUser = await client.query(
      `SELECT id
       FROM users
       WHERE is_active = true
         AND (
           LOWER(COALESCE(role, '')) = 'mayor_office_staff'
           OR (
             LOWER(COALESCE(role, '')) = 'mayor'
             AND full_name ILIKE '%office%'
           )
         )
       ORDER BY CASE
                  WHEN LOWER(COALESCE(role, '')) = 'mayor_office_staff' THEN 0
                  ELSE 1
                END,
                full_name
       LIMIT 1`
    );
    const notedBy = officeUser.rows[0]?.id
      ? await memoSignerIdentity(client, officeUser.rows[0].id, "Mayor's Office")
      : null;

    const mayor = await resolveActiveMayor(client, date);
    const mayorId = mayor?.employee_id ? String(mayor.employee_id) : null;
    const approvedBy =
      mayorId && (!notedBy || mayorId !== String(notedBy.id))
        ? await memoSignerIdentity(
            client,
            mayorId,
            mayor.position_title || 'Municipal Mayor'
          )
        : null;

    return { prepared_by: preparedBy, noted_by: notedBy, approved_by: approvedBy };
  } catch (err) {
    console.error('[docutracker] memo signatories', err);
    return null;
  }
}

async function serializeBuilder(client, document, user) {
  // Reading the builder must not insert, reassign, or move signature rows.
  // Official slots are stored only when an editable draft is explicitly saved.
  const memoSignatories = await resolveMemoSignatories(client, document);
  const contentResult = await client.query(
    `SELECT format_version, pages, revision
     FROM docutracker_document_contents
     WHERE document_id = $1`,
    [document.id]
  );
  // assigned_signer_* is the live identity shown before signing; once signed,
  // clients print the signer_*_snapshot columns frozen by signLockedField.
  const fieldsResult = await client.query(
    `SELECT f.*,
            assigned.full_name AS assigned_signer_name,
            ${signerIdentitySelectSql('assigned', 'assigned_signer')},
            encode(asset.image_bytes, 'base64') AS signature_image_base64
     FROM docutracker_signature_fields f
     JOIN users assigned ON assigned.id = f.assigned_signer_id
     ${signerIdentityJoinSql('assigned')}
     LEFT JOIN docutracker_signature_assets asset ON asset.id = f.signature_asset_id
     WHERE f.document_id = $1
     ORDER BY f.page_number, f.created_at, f.id`,
    [document.id]
  );
  const canEditLayout = await canEditBuilder(client, document, user);
  const canAddOwnSignature =
    !canEditLayout &&
    (await canAddOwnSignatureToDocument(client, { document, user }));
  const signatureFields = fieldsResult.rows.map((field) => ({
    ...field,
    can_sign: String(field.assigned_signer_id) === String(user.id),
  }));
  return {
    document_id: document.id,
    current_user_id: user.id,
    format_version: Number(
      contentResult.rows[0]?.format_version ?? DEFAULT_FORMAT_VERSION
    ),
    pages: contentResult.rows[0]?.pages || [[{ insert: '\n' }]],
    revision: Number(contentResult.rows[0]?.revision || 0),
    signature_fields: signatureFields,
    can_edit_layout: canEditLayout,
    can_add_own_signature: canAddOwnSignature,
    can_sign: signatureFields.some((field) => field.can_sign),
    memo_signatories: memoSignatories,
  };
}

async function getDocumentBuilder(pool, user, documentId) {
  const document = await getDocumentForUpdate(pool, documentId);
  if (!(await canReadBuilder(pool, document, user))) {
    throw forbiddenError('You do not have access to this document');
  }
  return serializeBuilder(pool, document, user);
}

async function saveDocumentBuilder(pool, user, documentId, input) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const document = await getDocumentForUpdate(client, documentId, true);
    const lockMessage = nativeDocumentContentLockMessage(document);
    if (lockMessage) {
      throw forbiddenError(lockMessage);
    }
    if (!(await canEditBuilder(client, document, user))) {
      throw forbiddenError('You do not have permission to edit this document layout');
    }

    const pages = normalizePages(input.pages);
    const fields = Array.isArray(input.signature_fields)
      ? input.signature_fields.map((field) => normalizeField(field, pages.length))
      : [];
    const signerIds = [...new Set(fields.map((field) => field.assignedSignerId))];
    if (signerIds.length) {
      const signers = await client.query(
        `SELECT id::text AS id FROM users
         WHERE id = ANY($1::uuid[]) AND is_active = true`,
        [signerIds]
      );
      const activeIds = new Set(signers.rows.map((row) => row.id));
      const invalid = signerIds.find((id) => !activeIds.has(id));
      if (invalid) throw validationError('Every signature field must use an active system user');
    }

    const currentContent = await client.query(
      `SELECT revision FROM docutracker_document_contents
       WHERE document_id = $1 FOR UPDATE`,
      [documentId]
    );
    const currentRevision = Number(currentContent.rows[0]?.revision || 0);
    const expectedRevision = Number(input.revision || 0);
    if (expectedRevision !== currentRevision) {
      throw conflictError('This document was updated elsewhere. Reload it before saving again.');
    }
    const nextRevision = currentRevision + 1;
    await client.query(
      `INSERT INTO docutracker_document_contents
         (document_id, format_version, pages, revision, updated_by)
       VALUES ($1, $2, $3::jsonb, $4, $5)
       ON CONFLICT (document_id) DO UPDATE SET
         pages = EXCLUDED.pages,
         revision = EXCLUDED.revision,
         updated_by = EXCLUDED.updated_by,
         updated_at = now()`,
      [
        documentId,
        DEFAULT_FORMAT_VERSION,
        JSON.stringify(pages),
        nextRevision,
        user.id,
      ]
    );

    const existingResult = await client.query(
      `SELECT * FROM docutracker_signature_fields
       WHERE document_id = $1 FOR UPDATE`,
      [documentId]
    );
    const existingById = new Map(existingResult.rows.map((field) => [String(field.id), field]));
    const incomingIds = new Set(fields.map((field) => field.id));

    for (const existing of existingResult.rows) {
      if (existing.locked_at && !incomingIds.has(String(existing.id))) {
        throw validationError('Signed signature fields cannot be removed');
      }
    }

    for (const field of fields) {
      const existing = existingById.get(field.id);
      if (existing?.locked_at) {
        const unchanged =
          Number(existing.page_number) === field.pageNumber &&
          Number(existing.position_x) === field.x &&
          Number(existing.position_y) === field.y &&
          Number(existing.width) === field.width &&
          Number(existing.height) === field.height &&
          String(existing.assigned_signer_id) === field.assignedSignerId &&
          String(existing.label) === field.label;
        if (!unchanged) throw validationError('Signed signature fields are locked');
        continue;
      }
      await client.query(
        `INSERT INTO docutracker_signature_fields
           (id, document_id, page_number, position_x, position_y, width, height,
            assigned_signer_id, label, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (id) DO UPDATE SET
           page_number = EXCLUDED.page_number,
           position_x = EXCLUDED.position_x,
           position_y = EXCLUDED.position_y,
           width = EXCLUDED.width,
           height = EXCLUDED.height,
           assigned_signer_id = EXCLUDED.assigned_signer_id,
           label = EXCLUDED.label,
           updated_at = now()
         WHERE docutracker_signature_fields.document_id = EXCLUDED.document_id
           AND docutracker_signature_fields.locked_at IS NULL`,
        [
          field.id,
          documentId,
          field.pageNumber,
          field.x,
          field.y,
          field.width,
          field.height,
          field.assignedSignerId,
          field.label,
          user.id,
        ]
      );
    }

    const editableIds = existingResult.rows
      .filter((field) => !field.locked_at && !incomingIds.has(String(field.id)))
      .map((field) => field.id);
    if (editableIds.length) {
      await client.query(
        `DELETE FROM docutracker_signature_fields
         WHERE document_id = $1 AND id = ANY($2::uuid[]) AND locked_at IS NULL`,
        [documentId, editableIds]
      );
    }

    await client.query(
      `UPDATE docutracker_documents SET updated_at = now() WHERE id = $1`,
      [documentId]
    );
    await client.query('COMMIT');
    return getDocumentBuilder(pool, user, documentId);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function createSignatureAsset(pool, user, input) {
  const mimeType = String(input.mime_type || '').trim().toLowerCase();
  const sourceType = String(input.source_type || '').trim().toLowerCase();
  if (sourceType !== 'drawn' && sourceType !== 'uploaded') {
    throw validationError('Signature source must be drawn or uploaded');
  }
  const imageBytes = decodeSignatureImage(input.image_base64, mimeType);
  const displayName = String(input.display_name || '').trim().slice(0, 120) || null;
  const result = await pool.query(
    `INSERT INTO docutracker_signature_assets
       (owner_user_id, image_bytes, mime_type, source_type, display_name, is_saved)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, owner_user_id, mime_type, source_type, display_name, is_saved,
               created_at, encode(image_bytes, 'base64') AS image_base64`,
    [user.id, imageBytes, mimeType, sourceType, displayName, input.is_saved === true]
  );
  return result.rows[0];
}

async function listSavedSignatureAssets(pool, user) {
  const result = await pool.query(
    `SELECT id, owner_user_id, mime_type, source_type, display_name, is_saved,
            created_at, encode(image_bytes, 'base64') AS image_base64
     FROM docutracker_signature_assets
     WHERE owner_user_id = $1 AND is_saved = true
     ORDER BY created_at DESC`,
    [user.id]
  );
  return result.rows;
}

async function renameSavedSignatureAsset(pool, user, assetId, displayName) {
  if (!isUuid(assetId)) throw notFoundError('Saved signature not found');
  const normalizedName = String(displayName || '').trim();
  if (!normalizedName || normalizedName.length > 120) {
    throw validationError('Signature name must contain 1 to 120 characters');
  }
  const result = await pool.query(
    `UPDATE docutracker_signature_assets
     SET display_name = $3
     WHERE id = $1::uuid
       AND owner_user_id = $2::uuid
       AND is_saved = true
     RETURNING id, owner_user_id, mime_type, source_type, display_name, is_saved,
               created_at, encode(image_bytes, 'base64') AS image_base64`,
    [assetId, user.id, normalizedName]
  );
  if (!result.rowCount) throw notFoundError('Saved signature not found');
  return result.rows[0];
}

async function removeSavedSignatureAsset(pool, user, assetId) {
  if (!isUuid(assetId)) throw notFoundError('Saved signature not found');
  const result = await pool.query(
    `UPDATE docutracker_signature_assets
     SET is_saved = false
     WHERE id = $1::uuid
       AND owner_user_id = $2::uuid
       AND is_saved = true
     RETURNING id`,
    [assetId, user.id]
  );
  if (!result.rowCount) throw notFoundError('Saved signature not found');
}

async function signDocumentField(pool, user, documentId, fieldId, input) {
  if (!isUuid(fieldId)) throw notFoundError('Signature field not found');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const document = await getDocumentForUpdate(client, documentId, true);
    if (!(await canReadBuilder(client, document, user))) {
      throw forbiddenError('You do not have access to this document');
    }
    const fieldResult = await client.query(
      `SELECT * FROM docutracker_signature_fields
       WHERE id = $1 AND document_id = $2 FOR UPDATE`,
      [fieldId, documentId]
    );
    const field = fieldResult.rows[0];
    if (!field) throw notFoundError('Signature field not found');
    if (String(field.assigned_signer_id) !== String(user.id)) {
      throw forbiddenError('Only the assigned signer can sign this field');
    }
    await signLockedField(client, user, documentId, field, input);
    await client.query('COMMIT');
    return getDocumentBuilder(pool, user, documentId);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function signLockedField(client, user, documentId, field, input, options = {}) {
  const allowReplacement = options.allowReplacement !== false;
  const alreadySigned = Boolean(
    field.signature_asset_id || field.signed_at || field.locked_at
  );
  if (!allowReplacement && alreadySigned) {
    throw conflictError('This signature field is already signed');
  }
  const isReplacement = alreadySigned;

  let assetId = String(input.signature_asset_id || '').trim();
  if (assetId) {
    if (!isUuid(assetId)) throw validationError('Saved signature is invalid');
    const ownedAsset = await client.query(
      `SELECT id FROM docutracker_signature_assets
       WHERE id = $1 AND owner_user_id = $2`,
      [assetId, user.id]
    );
    if (!ownedAsset.rowCount) throw forbiddenError('Saved signature not found');
  } else {
    const asset = await createSignatureAsset(client, user, input);
    assetId = asset.id;
  }

  const userResult = await client.query(
    `SELECT signer.full_name,
            ${signerIdentitySelectSql('signer', 'signer')}
     FROM users signer
     ${signerIdentityJoinSql('signer')}
     WHERE signer.id = $1 AND signer.is_active = true`,
    [user.id]
  );
  if (!userResult.rowCount) throw forbiddenError('Only an active user can sign');
  const signerName = userResult.rows[0].full_name;
  const signerPosition = String(userResult.rows[0].signer_position || '').trim() || null;
  const signerRole = String(userResult.rows[0].signer_role || '').trim() || null;
  const replacementGuard = allowReplacement
    ? ''
    : ' AND signed_at IS NULL AND signature_asset_id IS NULL AND locked_at IS NULL';
  const signed = await client.query(
    `UPDATE docutracker_signature_fields SET
       signature_asset_id = $1,
       signed_by = $2,
       signer_name_snapshot = $3,
       signer_position_snapshot = $6,
       signer_role_snapshot = $7,
       signed_at = now(),
       locked_at = now(),
       updated_at = now()
     WHERE id = $4 AND document_id = $5 AND assigned_signer_id = $2${replacementGuard}
     RETURNING *`,
    [assetId, user.id, signerName, field.id, documentId, signerPosition, signerRole]
  );
  if (!signed.rowCount) throw conflictError('This signature field changed while it was being signed');

  await client.query(
    `INSERT INTO docutracker_document_history
       (document_id, action, actor_id, actor_name, remarks)
     VALUES ($1, 'signed', $2, $3, $4)`,
    [
      documentId,
      user.id,
      signerName,
      `${isReplacement ? 'Replaced signature' : 'Signed'} field: ${field.label}`,
    ]
  );
}

/**
 * Lets the reviewer assigned to the document's active workflow step place and
 * sign a field for themselves after submission, when content editing is locked.
 */
async function addOwnSignatureField(pool, user, documentId, input) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const document = await getDocumentForUpdate(client, documentId, true);
    if (!(await canAddOwnSignatureToDocument(client, { document, user }))) {
      throw forbiddenError(
        'Only a reviewer assigned to the current workflow step can add their signature'
      );
    }
    const contentResult = await client.query(
      `SELECT pages FROM docutracker_document_contents WHERE document_id = $1`,
      [documentId]
    );
    const pages = contentResult.rows[0]?.pages;
    const pageCount = Array.isArray(pages) && pages.length ? pages.length : 1;
    const field = normalizeField(
      {
        ...input,
        id: null,
        assigned_signer_id: user.id,
        label: input.label || 'Signature',
      },
      pageCount
    );
    const inserted = await client.query(
      `INSERT INTO docutracker_signature_fields
         (id, document_id, page_number, position_x, position_y, width, height,
          assigned_signer_id, label, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8)
       RETURNING *`,
      [
        field.id,
        documentId,
        field.pageNumber,
        field.x,
        field.y,
        field.width,
        field.height,
        user.id,
        field.label,
      ]
    );
    await signLockedField(client, user, documentId, inserted.rows[0], input);
    await client.query(
      `UPDATE docutracker_documents SET updated_at = now() WHERE id = $1`,
      [documentId]
    );
    await client.query('COMMIT');
    return getDocumentBuilder(pool, user, documentId);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Keep in step with DocuTrackerMemoLayout.reviewerSignature. This is the open
// band below Prepared by, Noted by, Approved by, and Cc, and above the footer.
const MEMO_REVIEWER_SIGNATURE = Object.freeze({
  pageNumber: 1,
  x: 0.56,
  y: 0.802,
  width: 0.28,
  height: 0.044,
});

// Keep in step with DocuTrackerMemoLayout official slots.
const PURCHASE_REQUESTED = Object.freeze({
  label: 'Requested by',
  pageNumber: 1,
  x: 0.11,
  y: 0.69,
  width: 0.34,
  height: 0.085,
});
const PURCHASE_APPROVED = Object.freeze({
  label: 'Approved by',
  pageNumber: 1,
  x: 0.54,
  y: 0.69,
  width: 0.34,
  height: 0.085,
});

const MEMO_OFFICIAL_SLOTS = Object.freeze([
  Object.freeze({
    key: 'prepared_by',
    label: 'Prepared by',
    pageNumber: 1,
    x: 0.13,
    y: 0.523,
    width: 0.3,
    height: 0.085,
  }),
  Object.freeze({
    key: 'noted_by',
    label: 'Noted by',
    pageNumber: 1,
    x: 0.56,
    y: 0.523,
    width: 0.32,
    height: 0.085,
  }),
  Object.freeze({
    key: 'approved_by',
    label: 'Approved by',
    pageNumber: 1,
    x: 0.5,
    y: 0.628,
    width: 0.38,
    height: 0.085,
  }),
]);

function preferredAssignedField(rows) {
  const rank = (label) => {
    const index = MEMO_OFFICIAL_SLOTS.findIndex((slot) => slot.label === label);
    return index < 0 ? MEMO_OFFICIAL_SLOTS.length : index;
  };
  return [...rows].sort((a, b) => rank(a.label) - rank(b.label))[0];
}

function rectanglesOverlap(a, b) {
  const ax = Number(a.x);
  const ay = Number(a.y);
  const aw = Number(a.width);
  const ah = Number(a.height);
  const bx = Number(b.x);
  const by = Number(b.y);
  const bw = Number(b.width);
  const bh = Number(b.height);
  return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}

async function emptyPurchaseRequestSlot(client, document) {
  if (String(document?.document_type || '') !== 'purchaseRequest') return null;
  const step = Number(document.current_step || 1);
  const config = await client.query(
    `SELECT steps
     FROM docutracker_routing_config_versions
     WHERE document_type = $1
     ORDER BY version DESC
     LIMIT 1`,
    [document.document_type]
  );
  const rawSteps = config.rows[0]?.steps;
  const steps = Array.isArray(rawSteps) ? rawSteps : [];
  const orders = steps
    .filter((item) => item && item.enabled !== false && item.is_enabled !== false)
    .map((item) => Number(item.step_order ?? item.stepOrder))
    .filter((order) => Number.isFinite(order));
  const last = orders.length ? Math.max(...orders) : step;
  const slots = step >= last
    ? [PURCHASE_APPROVED, PURCHASE_REQUESTED]
    : [PURCHASE_REQUESTED, PURCHASE_APPROVED];
  for (const slot of slots) {
    const existing = await client.query(
      `SELECT id
       FROM docutracker_signature_fields
       WHERE document_id = $1
         AND page_number = 1
         AND label = $2
       LIMIT 1`,
      [document.id, slot.label]
    );
    if (existing.rowCount === 0) return slot;
  }
  return null;
}

async function missingOfficialMemoSlot(client, document, userId) {
  if (String(document?.document_type || '') !== 'memo') return null;
  const signatories = await resolveMemoSignatories(client, document);
  if (!signatories) return null;
  const slot = MEMO_OFFICIAL_SLOTS.find((item) => {
    const person = signatories[item.key];
    return person && String(person.id) === String(userId);
  });
  if (!slot) return null;
  const existing = await client.query(
    `SELECT id FROM docutracker_signature_fields
     WHERE document_id = $1
       AND page_number = 1
       AND label = $2
     LIMIT 1`,
    [document.id, slot.label]
  );
  if (existing.rowCount > 0) return null;
  return slot;
}

async function insertAndSignField(client, user, documentId, input, placement) {
  const contentResult = await client.query(
    `SELECT pages FROM docutracker_document_contents WHERE document_id = $1`,
    [documentId]
  );
  const pages = contentResult.rows[0]?.pages;
  const pageCount = Array.isArray(pages) && pages.length ? pages.length : 1;
  const field = normalizeField(
    {
      id: null,
      page_number: placement.pageNumber,
      position_x: placement.x,
      position_y: placement.y,
      width: placement.width,
      height: placement.height,
      assigned_signer_id: user.id,
      label: placement.label,
    },
    pageCount
  );
  const inserted = await client.query(
    `INSERT INTO docutracker_signature_fields
       (id, document_id, page_number, position_x, position_y, width, height,
        assigned_signer_id, label, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8)
     RETURNING *`,
    [
      field.id,
      documentId,
      field.pageNumber,
      field.x,
      field.y,
      field.width,
      field.height,
      user.id,
      field.label,
    ]
  );
  await signLockedField(client, user, documentId, inserted.rows[0], input, {
    allowReplacement: false,
  });
}

/**
 * Writes the reviewer's signature inside an open workflow transaction.
 * The caller commits or rolls this back with the workflow step.
 * An existing signature is left unchanged.
 *
 * Ink from Approve or Forward is written onto the signer's own Memorandum
 * line when they already have one, or onto that official line when they are
 * the resolved signatory and the row has not been saved yet.
 */
async function applyTransitionSignature(client, user, document, input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw validationError('A signature is required before this step can continue');
  }
  const documentId = document.id;
  if (await hasUserSignedDocument(client, { documentId, userId: user.id })) {
    return { applied: false };
  }

  const fieldId = String(input.field_id || '').trim();
  if (fieldId) {
    if (!isUuid(fieldId)) throw notFoundError('Signature field not found');
    const fieldResult = await client.query(
      `SELECT * FROM docutracker_signature_fields
       WHERE id = $1 AND document_id = $2
       FOR UPDATE`,
      [fieldId, documentId]
    );
    const field = fieldResult.rows[0];
    if (!field) throw notFoundError('Signature field not found');
    if (String(field.assigned_signer_id) !== String(user.id)) {
      throw forbiddenError('Only the assigned signer can sign this field');
    }
    if (field.signature_asset_id || field.signed_at || field.locked_at) {
      if (String(field.signed_by) === String(user.id)) return { applied: false };
      throw conflictError('This signature field is already signed');
    }
    await signLockedField(client, user, documentId, field, input, {
      allowReplacement: false,
    });
    return { applied: true };
  }

  const pendingMine = await client.query(
    `SELECT id, label FROM docutracker_signature_fields
     WHERE document_id = $1
       AND assigned_signer_id = $2
       AND signed_at IS NULL
       AND signature_asset_id IS NULL
       AND locked_at IS NULL
     FOR UPDATE`,
    [documentId, user.id]
  );
  if (pendingMine.rowCount > 0) {
    const chosen = preferredAssignedField(pendingMine.rows);
    const locked = await client.query(
      `SELECT * FROM docutracker_signature_fields
       WHERE id = $1 AND document_id = $2
       FOR UPDATE`,
      [chosen.id, documentId]
    );
    const field = locked.rows[0];
    if (!field || String(field.assigned_signer_id) !== String(user.id)) {
      throw validationError('Sign the signature field assigned to you');
    }
    if (field.signature_asset_id || field.signed_at || field.locked_at) {
      return { applied: false };
    }
    await signLockedField(client, user, documentId, field, input, {
      allowReplacement: false,
    });
    return { applied: true };
  }
  const officialSlot = await missingOfficialMemoSlot(client, document, user.id);
  if (officialSlot) {
    await insertAndSignField(client, user, documentId, input, {
      pageNumber: officialSlot.pageNumber,
      x: officialSlot.x,
      y: officialSlot.y,
      width: officialSlot.width,
      height: officialSlot.height,
      label: officialSlot.label,
    });
    return { applied: true };
  }
  if (!(await canAddOwnSignatureToDocument(client, { document, user }))) {
    throw forbiddenError(
      'Only a reviewer assigned to the current workflow step can add their signature'
    );
  }
  const purchaseSlot = await emptyPurchaseRequestSlot(client, document);
  if (purchaseSlot) {
    await insertAndSignField(client, user, documentId, input, {
      pageNumber: purchaseSlot.pageNumber,
      x: purchaseSlot.x,
      y: purchaseSlot.y,
      width: purchaseSlot.width,
      height: purchaseSlot.height,
      label: purchaseSlot.label,
    });
    return { applied: true };
  }

  const contentResult = await client.query(
    `SELECT pages FROM docutracker_document_contents WHERE document_id = $1`,
    [documentId]
  );
  const pages = contentResult.rows[0]?.pages;
  const pageCount = Array.isArray(pages) && pages.length ? pages.length : 1;
  let placement = input;
  if (String(document.document_type || '') === 'memo') {
    const occupied = await client.query(
      `SELECT position_x, position_y, width, height
       FROM docutracker_signature_fields
       WHERE document_id = $1
       FOR UPDATE`,
      [documentId]
    );
    const spotTaken = occupied.rows.some((row) => rectanglesOverlap(
      MEMO_REVIEWER_SIGNATURE,
      {
        x: row.position_x,
        y: row.position_y,
        width: row.width,
        height: row.height,
      }
    ));
    if (spotTaken) {
      throw validationError(
        'There is no open space left for a reviewer signature on this Memorandum.'
      );
    }
    placement = {
      ...input,
      page_number: MEMO_REVIEWER_SIGNATURE.pageNumber,
      position_x: MEMO_REVIEWER_SIGNATURE.x,
      position_y: MEMO_REVIEWER_SIGNATURE.y,
      width: MEMO_REVIEWER_SIGNATURE.width,
      height: MEMO_REVIEWER_SIGNATURE.height,
    };
  }
  const field = normalizeField(
    {
      ...placement,
      id: null,
      assigned_signer_id: user.id,
      label: placement.label || 'Signature',
    },
    pageCount
  );
  const inserted = await client.query(
    `INSERT INTO docutracker_signature_fields
       (id, document_id, page_number, position_x, position_y, width, height,
        assigned_signer_id, label, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8)
     RETURNING *`,
    [
      field.id,
      documentId,
      field.pageNumber,
      field.x,
      field.y,
      field.width,
      field.height,
      user.id,
      field.label,
    ]
  );
  await signLockedField(client, user, documentId, inserted.rows[0], input, {
    allowReplacement: false,
  });
  return { applied: true };
}

async function moveSignedDocumentField(pool, user, documentId, fieldId, input) {
  if (!isUuid(fieldId)) throw notFoundError('Signature field not found');
  const x = numberInRange(input.position_x, 0, 1, 'Horizontal position');
  const y = numberInRange(input.position_y, 0, 1, 'Vertical position');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const document = await getDocumentForUpdate(client, documentId, true);
    if (!(await canReadBuilder(client, document, user))) {
      throw forbiddenError('You do not have access to this document');
    }
    const fieldResult = await client.query(
      `SELECT * FROM docutracker_signature_fields
       WHERE id = $1 AND document_id = $2 FOR UPDATE`,
      [fieldId, documentId]
    );
    const field = fieldResult.rows[0];
    if (!field) throw notFoundError('Signature field not found');
    if (String(field.assigned_signer_id) !== String(user.id)) {
      throw forbiddenError('Only the assigned signer can move this signature');
    }
    if (!field.signature_asset_id || !field.signed_at || !field.locked_at) {
      throw conflictError('Only a signed signature field can be moved this way');
    }
    if (x + Number(field.width) > 1.000001 || y + Number(field.height) > 1.000001) {
      throw validationError('The signature field must remain inside its A4 page');
    }

    const moved = await client.query(
      `UPDATE docutracker_signature_fields SET
         position_x = $1,
         position_y = $2,
         updated_at = now()
       WHERE id = $3 AND document_id = $4 AND assigned_signer_id = $5
       RETURNING *`,
      [x, y, fieldId, documentId, user.id]
    );
    if (!moved.rowCount) {
      throw conflictError('This signature field changed while it was being moved');
    }

    const userResult = await client.query(
      `SELECT full_name FROM users WHERE id = $1 AND is_active = true`,
      [user.id]
    );
    if (!userResult.rowCount) throw forbiddenError('Only an active user can move a signature');
    const signerName = userResult.rows[0].full_name;
    await client.query(
      `INSERT INTO docutracker_document_history
         (document_id, action, actor_id, actor_name, remarks)
       VALUES ($1, 'metadata_updated', $2, $3, $4)`,
      [documentId, user.id, signerName, `Moved signed field: ${field.label}`]
    );
    await client.query('COMMIT');
    return getDocumentBuilder(pool, user, documentId);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  getDocumentBuilder,
  saveDocumentBuilder,
  createSignatureAsset,
  listSavedSignatureAssets,
  renameSavedSignatureAsset,
  removeSavedSignatureAsset,
  signDocumentField,
  addOwnSignatureField,
  applyTransitionSignature,
  moveSignedDocumentField,
};
