'use strict';
const {dateOnly} = require('./holidayOverlay');
const {todayInHrmsTimezone} = require('../utils/dateRangeParser');
const {canAdjustLeaveCredits} = require('./leaveCreditAdjustmentEligibility');
const {lockEmployeeLeaveFiling} = require('./leaveFilingLock');
const {insertLeaveBalanceLedger} = require('./leaveBalanceLedger');
const CREDIT_TYPES = ['sickLeave','vacationLeave'];
function fail(message, statusCode = 400) { throw Object.assign(new Error(message), {statusCode}); }
function amount(value) {
  if (!['number','string'].includes(typeof value)) fail('Enter numeric credit days.');
  if (!/^\d+(\.\d{1,3})?$/.test(String(value ?? '').trim())) fail('Enter non-negative credit days with up to three decimal places.');
  const result = Number(value);
  if (!Number.isFinite(result) || result > 9999999) fail('Credit days are out of range.');
  return result;
}
function cutoffDate(value, today) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail('Enter a valid balance cutoff date.');
  const parsed = new Date(value+'T00:00:00Z');
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0,10) !== value) fail('Enter a valid balance cutoff date.');
  parsed.setUTCDate(parsed.getUTCDate()+1);
  if (parsed.getUTCDate() !== 1 || value >= today.slice(0,7)+'-01') fail('The opening cutoff must be the last day of a completed month.');
  return value;
}
function assertQualifyingUsagePeriod(days, cutoffValue, hireValue) {
  const cutoff = dateOnly(cutoffValue);
  const yearStart = `${cutoff.slice(0,4)}-01-01`;
  const hired = dateOnly(hireValue);
  const start = hired && hired > yearStart ? hired : yearStart;
  // Opening usage can predate imported assignment/schedule history. Calendar
  // days provide a hard ceiling without inventing a historical work schedule.
  const maxDays = Math.max(0, Math.floor((Date.parse(`${cutoff}T00:00:00Z`) -
    Date.parse(`${start}T00:00:00Z`)) / 86400000) + 1);
  if (!Number.isFinite(maxDays)) fail('Unable to determine the historical qualifying usage period.');
  if (days > maxDays) fail(`Historical qualifying leave cannot exceed ${maxDays} calendar days for ${start} through ${cutoff}.`);
}
async function loadOpeningBalanceCutoffs(db, ids) {
  if (!ids.length) return new Map();
  const result = await db.query('SELECT user_id, cutoff_date FROM leave_opening_balance_setups WHERE user_id = ANY($1::uuid[])', [[...new Set(ids.map(String))]]);
  return new Map(result.rows.filter(r=>r.user_id && r.cutoff_date).map(r=>[String(r.user_id),dateOnly(r.cutoff_date)]));
}
async function assertAfterOpeningBalanceCutoff(db, userId, startDate) {
  const cutoff = (await loadOpeningBalanceCutoffs(db,[userId])).get(String(userId));
  if (cutoff && dateOnly(startDate) <= cutoff) fail('These dates are already covered by the opening balance. Do not record them as a new leave deduction.',409);
}
/** Caller owns the transaction; no employee balances are changed outside it. */
async function applyOpeningBalances(db, input, {today = todayInHrmsTimezone()} = {}) {
  if (!input.actor?.id || !['hr','admin'].includes(input.actor.role)) fail('HR or administrator access is required.',403);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.userId || '')) fail('Select a valid employee.');
  const cutoff = cutoffDate(input.cutoff_date,today);
  const amounts = {sickLeave:amount(input.sick_leave_days),vacationLeave:amount(input.vacation_leave_days)};
  const qualifyingDays = amount(input.qualifying_leave_days);
  const reason = String(input.reason || '').trim();
  if (!reason || reason.length > 500) fail('Enter the verified source/reason (up to 500 characters).');
  if (input.confirmed !== true) fail('Confirm both balances include all accruals and deductions through the cutoff.');
  // Month-end services hold a shared transaction lock on the same key.
  await db.query('SELECT pg_advisory_xact_lock(743022, 0)');
  await lockEmployeeLeaveFiling(db,input.userId);
  const employee=(await db.query(`SELECT id,role,employment_type,leave_credit_eligible,is_active,employment_status,date_hired
    FROM users WHERE id=$1::uuid FOR SHARE`,[input.userId])).rows[0];
  if (!employee || employee.role === 'super_admin' || employee.is_active === false ||
      !['active',''].includes(String(employee.employment_status || 'active').toLowerCase()) || !canAdjustLeaveCredits(employee)) fail('Select an active employee eligible for leave credits.');
  if (employee.date_hired && dateOnly(employee.date_hired)>cutoff) fail('The cutoff cannot be earlier than the employee’s hire date.');
  assertQualifyingUsagePeriod(qualifyingDays,cutoff,employee.date_hired);
  const existing=await db.query('SELECT user_id,cutoff_date FROM leave_opening_balance_setups WHERE user_id=$1::uuid',[input.userId]);
  if (existing.rows.length) fail('Opening balances are already recorded. Use Manual balance adjustment for later corrections.',409);
  await db.query(`INSERT INTO leave_balances (user_id,leave_type,earned_days,used_days,pending_days,adjusted_days,as_of_date)
    SELECT $1::uuid,t,0,0,0,0,$2::date FROM unnest($3::text[]) t
    ON CONFLICT (user_id,leave_type) DO NOTHING`,[input.userId,cutoff,CREDIT_TYPES]);
  const rows=(await db.query(`SELECT leave_type,earned_days,used_days,pending_days,adjusted_days,last_accrual_date
    FROM leave_balances WHERE user_id=$1::uuid AND leave_type=ANY($2::text[]) ORDER BY leave_type FOR UPDATE`,[input.userId,CREDIT_TYPES])).rows;
  if (rows.length !== 2) throw new Error('Could not lock both leave credit balances.');
  if (rows.some(r=>Number(r.pending_days)>0)) fail('Resolve pending leave reservations before recording opening balances.',409);
  if (rows.some(r=>dateOnly(r.last_accrual_date)>cutoff)) fail('Credits have already accrued after this cutoff. Choose the latest completed accounting period.',409);
  const requests=await db.query(`SELECT lr.id FROM leave_requests lr JOIN leave_types lt ON lt.id=lr.leave_type_id
    WHERE (lr.user_id=$1::uuid OR lr.employee_id=$1::uuid) AND lr.discarded_at IS NULL
      AND lt.balance_ledger_type IN ('vacationLeave','sickLeave')
      AND (lr.status IN ('pending','pending_department_head','pending_hr','pending_mayor')
        OR (lr.status='approved' AND lr.end_date>$2::date)) LIMIT 1`,[input.userId,cutoff]);
  if (requests.rows.length) fail('Resolve pending leave or approved leave after the cutoff before opening setup.',409);
  const later=await db.query(`SELECT user_id FROM leave_attendance_deductions WHERE user_id=$1::uuid AND service_month>$2::date
    UNION ALL SELECT user_id FROM leave_monthly_accrual_postings WHERE user_id=$1::uuid AND service_month>$2::date LIMIT 1`,[input.userId,cutoff]);
  if (later.rows.length) fail('Month-end processing exists after this cutoff. Choose a later completed accounting period.',409);
  const balances=[];
  for (const row of rows) {
    const adjusted = Math.round((amounts[row.leave_type]-Number(row.earned_days)+Number(row.used_days)+Number(row.pending_days))*1000)/1000;
    const saved=(await db.query(`UPDATE leave_balances SET adjusted_days=$3::numeric,last_accrual_date=$4::date,
      as_of_date=$5::date,updated_at=now() WHERE user_id=$1::uuid AND leave_type=$2::text RETURNING *`,
      [input.userId,row.leave_type,adjusted,cutoff.slice(0,7)+'-01',cutoff])).rows[0];
    await insertLeaveBalanceLedger(db,{userId:input.userId,leaveType:row.leave_type,action:'opening_balance',affectedBucket:'adjusted',
      daysChanged:Math.round((adjusted-Number(row.adjusted_days))*1000)/1000,oldValue:Number(row.adjusted_days),newValue:adjusted,
      actorUserId:input.actor.id,actorKind:input.actor.role,remarks:reason,
      metadataJson:{cutoff_date:cutoff,verified_available_days:amounts[row.leave_type],before:row,after:saved}});
    balances.push(saved);
  }
  const setup=(await db.query(`INSERT INTO leave_opening_balance_setups
    (user_id,cutoff_date,sick_leave_days,vacation_leave_days,reason,created_by,
     qualifying_leave_days,usage_reference,usage_verified_by,usage_verified_at)
    VALUES ($1::uuid,$2::date,$3::numeric,$4::numeric,$5::text,$6::uuid,$7::numeric,$5::text,$6::uuid,now()) RETURNING *`,
    [input.userId,cutoff,amounts.sickLeave,amounts.vacationLeave,reason,input.actor.id,qualifyingDays])).rows[0];
  return {setup:{...setup,cutoff_date:cutoff},balances};
}
async function verifyOpeningUsage(db,input) {
  if (!input.actor?.id || !['hr','admin'].includes(input.actor.role)) fail('HR or administrator access is required.',403);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.userId || '')) fail('Select a valid employee.');
  const days=amount(input.qualifying_leave_days);
  const reference=String(input.reference || '').trim();
  if (!reference || reference.length>500 || input.confirmed!==true) fail('Verify the qualifying days and provide the HR source reference (up to 500 characters).');
  await db.query('SELECT pg_advisory_xact_lock(743022, 0)');
  await lockEmployeeLeaveFiling(db,input.userId);
  const setup=(await db.query(`SELECT opening.cutoff_date,opening.qualifying_leave_days,employee.date_hired
    FROM leave_opening_balance_setups opening JOIN users employee ON employee.id=opening.user_id
    WHERE opening.user_id=$1::uuid FOR UPDATE OF opening FOR SHARE OF employee`,[input.userId])).rows[0];
  if (!setup) fail('Opening balances have not been recorded.',404);
  if (dateOnly(setup.cutoff_date)!==input.cutoff_date) fail('The cutoff changed. Reload the employee before verifying usage.',409);
  if (setup.qualifying_leave_days!=null) fail('Historical usage is already verified.',409);
  assertQualifyingUsagePeriod(days,setup.cutoff_date,setup.date_hired);
  const saved=(await db.query(`UPDATE leave_opening_balance_setups SET qualifying_leave_days=$2::numeric,
    usage_reference=$3,usage_verified_by=$4::uuid,usage_verified_at=now() WHERE user_id=$1::uuid RETURNING *`,
    [input.userId,days,reference,input.actor.id])).rows[0];
  return {setup:saved};
}
module.exports={applyOpeningBalances,loadOpeningBalanceCutoffs,assertAfterOpeningBalanceCutoff,verifyOpeningUsage};
