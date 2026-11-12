/**
 * Per-document Printed Form snapshot helpers.
 *
 * print_form_selection:
 * - official: built-in Memo/PR / editor page; ignore type template pointer
 * - custom: frozen print_template_version_id
 * - unset: legacy pre-snapshot row (compatibility only; not claimed original)
 */

const BUILTIN_OFFICIAL_TYPES = new Set(['memo', 'purchaseRequest']);

function normalizeSelection(raw) {
  const value = String(raw || '').trim().toLowerCase();
  if (value === 'official' || value === 'custom' || value === 'unset') {
    return value;
  }
  return 'unset';
}

function isBuiltinOfficialType(documentType) {
  return BUILTIN_OFFICIAL_TYPES.has(String(documentType || '').trim());
}

/**
 * Read the type's current default as a create-time snapshot payload.
 */
async function snapshotFromTypeDefault(db, documentType) {
  const key = String(documentType || '').trim();
  const q = await db.query(
    `SELECT dt.print_template_version_id AS version_id, v.print_layout
     FROM docutracker_document_types dt
     LEFT JOIN docutracker_print_template_versions v
       ON v.id = dt.print_template_version_id
     WHERE dt.document_type = $1`,
    [key],
  );
  const row = q.rows[0];
  const layout = row?.print_layout;
  if (
    row?.version_id &&
    layout &&
    typeof layout === 'object' &&
    !Array.isArray(layout)
  ) {
    return {
      print_form_selection: 'custom',
      print_template_version_id: row.version_id,
    };
  }
  return {
    print_form_selection: 'official',
    print_template_version_id: null,
  };
}

/**
 * Which template version id (if any) a document should use for print/fill.
 * Never follows the live type pointer for official or custom snapshots.
 */
function resolvedPrintVersionId(documentRow, typeVersionId) {
  const selection = normalizeSelection(documentRow?.print_form_selection);
  if (selection === 'custom') {
    return documentRow.print_template_version_id || null;
  }
  if (selection === 'official') {
    return null;
  }
  // Legacy unset
  if (isBuiltinOfficialType(documentRow?.document_type)) {
    return null;
  }
  return typeVersionId || null;
}

/** Local twin of workflow isDraftOrWipDocument (avoid circular requires). */
function isDraftOrWipPrintDocument(document) {
  if (!document) return false;
  const status = String(document.status || '')
    .trim()
    .toLowerCase();
  if (status === 'draft') return true;
  return (
    status === 'pending' &&
    !document.current_holder_id &&
    (document.current_step == null || Number(document.current_step) <= 0) &&
    !document.sent_time
  );
}

/**
 * Draft/WIP rows created before a Memo/PR custom layout existed stay
 * official/unset and would keep showing the built-in sheet. When the type now
 * has a custom layout, stamp that version onto the draft so fill/print match
 * the designed form. Submitted/history docs are left frozen.
 *
 * @returns {Promise<boolean>} true when the document row was updated
 */
async function adoptTypePrintSnapshotForDraft(db, documentRow) {
  if (!documentRow?.id || !isDraftOrWipPrintDocument(documentRow)) {
    return false;
  }
  const selection = normalizeSelection(documentRow.print_form_selection);
  const alreadyCustom =
    selection === 'custom' && documentRow.print_template_version_id;
  if (alreadyCustom) return false;
  // Only upgrade unset legacy rows or official stamps with no frozen version.
  if (selection !== 'unset' && selection !== 'official') return false;
  if (selection === 'official' && documentRow.print_template_version_id) {
    return false;
  }

  const next = await snapshotFromTypeDefault(db, documentRow.document_type);
  if (next.print_form_selection !== 'custom' || !next.print_template_version_id) {
    return false;
  }

  await db.query(
    `UPDATE docutracker_documents
     SET print_form_selection = $2,
         print_template_version_id = $3::uuid,
         updated_at = now()
     WHERE id = $1::uuid
       AND status = 'pending'
       AND current_holder_id IS NULL
       AND (current_step IS NULL OR current_step <= 0)
       AND sent_time IS NULL
       AND COALESCE(print_form_selection, 'unset') IN ('unset', 'official')
       AND print_template_version_id IS NULL`,
    [documentRow.id, next.print_form_selection, next.print_template_version_id],
  );
  documentRow.print_form_selection = next.print_form_selection;
  documentRow.print_template_version_id = next.print_template_version_id;
  return true;
}

function printSnapshotMeta(documentRow) {
  const selection = normalizeSelection(documentRow?.print_form_selection);
  return {
    print_form_selection: selection,
    print_snapshot_legacy: selection === 'unset',
  };
}

module.exports = {
  BUILTIN_OFFICIAL_TYPES,
  isBuiltinOfficialType,
  normalizeSelection,
  snapshotFromTypeDefault,
  resolvedPrintVersionId,
  isDraftOrWipPrintDocument,
  adoptTypePrintSnapshotForDraft,
  printSnapshotMeta,
};
