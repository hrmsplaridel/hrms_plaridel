// Centralized leave workflow/transition rules.
// Source of truth for allowed status changes and who can perform them.

const STATUSES = Object.freeze([
  'draft',
  'pending',
  'returned',
  'approved',
  'rejected',
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

function canEmployeeEdit(currentStatus) {
  return currentStatus === 'draft' || currentStatus === 'returned';
}

function canEmployeeCancel(currentStatus) {
  return (
    currentStatus === 'draft' ||
    currentStatus === 'pending' ||
    currentStatus === 'returned'
  );
}

function validateEmployeeUpdateTransition({ currentStatus, desiredStatus }) {
  // Employee endpoint: PUT /api/leave/:id
  //
  // Allowed:
  // - draft -> pending (submitted)
  // - returned -> pending (resubmitted)
  // - draft -> draft (saved_draft)
  // - returned -> returned (updated)
  //
  // Everything else is blocked here (including returned -> draft).
  if (!canEmployeeEdit(currentStatus)) {
    throw invalidActionError('Only draft or returned leave requests can be updated.');
  }

  const fromStatus = currentStatus;
  const toStatus = desiredStatus == null || desiredStatus === ''
    ? fromStatus
    : desiredStatus;

  if (!isValidStatus(toStatus)) {
    throw invalidTransitionError(fromStatus, toStatus ?? 'unknown');
  }

  if (toStatus === fromStatus) {
    if (toStatus === 'draft') {
      return { nextStatus: fromStatus, historyAction: 'saved_draft' };
    }
    if (toStatus === 'returned') {
      return { nextStatus: fromStatus, historyAction: 'updated' };
    }
    // Should be unreachable because canEmployeeEdit gates draft/returned.
    throw invalidActionError('This leave request status is not editable.');
  }

  if (toStatus === 'pending') {
    if (fromStatus === 'draft') {
      return { nextStatus: toStatus, historyAction: 'submitted' };
    }
    if (fromStatus === 'returned') {
      return { nextStatus: toStatus, historyAction: 'resubmitted' };
    }
    throw invalidTransitionError(fromStatus, toStatus);
  }

  // Cancellation is required to happen via the dedicated cancel endpoint.
  if (toStatus === 'cancelled') {
    throw invalidActionError('Cancellation must be done via the cancel endpoint.');
  }

  // Any other transition is blocked.
  throw invalidTransitionError(fromStatus, toStatus);
}

function validateEmployeeCancelTransition({ currentStatus }) {
  if (!canEmployeeCancel(currentStatus)) {
    throw invalidTransitionError(currentStatus, 'cancelled');
  }

  return { nextStatus: 'cancelled', historyAction: 'cancelled' };
}

function validateAdminTransition({ currentStatus, desiredStatus }) {
  // Admin endpoints:
  // - approve: pending -> approved
  // - reject: pending -> rejected
  // - return: pending -> returned
  if (currentStatus !== 'pending') {
    throw invalidTransitionError(currentStatus, desiredStatus);
  }

  switch (desiredStatus) {
    case 'approved':
      return { nextStatus: 'approved', historyAction: 'approved' };
    case 'rejected':
      return { nextStatus: 'rejected', historyAction: 'rejected' };
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
  validateAdminTransition,
};

