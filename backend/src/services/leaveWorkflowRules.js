// Centralized leave workflow/transition rules.
// Source of truth for allowed status changes and who can perform them.
//
// === Two-stage approval workflow ===
// Employee submit → pending_department_head → (dept head approve) → pending_hr → (HR approve) → approved
// If no department head → skip to pending_hr directly.
// Legacy 'pending' is treated as alias for 'pending_hr' for backward compatibility.

const STATUSES = Object.freeze([
  'draft',
  'pending',                     // legacy alias for pending_hr
  'pending_department_head',     // awaiting department head
  'pending_hr',                  // awaiting HR/admin
  'rejected_by_department_head', // dept head rejected
  'rejected_by_hr',              // HR/admin rejected
  'returned',
  'approved',
  'rejected',                    // legacy single-stage rejection
  'cancelled',
]);

function normalizeStatus(s) {
  if (s == null) return null;
  return String(s).trim().toLowerCase().replaceAll(' ', '').replaceAll('_', '');
}

function isValidStatus(status) {
  return STATUSES.includes(status);
}

function invalidTransitionError(fromStatus, toStatus) {
  const err = new Error(`Invalid status transition: ${fromStatus} -> ${toStatus}`);
  err.statusCode = 400;
  return err;
}

function invalidActionError(message) {
  const err = new Error(message);
  err.statusCode = 400;
  return err;
}

/**
 * Can the employee edit this request?
 * Editable when draft, returned, rejected_by_department_head, or rejected_by_hr.
 */
function canEmployeeEdit(currentStatus) {
  return (
    currentStatus === 'draft' ||
    currentStatus === 'returned' ||
    currentStatus === 'rejected_by_department_head' ||
    currentStatus === 'rejected_by_hr'
  );
}

/**
 * Can the employee cancel this request?
 */
function canEmployeeCancel(currentStatus) {
  return (
    currentStatus === 'draft' ||
    currentStatus === 'pending' ||
    currentStatus === 'pending_department_head' ||
    currentStatus === 'pending_hr' ||
    currentStatus === 'returned' ||
    currentStatus === 'rejected_by_department_head' ||
    currentStatus === 'rejected_by_hr'
  );
}

/**
 * Validate employee update/resubmit transitions.
 * The actual target status (pending_department_head vs pending_hr) is
 * determined by the route handler based on dept head availability,
 * NOT by this function. This function validates the "intent" to submit.
 *
 * @param {object} opts
 * @param {string} opts.currentStatus
 * @param {string|null} opts.desiredStatus - 'pending' (intent to submit) or same-status (save)
 * @returns {{nextStatus: string, historyAction: string}}
 */
function validateEmployeeUpdateTransition({ currentStatus, desiredStatus }) {
  if (!canEmployeeEdit(currentStatus)) {
    throw invalidActionError('Only draft, returned, or rejected leave requests can be updated.');
  }

  const fromStatus = currentStatus;
  const toStatus = desiredStatus == null || desiredStatus === ''
    ? fromStatus
    : desiredStatus;

  if (!isValidStatus(toStatus) && toStatus !== 'pending') {
    throw invalidTransitionError(fromStatus, toStatus ?? 'unknown');
  }

  // Same-status save
  if (toStatus === fromStatus) {
    if (toStatus === 'draft') {
      return { nextStatus: fromStatus, historyAction: 'saved_draft' };
    }
    if (toStatus === 'returned') {
      return { nextStatus: fromStatus, historyAction: 'updated' };
    }
    if (toStatus === 'rejected_by_department_head' || toStatus === 'rejected_by_hr') {
      return { nextStatus: fromStatus, historyAction: 'updated' };
    }
    throw invalidActionError('This leave request status is not editable.');
  }

  // Submit/resubmit intent (route handler will resolve actual target status)
  if (
    toStatus === 'pending' ||
    toStatus === 'pending_department_head' ||
    toStatus === 'pending_hr'
  ) {
    if (fromStatus === 'draft') {
      return { nextStatus: toStatus, historyAction: 'submitted' };
    }
    if (fromStatus === 'returned' || fromStatus === 'rejected_by_department_head' || fromStatus === 'rejected_by_hr') {
      return { nextStatus: toStatus, historyAction: 'resubmitted' };
    }
    throw invalidTransitionError(fromStatus, toStatus);
  }

  if (toStatus === 'cancelled') {
    throw invalidActionError('Cancellation must be done via the cancel endpoint.');
  }

  throw invalidTransitionError(fromStatus, toStatus);
}

function validateEmployeeCancelTransition({ currentStatus }) {
  if (!canEmployeeCancel(currentStatus)) {
    throw invalidTransitionError(currentStatus, 'cancelled');
  }

  return { nextStatus: 'cancelled', historyAction: 'cancelled' };
}

/**
 * Validate department head transitions.
 * Department head can act on pending_department_head requests.
 */
function validateDepartmentHeadTransition({ currentStatus, desiredStatus }) {
  if (currentStatus !== 'pending_department_head') {
    throw invalidTransitionError(currentStatus, desiredStatus);
  }

  switch (desiredStatus) {
    case 'pending_hr':
      return { nextStatus: 'pending_hr', historyAction: 'department_head_approved' };
    case 'rejected_by_department_head':
      return { nextStatus: 'rejected_by_department_head', historyAction: 'department_head_rejected' };
    case 'returned':
      return { nextStatus: 'returned', historyAction: 'department_head_returned' };
    default:
      throw invalidTransitionError(currentStatus, desiredStatus);
  }
}

/**
 * Validate admin/HR transitions.
 * Admin/HR can act on pending_hr (and legacy 'pending') requests.
 */
function validateAdminTransition({ currentStatus, desiredStatus }) {
  // Accept both 'pending_hr' and legacy 'pending'
  if (currentStatus !== 'pending_hr' && currentStatus !== 'pending') {
    throw invalidTransitionError(currentStatus, desiredStatus);
  }

  switch (desiredStatus) {
    case 'approved':
      return { nextStatus: 'approved', historyAction: 'approved' };
    case 'rejected':
    case 'rejected_by_hr':
      return { nextStatus: 'rejected_by_hr', historyAction: 'rejected' };
    case 'returned':
      return { nextStatus: 'returned', historyAction: 'returned' };
    default:
      throw invalidTransitionError(currentStatus, desiredStatus);
  }
}

module.exports = {
  STATUSES,
  normalizeStatus,
  isValidStatus,
  canEmployeeEdit,
  canEmployeeCancel,
  validateEmployeeUpdateTransition,
  validateEmployeeCancelTransition,
  validateDepartmentHeadTransition,
  validateAdminTransition,
};
