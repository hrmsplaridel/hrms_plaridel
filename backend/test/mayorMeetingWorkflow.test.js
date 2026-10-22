const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  canStaffSubmitMeetingRequest,
  canMayorDecideMeeting,
  canStaffRecordAttendance,
  canMayorEndorse,
  normalizeMeetingRequestStatus,
} = require('../src/services/mayorMeetingWorkflow');

test('normalizeMeetingRequestStatus defaults unknown to none', () => {
  assert.equal(normalizeMeetingRequestStatus('submitted'), 'submitted');
  assert.equal(normalizeMeetingRequestStatus('bogus'), 'none');
});

test('staff can submit meeting request from none/reschedule/declined/no_show', () => {
  assert.equal(
    canStaffSubmitMeetingRequest({ status: 'pending', meeting_request_status: 'none' }).ok,
    true,
  );
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'pending',
      meeting_request_status: 'reschedule_requested',
    }).ok,
    true,
  );
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'pending',
      meeting_request_status: 'declined',
    }).ok,
    true,
  );
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'pending',
      meeting_request_status: 'approved',
      appointment_status: 'no_show',
    }).ok,
    true,
  );
});

test('staff cannot submit while meeting already submitted or approved', () => {
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'pending',
      meeting_request_status: 'submitted',
    }).ok,
    false,
  );
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'pending',
      meeting_request_status: 'approved',
      appointment_status: 'scheduled',
    }).ok,
    false,
  );
  assert.equal(
    canStaffSubmitMeetingRequest({
      status: 'endorsed',
      meeting_request_status: 'none',
    }).status,
    409,
  );
});

test('mayor can decide only submitted meetings', () => {
  assert.equal(
    canMayorDecideMeeting({ status: 'pending', meeting_request_status: 'submitted' }).ok,
    true,
  );
  assert.equal(
    canMayorDecideMeeting({ status: 'pending', meeting_request_status: 'approved' }).ok,
    false,
  );
});

test('attendance requires approved meeting and rejects duplicates', () => {
  assert.equal(
    canStaffRecordAttendance(
      {
        status: 'pending',
        meeting_request_status: 'approved',
        appointment_status: 'scheduled',
      },
      'met',
    ).ok,
    true,
  );
  assert.equal(
    canStaffRecordAttendance(
      {
        status: 'pending',
        meeting_request_status: 'submitted',
        appointment_status: 'scheduled',
      },
      'met',
    ).ok,
    false,
  );
  assert.equal(
    canStaffRecordAttendance(
      {
        status: 'pending',
        meeting_request_status: 'approved',
        appointment_status: 'completed',
      },
      'met',
    ).status,
    409,
  );
});

test('endorse requires completed attendance on pending rows', () => {
  assert.equal(
    canMayorEndorse({ status: 'pending', appointment_status: 'completed' }).ok,
    true,
  );
  assert.equal(
    canMayorEndorse({ status: 'pending', appointment_status: 'scheduled' }).ok,
    false,
  );
  assert.equal(
    canMayorEndorse({ status: 'mayor_approved', appointment_status: 'none' }).ok,
    true,
  );
  assert.equal(canMayorEndorse({ status: 'endorsed' }).status, 409);
});

test('meeting approve does not imply endorsement status change in helpers', () => {
  // Decline/approve meeting helpers only validate meeting_request_status.
  const row = { status: 'pending', meeting_request_status: 'submitted' };
  assert.equal(canMayorDecideMeeting(row).ok, true);
  assert.equal(row.status, 'pending');
});

test('routes wire Phase 3 meeting and endorse endpoints with role guards', () => {
  const src = fs.readFileSync(
    path.join(__dirname, '../src/routes/mayorEndorsements.js'),
    'utf8',
  );
  assert.match(src, /router\.post\('\/:id\/meeting-request',\s*staffOpsOnly/);
  assert.match(src, /router\.post\('\/:id\/meeting\/approve',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/meeting\/reschedule',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/meeting\/decline',\s*mayorDecisionOnly/);
  assert.match(src, /router\.post\('\/:id\/endorse',\s*mayorDecisionOnly/);
  assert.match(src, /canStaffRecordAttendance/);
  assert.match(src, /router\.post\('\/:id\/met',\s*endorsementAccess/);
  assert.match(src, /router\.post\('\/:id\/no-show',\s*endorsementAccess/);
  assert.match(src, /meeting_request_submitted/);
  assert.match(src, /meeting_approved/);
  assert.match(src, /Meeting decline does not reject the endorsement/);
});
