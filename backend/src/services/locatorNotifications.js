const {
  insertNotification,
  insertNotificationForUsers,
  getHrAdminUserIds,
} = require('./notificationService');

function fmtDate(value) {
  if (!value) return '';
  return String(value).slice(0, 10);
}

function fmtSegmentLabel({ amIn, amOut, pmIn, pmOut }) {
  const parts = [];
  if (amIn) parts.push('AM IN');
  if (amOut) parts.push('AM OUT');
  if (pmIn) parts.push('PM IN');
  if (pmOut) parts.push('PM OUT');
  return parts.join(', ');
}

async function notifyAfterSubmit(
  pool,
  {
    slipId,
    status,
    employeeUserId,
    employeeName,
    slipDate,
    amIn,
    amOut,
    pmIn,
    pmOut,
    departmentHeadUserId,
  }
) {
  const dateLabel = fmtDate(slipDate);
  const segmentLabel = fmtSegmentLabel({ amIn, amOut, pmIn, pmOut });
  const who = employeeName || 'An employee';
  const bodyBase = `${who} filed a locator slip for ${dateLabel}${segmentLabel ? ` (${segmentLabel})` : ''}.`;

  if (status === 'pending_department_head' && departmentHeadUserId) {
    await insertNotification(pool, {
      userId: departmentHeadUserId,
      category: 'locator',
      type: 'locator_pending_department_head',
      title: 'Locator slip needs your review',
      body: bodyBase,
      referenceType: 'locator_slip',
      referenceId: slipId,
      metadata: { employee_id: employeeUserId },
    });
    return;
  }

  if (status === 'pending_hr' || status === 'pending') {
    const hrIds = await getHrAdminUserIds(pool);
    const targets = hrIds.filter((id) => id !== employeeUserId);
    await insertNotificationForUsers(pool, targets, {
      category: 'locator',
      type: 'locator_pending_hr',
      title: 'New locator slip for HR review',
      body: bodyBase,
      referenceType: 'locator_slip',
      referenceId: slipId,
      metadata: { employee_id: employeeUserId },
    });
  }
}

async function notifyDepartmentHeadApprovedForHr(
  pool,
  { slipId, employeeName, slipDate }
) {
  const hrIds = await getHrAdminUserIds(pool);
  await insertNotificationForUsers(pool, hrIds, {
    category: 'locator',
    type: 'locator_forwarded_to_hr',
    title: 'Locator slip ready for HR approval',
    body: `${employeeName || 'An employee'} locator slip (${fmtDate(
      slipDate
    )}) was endorsed by the department head.`,
    referenceType: 'locator_slip',
    referenceId: slipId,
    metadata: null,
  });
}

async function notifyEmployee(
  pool,
  { employeeUserId, slipId, type, title, body, metadata = null }
) {
  if (!employeeUserId) return;
  await insertNotification(pool, {
    userId: employeeUserId,
    category: 'locator',
    type,
    title,
    body,
    referenceType: 'locator_slip',
    referenceId: slipId,
    metadata,
  });
}

module.exports = {
  notifyAfterSubmit,
  notifyDepartmentHeadApprovedForHr,
  notifyEmployee,
};
