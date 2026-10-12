/**
 * Applicants Profile lock state is derived from DocuTracker signature rows.
 * There is no separate lock flag. A form is locked only when both required
 * slots are assigned and signed.
 *
 * Replacing a signature image keeps both slots signed, so the form stays locked.
 * An admin reassignment that changes the signer clears that slot's signature.
 * The form is editable again because the lock is computed from the signature
 * rows, not from a separate flag. Reassigning the same person keeps the lock.
 */

const APPLICANTS_PROFILE_TABLE = 'applicants_profile_entries';
const REQUIRED_SLOTS = Object.freeze(['prepared_by', 'checked_by']);

const LOCKED_CODE = 'APPLICANTS_PROFILE_LOCKED';
const LOCKED_MESSAGE =
  'Applicants Profile is locked because all required signatures have been completed.';

function isSignedSlot(row) {
  return Boolean(row && row.signature_asset_id && row.signed_at);
}

function applicantsProfileSignatureState(rows) {
  const bySlot = new Map();
  for (const row of rows || []) {
    if (row && row.slot_key) bySlot.set(row.slot_key, row);
  }
  const slots = REQUIRED_SLOTS.map((slotKey) => bySlot.get(slotKey) || null);
  if (slots.some((row) => !row || !row.assigned_signer_id)) {
    return { signature_status: 'needs_setup', locked: false };
  }
  const locked = slots.every(isSignedSlot);
  return {
    signature_status: locked ? 'completed' : 'awaiting_signatures',
    locked,
  };
}

/**
 * Checked By on Applicants Profile must not get an actionable assignment
 * notice until Prepared By has signed. Other forms and other slots are unchanged.
 */
function shouldSendApplicantsProfileAssignmentNotice({
  sourceTable,
  slotKey,
  preparedBySigned,
}) {
  if (sourceTable !== APPLICANTS_PROFILE_TABLE || slotKey !== 'checked_by') {
    return true;
  }
  return preparedBySigned === true;
}

module.exports = {
  APPLICANTS_PROFILE_TABLE,
  REQUIRED_SLOTS,
  LOCKED_CODE,
  LOCKED_MESSAGE,
  applicantsProfileSignatureState,
  shouldSendApplicantsProfileAssignmentNotice,
};
