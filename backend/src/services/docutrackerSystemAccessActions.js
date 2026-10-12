/**
 * Actions governed by DocuTracker System Access (docutracker_permissions).
 * Approve / forward / return / reject are deliberately excluded: they are
 * authorized only by the active workflow step's assignees.
 *
 * `release` distributes an approved, release-required document to a
 * department. Unlike the other actions, administrators do not bypass it;
 * they need an explicit grant like everyone else.
 */
const RELEASE_ACTION = 'release';

const SYSTEM_ACCESS_ACTIONS = Object.freeze([
  'view',
  'create_draft',
  'download',
  'submit',
  RELEASE_ACTION,
]);

/** System Access actions plus the legacy `create` alias stored by older rows. */
const GENERAL_PERMISSION_ACTIONS = new Set([...SYSTEM_ACCESS_ACTIONS, 'create']);

module.exports = {
  GENERAL_PERMISSION_ACTIONS,
  RELEASE_ACTION,
  SYSTEM_ACCESS_ACTIONS,
};
