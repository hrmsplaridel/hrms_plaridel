/**
 * Content-edit history for Selection Line-Up.
 * Uses the existing governance audit table. A signature is never cleared here.
 */

const SELECTION_LINEUP_TABLE = 'selection_lineup_entries';
const EDIT_EVENT = 'selection_lineup_content_edited';
const EDIT_ENTITY = 'selection_lineup_entry';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const CONTENT_FIELDS = Object.freeze([
  'date',
  'name_of_agency_office',
  'vacant_position',
  'item_no',
  'applicants',
  'prepared_by_name',
  'prepared_by_title',
]);

const FIELD_LABELS = Object.freeze({
  date: 'Date',
  name_of_agency_office: 'Agency / office',
  vacant_position: 'Vacant position',
  item_no: 'Item no.',
  applicants: 'Applicants',
  prepared_by_name: 'Prepared by name',
  prepared_by_title: 'Prepared by title',
});

const SIGNED_EDIT_NOTE =
  'The form content was changed after Prepared By signed. The existing signature image, signer, and signed time were kept. That signature does not cryptographically approve the revised content.';

function canonical(value) {
  if (value == null) return null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        return canonical(JSON.parse(trimmed));
      } catch (_) {
        return trimmed;
      }
    }
    return trimmed;
  }
  if (Array.isArray(value)) return value.map((item) => canonical(item));
  if (typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== undefined) out[key] = canonical(value[key]);
    }
    return out;
  }
  return value;
}

function sameValue(left, right) {
  return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}

function diffSelectionLineup(beforeRow, payload) {
  const previous = {};
  const next = {};
  const changes = [];
  for (const field of CONTENT_FIELDS) {
    if (!Object.prototype.hasOwnProperty.call(payload || {}, field)) continue;
    if (sameValue(beforeRow?.[field], payload[field])) continue;
    previous[field] = canonical(beforeRow?.[field]);
    next[field] = canonical(payload[field]);
    changes.push({
      field,
      label: FIELD_LABELS[field] || field,
      previous: previous[field],
      next: next[field],
    });
  }
  if (!changes.length) return null;
  return { previous, next, changes };
}

function signatureStateFromSlot(row) {
  if (!row || !row.assigned_signer_id) {
    return {
      signed: false,
      signature_status: 'needs_setup',
      signed_at: null,
      signer_name_snapshot: null,
    };
  }
  const signed = Boolean(row.signature_asset_id && row.signed_at);
  return {
    signed,
    signature_status: signed ? 'completed' : 'awaiting_signatures',
    signed_at: row.signed_at || null,
    signer_name_snapshot: row.signer_name_snapshot || null,
  };
}

function resolveLineupCreatorId(actorId) {
  const id = String(actorId || '').trim();
  if (!UUID_RE.test(id)) {
    const error = new Error('An authenticated creator is required to open a Selection Line-Up.');
    error.code = 'CREATOR_REQUIRED';
    error.status = 400;
    throw error;
  }
  return id;
}

function buildContentEditAudit({ recordId, actorId, actorName, diff, signature }) {
  const signed = signature?.signed === true;
  return {
    actorId,
    eventType: EDIT_EVENT,
    entityType: EDIT_ENTITY,
    entityId: String(recordId),
    documentType: 'rsp',
    beforeState: { values: diff.previous },
    afterState: {
      values: diff.next,
      changes: diff.changes,
      actor_name: actorName || null,
      signed_when_edited: signed,
      signature_status: signature?.signature_status || 'needs_setup',
      signature_signed_at: signature?.signed_at || null,
      signer_name_snapshot: signature?.signer_name_snapshot || null,
      integrity_note: signed ? SIGNED_EDIT_NOTE : null,
    },
    reason: signed
      ? SIGNED_EDIT_NOTE
      : 'Selection Line-Up content was updated before signing.',
  };
}

function serializeEditHistoryRow(row) {
  const after = row.after_state || {};
  const changes = Array.isArray(after.changes) ? after.changes : [];
  return {
    id: row.id,
    edited_at: row.created_at,
    edited_by: row.actor_id,
    edited_by_name: after.actor_name || row.actor_name || null,
    signed_when_edited: after.signed_when_edited === true,
    signature_status: after.signature_status || null,
    integrity_note: after.integrity_note || null,
    changes,
  };
}

module.exports = {
  SELECTION_LINEUP_TABLE,
  EDIT_EVENT,
  EDIT_ENTITY,
  CONTENT_FIELDS,
  SIGNED_EDIT_NOTE,
  canonical,
  diffSelectionLineup,
  signatureStateFromSlot,
  resolveLineupCreatorId,
  buildContentEditAudit,
  serializeEditHistoryRow,
};
