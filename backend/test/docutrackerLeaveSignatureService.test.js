const test = require('node:test');
const assert = require('node:assert/strict');

const {
  canApplicantSignStatus,
  canDepartmentHeadSignStatus,
  canHrApproverSignStatus,
  getLeaveSourceSignatures,
  signLeaveSourceApplicant,
  requireDepartmentHeadApprovalSignature,
  requireHrApprovalSignature,
} = require('../src/services/docutrackerLeaveSignatureService');

const leaveId = '11111111-1111-4111-8111-111111111111';
const employeeId = '22222222-2222-4222-8222-222222222222';
const assetId = '33333333-3333-4333-8333-333333333333';
const departmentHeadId = '44444444-4444-4444-8444-444444444444';

test('applicant signature remains replaceable while leave is under active review', () => {
  assert.equal(canApplicantSignStatus('draft'), true);
  assert.equal(canApplicantSignStatus('returned'), true);
  assert.equal(canApplicantSignStatus('pending_department_head'), true);
  assert.equal(canApplicantSignStatus('pending_hr'), true);
  assert.equal(canApplicantSignStatus('approved'), false);
  assert.equal(canApplicantSignStatus('rejected_by_hr'), false);
  assert.equal(canApplicantSignStatus('cancelled'), false);
});

test('department head can sign only while their review is pending', () => {
  assert.equal(canDepartmentHeadSignStatus('pending_department_head'), true);
  assert.equal(canDepartmentHeadSignStatus('pending_hr'), false);
  assert.equal(canDepartmentHeadSignStatus('approved'), false);
});

test('HR approver can sign only while final review is pending', () => {
  assert.equal(canHrApproverSignStatus('pending_hr'), true);
  assert.equal(canHrApproverSignStatus('pending'), true);
  assert.equal(canHrApproverSignStatus('pending_department_head'), false);
  assert.equal(canHrApproverSignStatus('approved'), false);
});

test('owner sees an unsigned applicant slot with server signing capability', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM leave_requests lr')) {
        return {
          rowCount: 1,
          rows: [{
            id: leaveId,
            status: 'draft',
            employee_user_id: employeeId,
            employee_name: 'Employee One',
            assigned_department_head_id: null,
            is_snapshotted_reviewer: false,
            was_department_reviewer: false,
          }],
        };
      }
      if (sql.includes('FROM docutracker_leave_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getLeaveSourceSignatures(
    pool,
    { id: employeeId, role: 'employee' },
    'dtr',
    'leave_requests',
    leaveId
  );

  assert.equal(result.signatures.length, 3);
  assert.equal(result.signatures[0].slot_key, 'applicant');
  assert.equal(result.signatures[0].can_sign, true);
  assert.equal(result.signatures[0].signature_asset_id, null);
});

test('assigned head sees a signable department head slot', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM leave_requests lr')) {
        return {
          rowCount: 1,
          rows: [{
            id: leaveId,
            status: 'pending_department_head',
            employee_user_id: employeeId,
            employee_name: 'Employee One',
            assigned_department_head_id: departmentHeadId,
            department_head_name: 'Department Head One',
            is_snapshotted_reviewer: true,
            was_department_reviewer: false,
          }],
        };
      }
      if (sql.includes('FROM docutracker_leave_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getLeaveSourceSignatures(
    pool,
    { id: departmentHeadId, role: 'employee' },
    'dtr',
    'leave_requests',
    leaveId
  );
  const signature = result.signatures.find(
    (item) => item.slot_key === 'department_head'
  );

  assert.equal(signature.can_sign, true);
  assert.equal(signature.assigned_signer_id, departmentHeadId);
  assert.equal(signature.assigned_signer_name, 'Department Head One');
});

test('an HR applicant does not see a signable final approval slot', async () => {
  const pool = {
    async query(sql) {
      if (sql.includes('FROM leave_requests lr')) {
        return { rowCount: 1, rows: [{
          id: leaveId,
          status: 'pending_hr',
          employee_user_id: employeeId,
          employee_name: 'HR Applicant',
          assigned_department_head_id: null,
          is_snapshotted_reviewer: false,
          was_department_reviewer: false,
        }] };
      }
      if (sql.includes('FROM docutracker_leave_signatures s')) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
  const result = await getLeaveSourceSignatures(
    pool, { id: employeeId, role: 'admin' }, 'dtr', 'leave_requests', leaveId
  );
  assert.equal(result.signatures.find((item) => item.slot_key === 'hr_approver').can_sign, false);
});

test('department head approval requires that same reviewer signature', async () => {
  await assert.rejects(
    requireDepartmentHeadApprovalSignature(
      { query: async () => ({ rowCount: 0, rows: [] }) },
      leaveId,
      departmentHeadId
    ),
    (error) => error.code === 'CONFLICT' && error.statusCode === 409
  );

  await requireDepartmentHeadApprovalSignature(
    { query: async () => ({ rowCount: 1, rows: [{ '?column?': 1 }] }) },
    leaveId,
    departmentHeadId
  );
});

test('HR approval requires that same reviewer signature', async () => {
  await assert.rejects(
    requireHrApprovalSignature(
      { query: async () => ({ rowCount: 0, rows: [] }) },
      leaveId,
      departmentHeadId
    ),
    (error) => error.code === 'CONFLICT' && error.statusCode === 409
  );

  await requireHrApprovalSignature(
    { query: async () => ({ rowCount: 1, rows: [{ '?column?': 1 }] }) },
    leaveId,
    departmentHeadId
  );
});

test('unrelated user cannot read a linked leave signature', async () => {
  const pool = {
    async query() {
      return {
        rowCount: 1,
        rows: [{
          id: leaveId,
          status: 'draft',
          employee_user_id: employeeId,
          employee_name: 'Employee One',
          assigned_department_head_id: null,
          is_snapshotted_reviewer: false,
          was_department_reviewer: false,
        }],
      };
    },
  };

  await assert.rejects(
    getLeaveSourceSignatures(
      pool,
      { id: '44444444-4444-4444-8444-444444444444', role: 'employee' },
      'dtr',
      'leave_requests',
      leaveId
    ),
    (error) => error.code === 'FORBIDDEN'
  );
});

test('applicant signing uses only an owned asset and appends leave audit history', async () => {
  let historyParams;
  const leaveContext = {
    id: leaveId,
    status: 'pending_department_head',
    employee_user_id: employeeId,
    employee_name: 'Employee One',
    assigned_department_head_id: null,
    is_snapshotted_reviewer: false,
    was_department_reviewer: false,
  };
  const client = {
    async query(sql, params = []) {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('FROM leave_requests lr')) {
        return { rowCount: 1, rows: [leaveContext] };
      }
      if (sql.includes('FROM docutracker_signature_assets')) {
        return { rowCount: 1, rows: [{ id: assetId }] };
      }
      if (sql.includes('FROM users')) {
        return { rowCount: 1, rows: [{ full_name: 'Employee One' }] };
      }
      if (sql.includes('SELECT id, signature_asset_id')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('INSERT INTO docutracker_leave_signatures')) {
        return { rowCount: 1, rows: [] };
      }
      if (sql.includes('INSERT INTO leave_request_history')) {
        historyParams = params;
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected transaction query: ${sql}`);
    },
    release() {},
  };
  const pool = {
    async connect() {
      return client;
    },
    async query(sql) {
      if (sql.includes('FROM leave_requests lr')) {
        return { rowCount: 1, rows: [leaveContext] };
      }
      if (sql.includes('FROM docutracker_leave_signatures s')) {
        return {
          rowCount: 1,
          rows: [{
            id: '55555555-5555-4555-8555-555555555555',
            slot_key: 'applicant',
            signature_asset_id: assetId,
            signed_by: employeeId,
            signer_name_snapshot: 'Employee One',
            signed_at: new Date('2026-09-13T01:00:00.000Z'),
            mime_type: 'image/png',
            signature_image_base64: 'aW1hZ2U=',
          }],
        };
      }
      throw new Error(`Unexpected response query: ${sql}`);
    },
  };

  const result = await signLeaveSourceApplicant(
    pool,
    { id: employeeId, role: 'employee' },
    'dtr',
    'leave_requests',
    leaveId,
    { signature_asset_id: assetId }
  );

  assert.equal(result.signatures[0].signature_asset_id, assetId);
  assert.equal(historyParams[1], 'signed');
  assert.equal(historyParams[3], employeeId);
});
