'use strict';

const { isValidIsoDate, manilaTodayDate, SEPARATION_EMPLOYMENT_STATUSES } = require('../utils/employeeAccountValidation');
const { normalizeEmployeeSetup, applyEmployeeSetup } = require('./employeeSetupTransaction');
const { lockAndValidateAccountTransition, revokeActiveRefreshTokens } = require('./employeeAccountSecurity');
const { invalidateAttendancePolicyCache } = require('./attendancePolicyCache');
const { enqueueEmployeeRangeReconciliation } = require('./dtrMonthEndReconciliation');
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { statusCode }); };

function validateReturnPayload(payload, today) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) fail('A return-to-service request is required.');
  if (!isValidIsoDate(payload.returned_on) || payload.returned_on > today) fail('Return date must be a valid date on or before today.');
  if (typeof payload.reason !== 'string' || payload.reason.trim().length < 5 || payload.reason.trim().length > 2000) {
    fail('A reason between 5 and 2000 characters is required.');
  }
  if (typeof payload.leave_credit_eligible !== 'boolean') fail('Choose whether leave-credit accrual will resume.');
  for (const field of ['department_id', 'position_id', 'shift_id']) {
    if (!UUID.test(payload.assignment?.[field] || '')) fail('A valid department, position, and shift are required.');
  }
  if (payload.attendance_policy_id != null && !UUID.test(payload.attendance_policy_id)) fail('Select a valid attendance policy.');
  return normalizeEmployeeSetup({ effective_from: payload.returned_on, effective_to: null,
    assignment: payload.assignment,
    policy_assignment: payload.attendance_policy_id ? { attendance_policy_id: payload.attendance_policy_id } : null,
  }, { isActive: true });
}

async function returnEmployeeToService(pool, { employeeId, actorId, payload, today = manilaTodayDate() }) {
  if (!UUID.test(employeeId || '')) fail('Invalid employee ID.');
  const setup = validateReturnPayload(payload, today);
  const client = await pool.connect();
  let transaction = false;
  try {
    await client.query('BEGIN');
    transaction = true;
    // Exclude concurrent month-end postings while the service periods change.
    await client.query('SELECT pg_advisory_xact_lock(743022, 0)');
    await lockAndValidateAccountTransition(client, {
      actorId, targetId: employeeId, nextIsActive: true, nextEmploymentStatus: 'active',
    });
    const previous = (await client.query(
      `SELECT id, role, full_name, employment_status, date_hired::text AS date_hired,
              separation_date::text AS separation_date, last_service_return_date::text AS last_service_return_date,
              leave_credit_eligible_until::text AS leave_credit_eligible_until, employment_type
         FROM users WHERE id=$1::uuid FOR UPDATE`, [employeeId]
    )).rows[0];
    if (!previous) fail('Employee not found.', 404);
    if (!SEPARATION_EMPLOYMENT_STATUSES.has(previous.employment_status)) fail('Only separated employees can return to service.', 409);
    if (!previous.date_hired || !previous.separation_date) fail('Set valid hire and separation dates before returning this employee.', 409);
    if (payload.returned_on <= previous.separation_date) fail('Return date must be after the previous last day of service.');
    if (payload.leave_credit_eligible && ['job_order', 'contract_of_service'].includes(previous.employment_type)) {
      fail('JO/COS employees cannot resume monthly leave-credit accrual through this action.');
    }
    const started = previous.last_service_return_date || previous.date_hired;
    await client.query(
      `INSERT INTO employee_service_returns(employee_id,service_started_on,separated_on,returned_on,
         prior_employment_status,leave_credit_eligible,reason,created_by)
       VALUES($1::uuid,$2::date,$3::date,$4::date,$5,$6,$7,$8::uuid)`,
      [employeeId, started, previous.separation_date, payload.returned_on, previous.employment_status,
        Boolean(previous.leave_credit_eligible_until), payload.reason.trim(), actorId]
    );
    const result = await client.query(
      `UPDATE users SET employment_status='active',is_active=true,separation_date=NULL,
         leave_credit_eligible_until=NULL,leave_credit_eligible=$2,last_service_return_date=$3::date,
         auth_version=auth_version+1,updated_at=now() WHERE id=$1::uuid
       RETURNING id,full_name,employment_status,is_active,date_hired::text AS date_hired,
         separation_date::text AS separation_date,last_service_return_date::text AS last_service_return_date,
         leave_credit_eligible,leave_credit_eligible_until`,
      [employeeId, payload.leave_credit_eligible, payload.returned_on]
    );
    const updatedSetup = await applyEmployeeSetup(client, { employeeId, setup, remarks: `Return to service: ${payload.reason.trim()}` });
    if (payload.returned_on.slice(0, 7) < today.slice(0, 7)) {
      await enqueueEmployeeRangeReconciliation(client, {
        employeeId, dateFrom: payload.returned_on, dateTo: today,
        reason: 'employee_returned_to_service', metadata: { actor_id: actorId },
      });
    }
    await revokeActiveRefreshTokens(client, employeeId);
    await client.query(
      `INSERT INTO audit_logs(user_id,action,entity_type,entity_id,details)
       VALUES($1::uuid,'employee_returned_to_service','employee_account',$2::uuid,$3)`,
      [actorId, employeeId, JSON.stringify({ previous, returned_on: payload.returned_on,
        leave_credit_eligible: payload.leave_credit_eligible, reason: payload.reason.trim(), assignment: updatedSetup.assignment })]
    );
    await client.query('COMMIT');
    transaction = false;
    invalidateAttendancePolicyCache({ employeeId });
    return { ...result.rows[0], updated_setup: updatedSetup };
  } catch (error) {
    if (transaction) await client.query('ROLLBACK');
    if (error.code === '23505' && error.constraint === 'users_single_active_mayor_idx') {
      error.statusCode = 409;
      error.message = 'An active Mayor already exists. Resolve the current Mayor account before returning this employee.';
    }
    throw error;
  } finally { client.release(); }
}

module.exports = { returnEmployeeToService };
