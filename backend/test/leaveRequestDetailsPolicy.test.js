const test = require('node:test');
const assert = require('node:assert/strict');

const {
  employeeLeaveDetailsFromPayload,
  loadEmployeeOfficialSnapshot,
  sanitizeEmployeeLeaveDetails,
} = require('../src/services/leaveRequestDetailsPolicy');

const USER_ID = '00000000-0000-0000-0000-000000000101';

test('employee leave details keep filing fields and remove official or HR-owned values', () => {
  const sanitized = sanitizeEmployeeLeaveDetails({
    location_option: 'withinPhilippines',
    location_details: 'Cebu City',
    expected_delivery_date: '2026-09-15',
    commutation: 'requested',
    employee_name: 'Forged Employee',
    office_department: 'Office of the Mayor',
    position_title: 'Department Head',
    salary: 999999,
    status: 'approved',
    recommendation_remarks: 'Recommended for approval',
    disapproval_reason: 'Forged review',
    approved_days_with_pay: 10,
    reviewer_id: USER_ID,
    attachment_path: '../../secret.pdf',
    unknown_field: 'not part of the leave form',
    vawc_case_details: { nested: 'objects are not accepted' },
  });

  assert.deepEqual(sanitized, {
    location_option: 'withinPhilippines',
    location_details: 'Cebu City',
    expected_delivery_date: '2026-09-15',
    commutation: 'requested',
  });
});

test('nested details and flat form fields pass through the same whitelist', () => {
  const sanitized = employeeLeaveDetailsFromPayload({
    rest: {
      sick_leave_nature: 'outPatient',
      sick_illness_details: 'Medical consultation',
      salary: 50000,
    },
    details: {
      sick_illness_details: 'Updated medical consultation',
      hr_remarks: 'Approved',
    },
  });

  assert.deepEqual(sanitized, {
    sick_leave_nature: 'outPatient',
    sick_illness_details: 'Updated medical consultation',
  });
});

test('official leave snapshot comes only from server employee and assignment records', async () => {
  let capturedSql = '';
  const db = {
    async query(sql, params) {
      capturedSql = String(sql);
      assert.deepEqual(params, [USER_ID, null]);
      return {
        rows: [{
          full_name: 'Maria Santos',
          salary_grade: '25,000.50',
          department_name: 'Accounting',
          position_name: 'Administrative Aide',
          date_filed: '2026-08-06',
        }],
      };
    },
  };

  const snapshot = await loadEmployeeOfficialSnapshot(db, USER_ID);

  assert.deepEqual(snapshot, {
    employee_name: 'Maria Santos',
    office_department: 'Accounting',
    position_title: 'Administrative Aide',
    salary: 25000.5,
    date_filed: '2026-08-06',
  });
  assert.match(capturedSql, /a\.effective_from/);
  assert.match(capturedSql, /a\.effective_to/);
  assert.doesNotMatch(capturedSql, /a\.is_active/i);
});
