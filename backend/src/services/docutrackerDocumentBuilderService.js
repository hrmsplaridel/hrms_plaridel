const { v4: uuidv4 } = require('uuid');
const {
  canUserPerformDocumentAction,
} = require('./docutrackerWorkflowService');

const MAX_PAGES = 50;
const MAX_CONTENT_BYTES = 2 * 1024 * 1024;
const MAX_SIGNATURE_BYTES = 2 * 1024 * 1024;
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

async function serializeBuilder(client, document, user) {
  const contentResult = await client.query(
    `SELECT pages, revision
     FROM docutracker_document_contents
     WHERE document_id = $1`,
    [document.id]
  );
  const fieldsResult = await client.query(
    `SELECT f.*,
            assigned.full_name AS assigned_signer_name,
            encode(asset.image_bytes, 'base64') AS signature_image_base64
     FROM docutracker_signature_fields f
     JOIN users assigned ON assigned.id = f.assigned_signer_id
     LEFT JOIN docutracker_signature_assets asset ON asset.id = f.signature_asset_id
     WHERE f.document_id = $1
     ORDER BY f.page_number, f.created_at, f.id`,
    [document.id]
  );
  const canEditLayout = await canEditBuilder(client, document, user);
  const signatureFields = fieldsResult.rows.map((field) => ({
    ...field,
    can_sign: String(field.assigned_signer_id) === String(user.id),
  }));
  return {
    document_id: document.id,
    current_user_id: user.id,
    pages: contentResult.rows[0]?.pages || [[{ insert: '\n' }]],
    revision: Number(contentResult.rows[0]?.revision || 0),
    signature_fields: signatureFields,
    can_edit_layout: canEditLayout,
    can_sign: signatureFields.some((field) => field.can_sign),
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
         (document_id, pages, revision, updated_by)
       VALUES ($1, $2::jsonb, $3, $4)
       ON CONFLICT (document_id) DO UPDATE SET
         pages = EXCLUDED.pages,
         revision = EXCLUDED.revision,
         updated_by = EXCLUDED.updated_by,
         updated_at = now()`,
      [documentId, JSON.stringify(pages), nextRevision, user.id]
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
    const isReplacement = Boolean(
      field.signature_asset_id || field.signed_at || field.locked_at
    );

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
      `SELECT full_name FROM users WHERE id = $1 AND is_active = true`,
      [user.id]
    );
    if (!userResult.rowCount) throw forbiddenError('Only an active user can sign');
    const signerName = userResult.rows[0].full_name;
    const signed = await client.query(
      `UPDATE docutracker_signature_fields SET
         signature_asset_id = $1,
         signed_by = $2,
         signer_name_snapshot = $3,
         signed_at = now(),
         locked_at = now(),
         updated_at = now()
       WHERE id = $4 AND document_id = $5 AND assigned_signer_id = $2
       RETURNING *`,
      [assetId, user.id, signerName, fieldId, documentId]
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
    await client.query('COMMIT');
    return getDocumentBuilder(pool, user, documentId);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
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
  signDocumentField,
  moveSignedDocumentField,
};
