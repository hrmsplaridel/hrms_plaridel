/**
 * Applicant emails for recruitment decisions the applicant cannot see in-app.
 * A failed send never changes the recruitment update that already succeeded.
 */

const { pool } = require('../config/db');
const {
  sendRspDocumentDecisionEmailJs,
  sendRspScheduleNoticeEmailJs,
  sendRspActionRequiredEmailJs,
  sendRspFinalRequirementReturnedEmailJs,
} = require('../utils/emailJsMail');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const inflightSends = new Map();

const ACTION_TITLES = {
  bi: 'Background Investigation Form',
  ojt: 'OJT / Work Immersion Evaluation',
  wes: 'Work Experience Sheet',
};

const FINAL_DOCUMENT_NAMES = {
  medical_certificate: 'Medical Certificate',
  drug_test_result: 'Drug Test Result',
  nbi_clearance: 'NBI Clearance',
};

const FINAL_REQUIREMENT_INSTRUCTIONS =
  'Upload a new file for this requirement on your application tracker.';

function resetApplicantNoticeDedupe() {
  inflightSends.clear();
}

function normalizeRecipient(email) {
  const value = String(email || '').trim();
  if (!value || value.length > 254 || !EMAIL_RE.test(value)) return '';
  return value;
}

function shouldNotifyDocumentDecision(previousStatus, nextStatus) {
  if (previousStatus === nextStatus) return false;
  return nextStatus === 'document_approved' || nextStatus === 'document_declined';
}

function documentDecisionCopy(status) {
  if (status === 'document_approved') {
    return {
      decision: 'Approved',
      nextStep:
        'Open your application tracker. HR will assign your next form before the exam.',
    };
  }
  return {
    decision: 'Declined',
    nextStep:
      'Open your application tracker, replace the declined documents, and resubmit them.',
  };
}

function scheduleChanged(previousAt, nextAt) {
  if (nextAt == null || nextAt === '') return false;
  const next = new Date(nextAt);
  if (Number.isNaN(next.getTime())) return false;
  if (previousAt == null || previousAt === '') return true;
  const previous = new Date(previousAt);
  if (Number.isNaN(previous.getTime())) return true;
  return previous.getTime() !== next.getTime();
}

function formatScheduleAt(value) {
  const when = new Date(value);
  if (Number.isNaN(when.getTime())) return '';
  const zone = (process.env.HRMS_TIMEZONE || 'Asia/Manila').trim() || 'Asia/Manila';
  return new Intl.DateTimeFormat('en-PH', {
    timeZone: zone,
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(when);
}

function scheduleCopy(eventName) {
  if (eventName === 'Orientation') {
    return 'Please arrive on time for your orientation. Open your application tracker for the latest status.';
  }
  return 'Please arrive on time for your deliberation. Open your application tracker for the latest status.';
}

function revisionIsNew(previousStatus, previousComment, nextComment) {
  const comment = String(nextComment || '').trim();
  return !(
    previousStatus === 'needs_revision' &&
    String(previousComment || '').trim() === comment
  );
}

function actionCopy(formKey, mode, comment) {
  const actionTitle = ACTION_TITLES[formKey];
  if (!actionTitle) return null;
  if (mode === 'revision') {
    return {
      actionTitle,
      actionDetail:
        'HR returned this form for revision. Update it and submit it again on your application tracker.',
      hrComment: String(comment || '').trim(),
    };
  }
  return {
    actionTitle,
    actionDetail: 'HR assigned this form. Open your application tracker and complete it.',
    hrComment: '',
  };
}

function safeErrorCode(err) {
  const code = err?.code || err?.httpStatus || 'EMAIL_FAILED';
  return String(code).replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[redacted]').slice(0, 80);
}

function logSkip(kind, applicationId, reason) {
  console.warn('[rspApplicantNotices] skipped', { kind, applicationId, reason });
}

function logFailure(kind, applicationId, err) {
  console.error('[rspApplicantNotices] failed', {
    kind,
    applicationId,
    code: safeErrorCode(err),
  });
}

function beginSend(key) {
  if (inflightSends.has(key)) return false;
  inflightSends.set(key, true);
  return true;
}

async function loadApplicant(applicationId) {
  const result = await pool.query(
    `SELECT email, full_name, applicant_number, position_applied_for
     FROM public.recruitment_applications
     WHERE id = $1`,
    [applicationId],
  );
  return result.rows[0] || null;
}

function personFields(row) {
  return {
    to: normalizeRecipient(row?.email),
    applicantName: String(row?.full_name || '').trim() || 'Applicant',
    applicationNumber: String(row?.applicant_number || '').trim(),
    position: String(row?.position_applied_for || '').trim(),
  };
}

async function resolvePerson(applicationId, applicant) {
  if (applicant && applicant.email != null) return personFields(applicant);
  const row = await loadApplicant(applicationId);
  return personFields(row);
}

async function deliver(kind, applicationId, key, send) {
  if (!beginSend(key)) {
    logSkip(kind, applicationId, 'duplicate');
    return { sent: false, reason: 'duplicate' };
  }
  try {
    await send();
    return { sent: true };
  } catch (err) {
    logFailure(kind, applicationId, err);
    return { sent: false, reason: 'delivery_failed' };
  } finally {
    inflightSends.delete(key);
  }
}

async function notifyDocumentDecision({
  applicationId,
  previousStatus,
  nextStatus,
  applicant,
}) {
  try {
    if (!shouldNotifyDocumentDecision(previousStatus, nextStatus)) {
      return { sent: false, reason: 'unchanged' };
    }
    const person = await resolvePerson(applicationId, applicant);
    if (!person.to) {
      logSkip('document-decision', applicationId, 'invalid_recipient');
      return { sent: false, reason: 'invalid_recipient' };
    }
    const copy = documentDecisionCopy(nextStatus);
    return deliver(
      'document-decision',
      applicationId,
      `decision:${applicationId}:${nextStatus}`,
      () => sendRspDocumentDecisionEmailJs({
        to: person.to,
        applicantName: person.applicantName,
        applicationNumber: person.applicationNumber,
        position: person.position,
        decision: copy.decision,
        nextStep: copy.nextStep,
      }),
    );
  } catch (err) {
    logFailure('document-decision', applicationId, err);
    return { sent: false, reason: 'delivery_failed' };
  }
}

async function notifyScheduleNotice({
  applicationId,
  eventName,
  previousAt,
  nextAt,
  applicant,
}) {
  try {
    if (!scheduleChanged(previousAt, nextAt)) {
      return { sent: false, reason: 'unchanged' };
    }
    const scheduleAt = formatScheduleAt(nextAt);
    if (!scheduleAt) return { sent: false, reason: 'unchanged' };
    const person = await resolvePerson(applicationId, applicant);
    if (!person.to) {
      logSkip('schedule-notice', applicationId, 'invalid_recipient');
      return { sent: false, reason: 'invalid_recipient' };
    }
    const label = eventName === 'Orientation' ? 'Orientation' : 'Deliberation';
    return deliver(
      'schedule-notice',
      applicationId,
      `schedule:${applicationId}:${label}:${new Date(nextAt).toISOString()}`,
      () => sendRspScheduleNoticeEmailJs({
        to: person.to,
        applicantName: person.applicantName,
        applicationNumber: person.applicationNumber,
        position: person.position,
        eventName: label,
        scheduleAt,
        instructions: scheduleCopy(label),
      }),
    );
  } catch (err) {
    logFailure('schedule-notice', applicationId, err);
    return { sent: false, reason: 'delivery_failed' };
  }
}

async function notifyActionRequired({
  applicationId,
  formKey,
  mode,
  comment,
  applicant,
}) {
  try {
    const copy = actionCopy(formKey, mode, comment);
    if (!copy) return { sent: false, reason: 'unsupported_form' };
    const person = await resolvePerson(applicationId, applicant);
    if (!person.to) {
      logSkip('action-required', applicationId, 'invalid_recipient');
      return { sent: false, reason: 'invalid_recipient' };
    }
    const commentKey = mode === 'revision' ? `:${copy.hrComment}` : '';
    return deliver(
      'action-required',
      applicationId,
      `action:${applicationId}:${mode}:${formKey}${commentKey}`,
      () => sendRspActionRequiredEmailJs({
        to: person.to,
        applicantName: person.applicantName,
        applicationNumber: person.applicationNumber,
        position: person.position,
        actionTitle: copy.actionTitle,
        actionDetail: copy.actionDetail,
        hrComment: copy.hrComment,
      }),
    );
  } catch (err) {
    logFailure('action-required', applicationId, err);
    return { sent: false, reason: 'delivery_failed' };
  }
}

async function notifyFinalRequirementReturned({
  applicationId,
  documentKind,
  reason,
  applicant,
}) {
  try {
    const documentName = FINAL_DOCUMENT_NAMES[documentKind];
    if (!documentName) return { sent: false, reason: 'unsupported_document' };
    const person = await resolvePerson(applicationId, applicant);
    if (!person.to) {
      logSkip('final-requirement-returned', applicationId, 'invalid_recipient');
      return { sent: false, reason: 'invalid_recipient' };
    }
    const recordedReason = String(reason || '').trim();
    return deliver(
      'final-requirement-returned',
      applicationId,
      `final:${applicationId}:${documentKind}:${recordedReason}`,
      () => sendRspFinalRequirementReturnedEmailJs({
        to: person.to,
        applicantName: person.applicantName,
        applicationNumber: person.applicationNumber,
        position: person.position,
        documentName,
        reason: recordedReason,
        instructions: FINAL_REQUIREMENT_INSTRUCTIONS,
      }),
    );
  } catch (err) {
    logFailure('final-requirement-returned', applicationId, err);
    return { sent: false, reason: 'delivery_failed' };
  }
}

async function safeNotify(work) {
  try {
    return await work();
  } catch (err) {
    logFailure('unexpected', null, err);
    return { sent: false, reason: 'delivery_failed' };
  }
}

module.exports = {
  resetApplicantNoticeDedupe,
  shouldNotifyDocumentDecision,
  documentDecisionCopy,
  scheduleChanged,
  formatScheduleAt,
  revisionIsNew,
  actionCopy,
  notifyDocumentDecision,
  notifyScheduleNotice,
  notifyActionRequired,
  notifyFinalRequirementReturned,
  safeNotify,
  FINAL_REQUIREMENT_INSTRUCTIONS,
};
