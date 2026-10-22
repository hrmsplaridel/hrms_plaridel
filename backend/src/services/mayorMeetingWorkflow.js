/**
 * Phase 3 — Mayor meeting-request state helpers (no DB I/O).
 */

const MEETING_REQUEST_STATUSES = Object.freeze([
  'none',
  'submitted',
  'approved',
  'reschedule_requested',
  'declined',
]);

const MEETING_DECISIONS = Object.freeze([
  'approved',
  'declined',
  'reschedule_requested',
]);

function normalizeMeetingRequestStatus(value, fallback = 'none') {
  const v = String(value || '').trim().toLowerCase();
  return MEETING_REQUEST_STATUSES.includes(v) ? v : fallback;
}

/** Staff may submit/revise a meeting request from these statuses. */
function canStaffSubmitMeetingRequest(row) {
  const endorsement = String(row?.status || '').toLowerCase();
  if (endorsement !== 'pending') {
    return {
      ok: false,
      status: 409,
      error: 'Meeting requests are only allowed for pending endorsements.',
    };
  }
  const mrs = normalizeMeetingRequestStatus(row?.meeting_request_status);
  const appt = String(row?.appointment_status || '').toLowerCase();
  if (mrs === 'submitted') {
    return {
      ok: false,
      status: 409,
      error: 'A meeting request is already awaiting Mayor approval.',
    };
  }
  if (mrs === 'approved' && appt !== 'no_show') {
    return {
      ok: false,
      status: 409,
      error:
        'Meeting is already approved. Record attendance or mark no-show before requesting another meeting.',
    };
  }
  // none | reschedule_requested | declined | approved+no_show
  return { ok: true };
}

function canMayorDecideMeeting(row) {
  const mrs = normalizeMeetingRequestStatus(row?.meeting_request_status);
  if (mrs !== 'submitted') {
    return {
      ok: false,
      status: 409,
      error: 'Only submitted meeting requests can be decided by the Mayor.',
    };
  }
  const endorsement = String(row?.status || '').toLowerCase();
  if (endorsement === 'endorsed' || endorsement === 'rejected') {
    return {
      ok: false,
      status: 409,
      error: 'Cannot decide a meeting for a completed endorsement.',
    };
  }
  return { ok: true };
}

function canStaffRecordAttendance(row, outcome) {
  const endorsement = String(row?.status || '').toLowerCase();
  if (endorsement === 'endorsed' || endorsement === 'rejected') {
    return {
      ok: false,
      status: 409,
      error: 'Cannot record attendance on a completed endorsement.',
    };
  }
  const mrs = normalizeMeetingRequestStatus(row?.meeting_request_status);
  if (mrs !== 'approved') {
    return {
      ok: false,
      status: 409,
      error: 'Attendance requires an approved meeting with the Mayor.',
    };
  }
  const appt = String(row?.appointment_status || '').toLowerCase();
  if (appt === 'completed') {
    return {
      ok: false,
      status: 409,
      error: 'Attendance was already recorded for this meeting.',
    };
  }
  if (outcome === 'met') {
    if (appt !== 'scheduled' && appt !== 'no_show') {
      return {
        ok: false,
        status: 409,
        error: 'Mark attendance only after the meeting is approved and scheduled.',
      };
    }
  }
  if (outcome === 'no_show') {
    if (appt !== 'scheduled') {
      return {
        ok: false,
        status: 409,
        error: 'No-show can only be recorded for an approved scheduled meeting.',
      };
    }
  }
  return { ok: true };
}

function canMayorEndorse(row) {
  const endorsement = String(row?.status || '').toLowerCase();
  if (endorsement === 'endorsed') {
    return { ok: false, status: 409, error: 'Request is already endorsed' };
  }
  if (endorsement === 'rejected') {
    return { ok: false, status: 409, error: 'Rejected requests cannot be endorsed' };
  }
  if (endorsement === 'mayor_approved') {
    // Legacy in-flight: prefer approve-form, but allow single endorse as shortcut.
    return { ok: true, legacyMayorApproved: true };
  }
  if (endorsement !== 'pending') {
    return {
      ok: false,
      status: 409,
      error: 'Only pending requests can be endorsed',
    };
  }
  if (String(row?.appointment_status || '').toLowerCase() !== 'completed') {
    return {
      ok: false,
      status: 409,
      error:
        'The applicant must meet the Mayor first. Attendance must be recorded before endorsement.',
    };
  }
  return { ok: true, legacyMayorApproved: false };
}

module.exports = {
  MEETING_REQUEST_STATUSES,
  MEETING_DECISIONS,
  normalizeMeetingRequestStatus,
  canStaffSubmitMeetingRequest,
  canMayorDecideMeeting,
  canStaffRecordAttendance,
  canMayorEndorse,
};
