const {
  insertNotification,
  insertNotificationForUsers,
  getHrAdminUserIds,
} = require('./notificationService');

function fmtRange(startStr, endStr) {
  if (!startStr || !endStr) return '';
  return `${startStr} – ${endStr}`;
}

function leaveLabel(name) {
  return name || 'Leave';
}

/**
 * Employee submitted or resubmitted; notify department head and/or HR.
 */
async function notifyAfterSubmit(pool, {
  leaveRequestId,
  status,
  employeeUserId,
  employeeName,
  leaveTypeName,
  startDateStr,
  endDateStr,
  departmentHeadUserId,
}) {
  const range = fmtRange(startDateStr, endDateStr);
  const who = employeeName || 'An employee';
  const lt = leaveLabel(leaveTypeName);

  if (status === 'pending_department_head' && departmentHeadUserId) {
    await insertNotification(pool, {
      userId: departmentHeadUserId,
      category: 'leave',
      type: 'leave_pending_department_head',
      title: 'Leave request needs your review',
      body: `${who} submitted ${lt} (${range}).`,
      referenceType: 'leave_request',
      referenceId: leaveRequestId,
      metadata: { employee_id: employeeUserId, leave_type: leaveTypeName },
    });
    return;
  }

  if (status === 'pending_hr' || status === 'pending') {
    const hrIds = await getHrAdminUserIds(pool);
    const targets = hrIds.filter((id) => id !== employeeUserId);
    await insertNotificationForUsers(pool, targets, {
      category: 'leave',
      type: 'leave_pending_hr',
      title: 'New leave request for HR',
      body: `${who} submitted ${lt} (${range}).`,
      referenceType: 'leave_request',
      referenceId: leaveRequestId,
      metadata: { employee_id: employeeUserId, leave_type: leaveTypeName },
    });
  }
}

/** Department head approved; request is now with HR. */
async function notifyDepartmentHeadApprovedForHr(pool, {
  leaveRequestId,
  employeeName,
  leaveTypeName,
  startDateStr,
  endDateStr,
}) {
  const hrIds = await getHrAdminUserIds(pool);
  const range = fmtRange(startDateStr, endDateStr);
  const who = employeeName || 'An employee';
  const lt = leaveLabel(leaveTypeName);
  await insertNotificationForUsers(pool, hrIds, {
    category: 'leave',
    type: 'leave_forwarded_to_hr',
    title: 'Leave request ready for HR approval',
    body: `${who} — ${lt} (${range}) was endorsed by the department head.`,
    referenceType: 'leave_request',
    referenceId: leaveRequestId,
    metadata: { leave_type: leaveTypeName },
  });
}

async function notifyEmployee(pool, {
  employeeUserId,
  leaveRequestId,
  type,
  title,
  body,
  metadata = {},
}) {
  if (!employeeUserId) return;
  await insertNotification(pool, {
    userId: employeeUserId,
    category: 'leave',
    type,
    title,
    body,
    referenceType: 'leave_request',
    referenceId: leaveRequestId,
    metadata,
  });
}

/** HR/admin applied forced leave deduction against vacation balance. */
async function notifyForcedLeaveDeductionApplied(pool, {
  employeeUserId,
  deductedDays,
  remainingDays,
  remarks,
}) {
  if (!employeeUserId) return;
  await insertNotification(pool, {
    userId: employeeUserId,
    category: 'leave',
    type: 'leave_forced_deduction_applied',
    title: 'Forced leave deduction applied',
    body:
      `HR applied a forced leave deduction of ${deductedDays} day(s) from your Vacation Leave balance.` +
      ` Available balance: ${remainingDays} day(s).` +
      (remarks ? ` Note: ${remarks}` : ''),
    referenceType: null,
    referenceId: null,
    metadata: {
      leave_type: 'vacationLeave',
      deducted_days: deductedDays,
      available_days: remainingDays,
      remarks: remarks || null,
    },
  });
}

/** Employee cancelled a request that was still in the approval pipeline. */
async function notifyStakeholdersLeaveCancelled(pool, {
  leaveRequestId,
  employeeUserId,
  employeeName,
  previousStatus,
  leaveTypeName,
  startDateStr,
  endDateStr,
  cancelReason,
  departmentHeadUserId,
}) {
  const range = fmtRange(startDateStr, endDateStr);
  const who = employeeName || 'An employee';
  const lt = leaveLabel(leaveTypeName);
  const body = `${who} cancelled ${lt} (${range}).${cancelReason ? ` Reason: ${cancelReason}` : ''}`;

  const hrIds = await getHrAdminUserIds(pool);
  const hrTargets = hrIds.filter((id) => id !== employeeUserId);
  await insertNotificationForUsers(pool, hrTargets, {
    category: 'leave',
    type: 'leave_cancelled_hr',
    title: 'Leave request cancelled',
    body,
    referenceType: 'leave_request',
    referenceId: leaveRequestId,
    metadata: { previous_status: previousStatus },
  });

  if (
    previousStatus === 'pending_department_head' &&
    departmentHeadUserId &&
    departmentHeadUserId !== employeeUserId
  ) {
    await insertNotification(pool, {
      userId: departmentHeadUserId,
      category: 'leave',
      type: 'leave_cancelled_department_head',
      title: 'Leave request cancelled',
      body,
      referenceType: 'leave_request',
      referenceId: leaveRequestId,
      metadata: { previous_status: previousStatus },
    });
  }
}

module.exports = {
  notifyAfterSubmit,
  notifyDepartmentHeadApprovedForHr,
  notifyEmployee,
  notifyForcedLeaveDeductionApplied,
  notifyStakeholdersLeaveCancelled,
  fmtRange,
  leaveLabel,
};
