/**
 * Default DocuTracker role permissions: the policy a fresh install seeds in
 * backend/scripts/init-schema.sql (baseline `docutracker_permissions` rows).
 * Resetting a role's settings restores these rows instead of leaving the role
 * with no rule. Must stay identical to the init-schema baseline; a test
 * compares the two.
 */
const ROLE_WILDCARD_DEFAULTS = Object.freeze({
  employee: {
    view: true, create: true, submit: true, download: true, edit: false,
    delete: false, forward: false, approve: false, reject: false, return: false,
  },
  hr: {
    view: true, create: true, submit: true, download: true, edit: true,
    delete: false, forward: true, approve: true, reject: true, return: true,
  },
  supervisor: {
    view: true, create: true, submit: true, download: true, edit: true,
    delete: false, forward: true, approve: true, reject: true, return: true,
  },
  admin: {
    view: true, create: true, submit: true, download: true, edit: true,
    delete: true, forward: true, approve: true, reject: true, return: true,
  },
});

const DOCUMENT_TYPE_DEFAULTS = Object.freeze([
  ['employee', 'memo', 'create_draft', false],
  ['employee', 'memo', 'submit', false],
  ['hr', 'memo', 'create_draft', false],
  ['hr', 'memo', 'submit', false],
  ['supervisor', 'memo', 'create_draft', false],
  ['supervisor', 'memo', 'submit', false],
  ['employee', 'purchaseRequest', 'create_draft', false],
  ['employee', 'purchaseRequest', 'submit', false],
  ['hr', 'purchaseRequest', 'create_draft', false],
  ['hr', 'purchaseRequest', 'submit', false],
  ['supervisor', 'purchaseRequest', 'create_draft', false],
  ['supervisor', 'purchaseRequest', 'submit', false],
  ['hr', 'memo', 'release', true],
]);

const DEFAULT_ROLE_PERMISSIONS = Object.freeze([
  ...Object.entries(ROLE_WILDCARD_DEFAULTS).flatMap(([roleId, actions]) =>
    Object.entries(actions).map(([action, granted]) =>
      Object.freeze({ role_id: roleId, document_type: '*', action, granted })
    )
  ),
  ...DOCUMENT_TYPE_DEFAULTS.map(([roleId, documentType, action, granted]) =>
    Object.freeze({ role_id: roleId, document_type: documentType, action, granted })
  ),
]);

/**
 * Default rows for one role and document scope. [actions] limits the result
 * to the given stored action names (e.g. both `create_draft` and `create`).
 */
function defaultRolePermissions(roleId, documentType, actions = null) {
  return DEFAULT_ROLE_PERMISSIONS.filter(
    (row) =>
      row.role_id === roleId &&
      row.document_type === documentType &&
      (actions == null || actions.includes(row.action))
  );
}

module.exports = {
  DEFAULT_ROLE_PERMISSIONS,
  defaultRolePermissions,
};
