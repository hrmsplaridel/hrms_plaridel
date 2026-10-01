/**
 * Actions governed by DocuTracker System Access (docutracker_permissions).
 * Approve / forward / return / reject are deliberately excluded: they are
 * authorized only by the active workflow step's assignees.
 */
const SYSTEM_ACCESS_ACTIONS = Object.freeze([
  'view',
  'create_draft',
  'download',
  'submit',
]);

/** System Access actions plus the legacy `create` alias stored by older rows. */
const GENERAL_PERMISSION_ACTIONS = new Set([...SYSTEM_ACCESS_ACTIONS, 'create']);

module.exports = {
  GENERAL_PERMISSION_ACTIONS,
  SYSTEM_ACCESS_ACTIONS,
};
