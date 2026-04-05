const { insertNotification, insertNotificationForUsers, getHrAdminUserIds } = require('./notificationService');

function dateOnly(val) {
  if (!val) return '';
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  return String(val).slice(0, 10);
}

/**
 * New correction filed — notify admin/HR (excluding the user who submitted, if they are admin/HR).
 */
async function notifyHrAdminNewCorrection(pool, {
  correctionId,
  employeeUserId,
  employeeName,
  attendanceDate,
  filedByUserId,
}) {
  const dateStr = dateOnly(attendanceDate);
  const hrIds = await getHrAdminUserIds(pool);
  const targets = hrIds.filter((id) => id && id !== filedByUserId);
  await insertNotificationForUsers(pool, targets, {
    category: 'dtr',
    type: 'dtr_correction_pending_hr',
    title: 'DTR correction request pending',
    body: `${employeeName || 'An employee'} requested an attendance correction for ${dateStr}.`,
    referenceType: 'dtr_correction',
    referenceId: correctionId,
    metadata: { employee_id: employeeUserId, attendance_date: dateStr },
  });
}

/**
 * HR approved or rejected — notify the employee who filed (target of the correction).
 */
async function notifyEmployeeCorrectionDecision(pool, {
  employeeUserId,
  correctionId,
  status,
  attendanceDate,
  reviewNotes,
}) {
  if (!employeeUserId) return;
  const dateStr = dateOnly(attendanceDate);
  const approved = status === 'approved';
  const title = approved ? 'DTR correction approved' : 'DTR correction rejected';
  let body = approved
    ? `Your attendance correction for ${dateStr} was approved and applied to your record.`
    : `Your attendance correction for ${dateStr} was rejected.`;
  if (!approved && reviewNotes && String(reviewNotes).trim()) {
    body += ` Notes: ${String(reviewNotes).trim()}`;
  }
  await insertNotification(pool, {
    userId: employeeUserId,
    category: 'dtr',
    type: approved ? 'dtr_correction_approved' : 'dtr_correction_rejected',
    title,
    body,
    referenceType: 'dtr_correction',
    referenceId: correctionId,
    metadata: { attendance_date: dateStr, status },
  });
}

module.exports = {
  notifyHrAdminNewCorrection,
  notifyEmployeeCorrectionDecision,
  dateOnly,
};
