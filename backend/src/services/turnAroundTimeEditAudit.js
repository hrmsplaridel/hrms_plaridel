/**
 * Content revisions for Turn Around Time.
 * A material save clears active signatures and keeps the previous signing
 * evidence in the governance audit. Assignments stay on the same people.
 */

const TURN_AROUND_TIME_TABLE = 'turn_around_time_entries';
const EDIT_EVENT = 'turn_around_time_content_edited';
const EDIT_ENTITY = 'turn_around_time_entry';
const SLOT_ORDER = Object.freeze(['prepared_by', 'noted_by']);

const HEADER_FIELDS = Object.freeze([
  'position',
  'office',
  'no_of_vacant_position',
  'date_of_publication',
  'end_search',
  'qs',
  'prepared_by_name',
  'prepared_by_title',
  'noted_by_name',
  'noted_by_title',
]);

const APPLICANT_FIELDS = Object.freeze([
  'application_id',
  'name',
  'date_initial_assessment',
  'date_contract_exam',
  'skills_trade_exam_result',
  'date_deliberation',
  'date_job_offer',
  'acceptance_date',
  'date_assumption_to_duty',
  'no_of_days_to_fill_up',
  'overall_cost_per_hire',
]);

const FIELD_LABELS = Object.freeze({
  position: 'Position',
  office: 'Office',
  no_of_vacant_position: 'Number of vacant positions',
  date_of_publication: 'Publication date',
  end_search: 'End of search',
  qs: 'Qualifications',
  prepared_by_name: 'Prepared by name',
  prepared_by_title: 'Prepared by title',
  noted_by_name: 'Noted by name',
  noted_by_title: 'Noted by title',
  application_id: 'Linked application',
  name: 'Applicant name',
  date_initial_assessment: 'Initial assessment',
  date_contract_exam: 'Exam date',
  skills_trade_exam_result: 'Exam result',
  date_deliberation: 'Deliberation',
  date_job_offer: 'Job offer',
  acceptance_date: 'Acceptance date',
  date_assumption_to_duty: 'Assumption to duty',
  no_of_days_to_fill_up: 'Days to fill',
  overall_cost_per_hire: 'Cost per hire',
});

const RENEWAL_NOTE =
  'The form content changed after signing. The active signatures were cleared and must be signed again, Prepared By first. The names and times below are for the earlier revision, not this one.';

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

function textOrNull(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text || null;
}

function normalizeApplicant(raw) {
  const source = canonical(raw);
  const row = source && typeof source === 'object' && !Array.isArray(source) ? source : {};
  const out = {};
  for (const field of APPLICANT_FIELDS) out[field] = textOrNull(row[field]);
  return out;
}

function parseApplicants(value) {
  const parsed = canonical(value);
  if (!Array.isArray(parsed)) return [];
  return parsed.map((item) => normalizeApplicant(item));
}

function isBlank(applicant) {
  return APPLICANT_FIELDS.every((field) => applicant[field] == null);
}

function identityKey(applicant) {
  if (applicant.application_id) return `id:${applicant.application_id}`;
  return `name:${applicant.name || ''}`;
}

function milestoneFingerprint(applicant) {
  return APPLICANT_FIELDS.filter((field) => field !== 'name' && field !== 'application_id')
    .map((field) => applicant[field] || '')
    .join('\u0001');
}

function nameCounts(applicants) {
  const counts = new Map();
  for (const applicant of applicants) {
    const name = applicant.name || '';
    counts.set(name, (counts.get(name) || 0) + 1);
  }
  return counts;
}

function applicantLabel(applicant, index, applicants) {
  const name = applicant.name || 'Unnamed applicant';
  const counts = nameCounts(applicants);
  if ((counts.get(applicant.name || '') || 0) > 1) return `${name} (row ${index + 1})`;
  return name;
}

function snapshotApplicant(applicant) {
  const out = {};
  for (const field of APPLICANT_FIELDS) {
    if (applicant[field] != null) out[field] = applicant[field];
  }
  return out;
}

function matchApplicants(before, after) {
  const usedBefore = new Set();
  const usedAfter = new Set();
  const pairs = [];
  const beforeGroups = new Map();
  const afterGroups = new Map();
  const add = (groups, key, index) => {
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(index);
  };
  before.forEach((applicant, index) => add(beforeGroups, identityKey(applicant), index));
  after.forEach((applicant, index) => add(afterGroups, identityKey(applicant), index));
  for (const key of new Set([...beforeGroups.keys(), ...afterGroups.keys()])) {
    const beforeIndexes = beforeGroups.get(key) || [];
    const afterIndexes = afterGroups.get(key) || [];
    const count = Math.min(beforeIndexes.length, afterIndexes.length);
    for (let index = 0; index < count; index += 1) {
      pairs.push({ beforeIndex: beforeIndexes[index], afterIndex: afterIndexes[index] });
      usedBefore.add(beforeIndexes[index]);
      usedAfter.add(afterIndexes[index]);
    }
  }
  for (let index = 0; index < Math.min(before.length, after.length); index += 1) {
    if (usedBefore.has(index) || usedAfter.has(index)) continue;
    const previous = before[index];
    const next = after[index];
    if (isBlank(previous) || isBlank(next)) continue;
    const sameName = previous.name && previous.name === next.name;
    const sameMilestones = milestoneFingerprint(previous) === milestoneFingerprint(next);
    if (!sameName && !sameMilestones) continue;
    pairs.push({ beforeIndex: index, afterIndex: index });
    usedBefore.add(index);
    usedAfter.add(index);
  }
  return { pairs, usedBefore, usedAfter };
}

function diffApplicants(beforeValue, afterValue) {
  const before = parseApplicants(beforeValue);
  const after = parseApplicants(afterValue);
  const { pairs, usedBefore, usedAfter } = matchApplicants(before, after);
  const changes = [];
  for (const pair of pairs) {
    const previous = before[pair.beforeIndex];
    const next = after[pair.afterIndex];
    if (isBlank(previous) && isBlank(next)) continue;
    const labelSource = previous.name ? previous : next;
    const labelRows = previous.name ? before : after;
    const labelIndex = previous.name ? pair.beforeIndex : pair.afterIndex;
    for (const field of APPLICANT_FIELDS) {
      if (sameValue(previous[field], next[field])) continue;
      changes.push({
        field: `applicants.${field}`,
        label: FIELD_LABELS[field] || field,
        applicant: applicantLabel(labelSource, labelIndex, labelRows),
        applicant_ref: `before-row:${pair.beforeIndex}`,
        previous: previous[field],
        next: next[field],
      });
    }
  }
  const people = pairs.filter(
    (pair) => !isBlank(before[pair.beforeIndex]) || !isBlank(after[pair.afterIndex]),
  );
  const beforeOrder = [...people]
    .sort((left, right) => left.beforeIndex - right.beforeIndex)
    .map((pair) => pair.beforeIndex);
  const afterOrder = [...people]
    .sort((left, right) => left.afterIndex - right.afterIndex)
    .map((pair) => pair.beforeIndex);
  if (JSON.stringify(beforeOrder) !== JSON.stringify(afterOrder)) {
    changes.push({
      field: 'applicants.order',
      label: 'Applicant order',
      previous: beforeOrder.map((index) => applicantLabel(before[index], index, before)),
      next: afterOrder.map((index) => applicantLabel(before[index], index, before)),
    });
  }
  before.forEach((applicant, index) => {
    if (usedBefore.has(index) || isBlank(applicant)) return;
    changes.push({
      field: 'applicants.removed',
      label: 'Applicant removed',
      applicant: applicantLabel(applicant, index, before),
      applicant_ref: `before-row:${index}`,
      previous: snapshotApplicant(applicant),
      next: null,
    });
  });
  after.forEach((applicant, index) => {
    if (usedAfter.has(index) || isBlank(applicant)) return;
    changes.push({
      field: 'applicants.added',
      label: 'Applicant added',
      applicant: applicantLabel(applicant, index, after),
      applicant_ref: `after-row:${index}`,
      previous: null,
      next: snapshotApplicant(applicant),
    });
  });
  return changes;
}

function diffTurnAroundTime(beforeRow, payload) {
  const previous = {};
  const next = {};
  const changes = [];
  for (const field of HEADER_FIELDS) {
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
  if (Object.prototype.hasOwnProperty.call(payload || {}, 'applicants')) {
    for (const change of diffApplicants(beforeRow?.applicants, payload.applicants)) {
      const key = change.applicant ? `${change.applicant} · ${change.field}` : change.field;
      previous[key] = change.previous;
      next[key] = change.next;
      changes.push(change);
    }
  }
  if (!changes.length) return null;
  return { previous, next, changes };
}

function isSignedSlot(row) {
  return Boolean(row && row.signature_asset_id && row.signed_at);
}

function signatureStatusFromRows(rows) {
  const bySlot = new Map((rows || []).map((row) => [row.slot_key, row]));
  const prepared = bySlot.get('prepared_by');
  const noted = bySlot.get('noted_by');
  if (!prepared?.assigned_signer_id || !noted?.assigned_signer_id) return 'needs_setup';
  if (isSignedSlot(prepared) && isSignedSlot(noted)) return 'completed';
  return 'awaiting_signatures';
}

function signatureEvidence(row) {
  return {
    slot_key: row.slot_key,
    assigned_signer_id: row.assigned_signer_id || null,
    signed_by: row.signed_by || null,
    signer_name_snapshot: row.signer_name_snapshot || null,
    signed_at: row.signed_at || null,
    signature_asset_id: row.signature_asset_id || null,
  };
}

function planTatRevision({ diff, signatureRows }) {
  if (!diff) {
    return {
      record: false,
      clearSlotKeys: [],
      signaturesCleared: [],
      signatureStatusBefore: signatureStatusFromRows(signatureRows),
      renewalRequired: false,
    };
  }
  const cleared = SLOT_ORDER
    .map((key) => (signatureRows || []).find((row) => row.slot_key === key))
    .filter(isSignedSlot)
    .map(signatureEvidence);
  return {
    record: true,
    clearSlotKeys: cleared.map((row) => row.slot_key),
    signaturesCleared: cleared,
    signatureStatusBefore: signatureStatusFromRows(signatureRows),
    renewalRequired: cleared.length > 0,
  };
}

function shouldRecordTatEdit(diff, updatedRowCount) {
  return diff != null && Number(updatedRowCount) > 0;
}

/**
 * Noted By on Turn Around Time waits until Prepared By has signed.
 * Other forms and the Prepared By slot are not held back here.
 */
function shouldSendTatNotedByAssignmentNotice({ sourceTable, slotKey, preparedBySigned }) {
  if (sourceTable !== TURN_AROUND_TIME_TABLE || slotKey !== 'noted_by') return true;
  return preparedBySigned === true;
}

function buildContentEditAudit({ recordId, actorId, actorName, diff, plan }) {
  const renewal = plan?.renewalRequired === true;
  return {
    actorId,
    eventType: EDIT_EVENT,
    entityType: EDIT_ENTITY,
    entityId: String(recordId),
    documentType: 'rsp',
    beforeState: {
      values: diff.previous,
      signatures: plan?.signaturesCleared || [],
    },
    afterState: {
      values: diff.next,
      changes: diff.changes,
      actor_name: actorName || null,
      signature_status_before: plan?.signatureStatusBefore || 'needs_setup',
      signed_before_edit: (plan?.signaturesCleared || []).length > 0,
      renewal_required: renewal,
      signatures_cleared: plan?.signaturesCleared || [],
      integrity_note: renewal ? RENEWAL_NOTE : null,
    },
    reason: renewal
      ? RENEWAL_NOTE
      : 'Turn Around Time content was updated before the current signatures were complete.',
  };
}

function serializeEditHistoryRow(row) {
  const after = row.after_state || {};
  return {
    id: row.id,
    edited_at: row.created_at,
    edited_by: row.actor_id,
    edited_by_name: after.actor_name || row.actor_name || null,
    signature_status_before: after.signature_status_before || null,
    signed_before_edit: after.signed_before_edit === true,
    renewal_required: after.renewal_required === true,
    signatures_cleared: Array.isArray(after.signatures_cleared) ? after.signatures_cleared : [],
    integrity_note: after.integrity_note || null,
    changes: Array.isArray(after.changes) ? after.changes : [],
  };
}

function renewalStillPending(edits, signatureStatus) {
  if (!signatureStatus || signatureStatus === 'completed') return false;
  return (edits || []).some((edit) => edit && edit.renewal_required === true);
}

module.exports = {
  TURN_AROUND_TIME_TABLE,
  EDIT_EVENT,
  EDIT_ENTITY,
  SLOT_ORDER,
  HEADER_FIELDS,
  APPLICANT_FIELDS,
  RENEWAL_NOTE,
  canonical,
  diffTurnAroundTime,
  signatureStatusFromRows,
  planTatRevision,
  shouldRecordTatEdit,
  shouldSendTatNotedByAssignmentNotice,
  buildContentEditAudit,
  serializeEditHistoryRow,
  renewalStillPending,
};
