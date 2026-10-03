const { insertNotification, insertNotificationForUsers } = require('./notificationService');
const { resolveDtrCorrectionReviewers } = require('./dtrCorrectionReviewers');

async function submitted(db, row) {
  const reviewers = await resolveDtrCorrectionReviewers(db);
  await insertNotificationForUsers(db, reviewers.filter(r => String(r.id) !== String(row.employee_id)).map(r => r.id), {
    category: 'dtr', type: 'dtr_correction_pending_review',
    title: 'DTR correction pending review',
    body: `An employee submitted an attendance correction for ${String(row.attendance_date).slice(0, 10)}.`,
    referenceType: 'dtr_correction', referenceId: row.id,
    metadata: { employee_id: row.employee_id, attendance_date: row.attendance_date },
  });
}

async function reviewed(db, row, decision) {
  await insertNotification(db, {
    userId: row.employee_id, category: 'dtr', type: `dtr_correction_${decision}`,
    title: `DTR correction ${decision}`,
    body: `Your attendance correction for ${row.attendance_date} was ${decision}. Open the request to view the review notes.`,
    referenceType: 'dtr_correction', referenceId: row.id,
    metadata: { status: decision, attendance_date: row.attendance_date },
  });
}
module.exports = { submitted, reviewed };
