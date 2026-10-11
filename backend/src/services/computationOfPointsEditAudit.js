/**
 * Content-edit history for Computation of Points.
 * Uses the existing governance audit table. A signature is never cleared here.
 *
 * Candidates have no stable id. Rows are matched by name, position, salary
 * grade, and rate so a reorder is not stored as another person's score change.
 * A same-row rename is matched only when the name or the seven scores still agree.
 */

const COMPUTATION_OF_POINTS_TABLE = 'computation_of_points_entries';
const EDIT_EVENT = 'computation_of_points_content_edited';
const EDIT_ENTITY = 'computation_of_points_entry';

const HEADER_FIELDS = Object.freeze([
  'date',
  'position_level',
  'position',
  'salary_grade',
  'rate',
  'office',
  'min_education',
  'min_training',
  'min_experience',
  'min_eligibility',
  'prepared_by_name',
]);

const CANDIDATE_FIELDS = Object.freeze([
  'name',
  'position',
  'salary_grade',
  'rate',
  'education',
  'eligibility',
  'experience',
  'training',
  'performance',
  'potential',
  'work_attitude',
  'total',
  'rank',
]);

const SCORE_FIELDS = Object.freeze([
  'education',
  'eligibility',
  'experience',
  'training',
  'performance',
  'potential',
  'work_attitude',
]);

/** Labels only. These caps mirror the screen; this module never rewrites scores. */
const SCORE_MAX = Object.freeze({
  education: 25,
  eligibility: 20,
  experience: 15,
  training: 10,
  performance: 10,
  potential: 10,
  work_attitude: 10,
});

const FIELD_LABELS = Object.freeze({
  date: 'Date',
  position_level: 'Position level',
  position: 'Position',
  salary_grade: 'Salary grade',
  rate: 'Rate',
  office: 'Office',
  min_education: 'Minimum education',
  min_training: 'Minimum training',
  min_experience: 'Minimum experience',
  min_eligibility: 'Minimum eligibility',
  prepared_by_name: 'Prepared by name',
  name: 'Candidate name',
  education: 'Education',
  eligibility: 'Eligibility',
  experience: 'Experience',
  training: 'Training',
  performance: 'Performance',
  potential: 'Potential',
  work_attitude: 'Work attitude',
  total: 'Total',
  rank: 'Rank',
});

const SIGNED_EDIT_NOTE =
  'The Computation of Points content was changed after Prepared By signed. The existing signature image, signer, and signed time were kept. That signature does not approve the revised content.';

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

function normalizeCandidate(raw) {
  const source = canonical(raw);
  const row = source && typeof source === 'object' && !Array.isArray(source) ? source : {};
  const out = {};
  for (const field of CANDIDATE_FIELDS) out[field] = textOrNull(row[field]);
  return out;
}

function parseCandidates(value) {
  const parsed = canonical(value);
  if (!Array.isArray(parsed)) return [];
  return parsed.map((item) => normalizeCandidate(item));
}

function isBlank(candidate) {
  return CANDIDATE_FIELDS.every((field) => candidate[field] == null);
}

function identityKey(candidate) {
  const identity = ['name', 'position', 'salary_grade', 'rate']
    .map((field) => candidate[field] || '')
    .join('\u0001');
  if (identity !== '\u0001\u0001\u0001') return identity;
  if (!isBlank(candidate)) {
    return `__content__:${scoreFingerprint(candidate)}:${candidate.total || ''}:${candidate.rank || ''}`;
  }
  return '__blank__';
}

function scoreFingerprint(candidate) {
  return SCORE_FIELDS.map((field) => candidate[field] || '').join('\u0001');
}

function nameCounts(candidates) {
  const counts = new Map();
  for (const candidate of candidates) {
    const name = candidate.name || '';
    counts.set(name, (counts.get(name) || 0) + 1);
  }
  return counts;
}

function candidateLabel(candidate, index, candidates) {
  const name = candidate.name || 'Unnamed candidate';
  const counts = nameCounts(candidates);
  if ((counts.get(candidate.name || '') || 0) > 1) {
    return `${name} (row ${index + 1})`;
  }
  return name;
}

function snapshotCandidate(candidate) {
  const out = {};
  for (const field of CANDIDATE_FIELDS) {
    if (candidate[field] != null) out[field] = candidate[field];
  }
  return out;
}

function numericScore(value) {
  if (value == null) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

/** Same screen rule: empty scores are skipped, and each score is capped. */
function formulaTotal(candidate) {
  let sum = 0;
  for (const field of SCORE_FIELDS) {
    const number = numericScore(candidate[field]);
    if (number == null) continue;
    sum += Math.min(Math.max(number, 0), SCORE_MAX[field]);
  }
  return sum.toFixed(2);
}

function formulaRanks(candidates) {
  const ranked = [];
  candidates.forEach((candidate, index) => {
    if (!candidate.name) return;
    ranked.push({ index, total: Number(formulaTotal(candidate)) });
  });
  ranked.sort((left, right) => right.total - left.total);
  const ranks = new Map();
  let rank = 0;
  let position = 0;
  let lastTotal = null;
  for (const entry of ranked) {
    position += 1;
    if (lastTotal == null || entry.total !== lastTotal) {
      rank = position;
      lastTotal = entry.total;
    }
    ranks.set(entry.index, String(rank));
  }
  return ranks;
}

function valueKind(field, candidate, candidates, index) {
  if (field === 'total') {
    return candidate.total === formulaTotal(candidate) ? 'calculated' : 'stored';
  }
  if (field === 'rank') {
    const expected = formulaRanks(candidates).get(index) || null;
    return candidate.rank === expected ? 'calculated' : 'stored';
  }
  return 'entered';
}

function matchCandidates(before, after) {
  const usedBefore = new Set();
  const usedAfter = new Set();
  const pairs = [];
  const beforeGroups = new Map();
  const afterGroups = new Map();
  const add = (groups, key, index) => {
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(index);
  };
  before.forEach((candidate, index) => add(beforeGroups, identityKey(candidate), index));
  after.forEach((candidate, index) => add(afterGroups, identityKey(candidate), index));
  for (const key of new Set([...beforeGroups.keys(), ...afterGroups.keys()])) {
    const beforeIndexes = beforeGroups.get(key) || [];
    const afterIndexes = afterGroups.get(key) || [];
    const count = Math.min(beforeIndexes.length, afterIndexes.length);
    for (let index = 0; index < count; index += 1) {
      pairs.push({
        beforeIndex: beforeIndexes[index],
        afterIndex: afterIndexes[index],
      });
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
    const sameScores = scoreFingerprint(previous) === scoreFingerprint(next);
    if (!sameName && !sameScores) continue;
    pairs.push({ beforeIndex: index, afterIndex: index });
    usedBefore.add(index);
    usedAfter.add(index);
  }

  return { pairs, usedBefore, usedAfter };
}

function diffCandidates(beforeValue, afterValue) {
  const before = parseCandidates(beforeValue);
  const after = parseCandidates(afterValue);
  const { pairs, usedBefore, usedAfter } = matchCandidates(before, after);
  const changes = [];

  for (const pair of pairs) {
    const previous = before[pair.beforeIndex];
    const next = after[pair.afterIndex];
    if (isBlank(previous) && isBlank(next)) continue;
    for (const field of CANDIDATE_FIELDS) {
      if (sameValue(previous[field], next[field])) continue;
      const kind = valueKind(field, next, after, pair.afterIndex);
      const labelSource = previous.name ? previous : next;
      const labelRows = previous.name ? before : after;
      const labelIndex = previous.name ? pair.beforeIndex : pair.afterIndex;
      changes.push({
        field: `candidates.${field}`,
        label: FIELD_LABELS[field] || field,
        candidate: candidateLabel(labelSource, labelIndex, labelRows),
        candidate_ref: `before-row:${pair.beforeIndex}`,
        previous: previous[field],
        next: next[field],
        value_kind: kind,
        ...(kind === 'calculated'
          ? { note: 'This value matches the screen formula. It was not typed separately.' }
          : {}),
        ...(kind === 'stored'
          ? { note: 'This stored value does not match the screen formula.' }
          : {}),
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
      field: 'candidates.order',
      label: 'Candidate order',
      previous: beforeOrder.map((index) => candidateLabel(before[index], index, before)),
      next: afterOrder.map((index) => candidateLabel(before[index], index, before)),
      value_kind: 'entered',
    });
  }

  before.forEach((candidate, index) => {
    if (usedBefore.has(index) || isBlank(candidate)) return;
    changes.push({
      field: 'candidates.removed',
      label: 'Candidate removed',
      candidate: candidateLabel(candidate, index, before),
      candidate_ref: `before-row:${index}`,
      previous: snapshotCandidate(candidate),
      next: null,
      value_kind: 'entered',
    });
  });
  after.forEach((candidate, index) => {
    if (usedAfter.has(index) || isBlank(candidate)) return;
    changes.push({
      field: 'candidates.added',
      label: 'Candidate added',
      candidate: candidateLabel(candidate, index, after),
      candidate_ref: `after-row:${index}`,
      previous: null,
      next: snapshotCandidate(candidate),
      value_kind: 'entered',
    });
  });

  const blankBefore = before.filter(isBlank).length;
  const blankAfter = after.filter(isBlank).length;
  if (blankAfter > blankBefore) {
    changes.push({
      field: 'candidates.added',
      label: 'Empty candidate row added',
      previous: blankBefore,
      next: blankAfter,
      value_kind: 'entered',
    });
  } else if (blankBefore > blankAfter) {
    changes.push({
      field: 'candidates.removed',
      label: 'Empty candidate row removed',
      previous: blankBefore,
      next: blankAfter,
      value_kind: 'entered',
    });
  }

  return changes;
}

function diffComputationOfPoints(beforeRow, payload) {
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
      value_kind: 'entered',
    });
  }
  if (Object.prototype.hasOwnProperty.call(payload || {}, 'candidates')) {
    for (const change of diffCandidates(beforeRow?.candidates, payload.candidates)) {
      const key = change.candidate ? `${change.candidate} · ${change.field}` : change.field;
      previous[key] = change.previous;
      next[key] = change.next;
      changes.push(change);
    }
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

function shouldRecordContentEdit(diff, updatedRowCount) {
  return diff != null && Number(updatedRowCount) > 0;
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
      : 'Computation of Points content was updated before signing.',
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
  COMPUTATION_OF_POINTS_TABLE,
  EDIT_EVENT,
  EDIT_ENTITY,
  HEADER_FIELDS,
  CANDIDATE_FIELDS,
  SCORE_FIELDS,
  SCORE_MAX,
  SIGNED_EDIT_NOTE,
  canonical,
  diffComputationOfPoints,
  signatureStateFromSlot,
  shouldRecordContentEdit,
  formulaTotal,
  formulaRanks,
  buildContentEditAudit,
  serializeEditHistoryRow,
};
