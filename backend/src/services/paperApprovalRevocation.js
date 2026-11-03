'use strict';
const { LOCATOR_REVOKE_WINDOW_MS, normalizeLocatorRevocationReason } = require('./locatorRevocationPolicy');

function evaluatePaperRevocation({status,paperRecord,createdAt,reason,now=new Date(),windowMs=LOCATOR_REVOKE_WINDOW_MS}) {
  if(status !== 'approved')return {ok:false,statusCode:409,code:'paper_not_approved',error:'Only approved paper records can be revoked.'};
  const revocationReason=normalizeLocatorRevocationReason(reason);
  if(!revocationReason)return {ok:false,statusCode:400,code:'paper_revocation_reason_required',error:'A revocation reason between 10 and 1000 characters is required.'};
  const recordedAt=new Date(paperRecord?.encoded_at || createdAt || 'invalid');
  if(!Number.isFinite(recordedAt.getTime()))return {ok:false,statusCode:409,code:'paper_recording_time_missing',error:'The paper recording time is unavailable.'};
  const deadline=new Date(recordedAt.getTime()+windowMs);
  if(now>deadline)return {ok:false,statusCode:409,code:'paper_revoke_window_expired',error:'The three-day revoke period after paper recording has expired.',deadline};
  return {ok:true,revocationReason,deadline};
}

async function assertPaperRevocationActor(db,{actor,employeeId,module}) {
  const denied=()=>Object.assign(new Error('Only authorized HR staff can revoke another employee’s paper record.'),{statusCode:403});
  if(!actor?.id || !['admin','hr'].includes(actor.role) || String(actor.id)===String(employeeId))throw denied();
  const current=(await db.query("SELECT id,role,full_name FROM users WHERE id=$1::uuid AND is_active=true",[actor.id])).rows[0];
  if(!current || current.role!==actor.role)throw denied();
  if(current.role==='admin') {
    const access=await require('../middleware/dtrAccess').loadDtrAccess(actor.id,db);
    if(!access?.[`${module}_allowed`])throw denied();
  }
  return current;
}

async function restorePaperLeaveCredits(db,{requestId,employeeId,actorId,reason,insertLeaveBalanceLedger}) {
  // Use the original ledger buckets, even if today's leave type configuration changed.
  const charges=await db.query(`SELECT leave_type,SUM(days_changed) AS deducted_days
    FROM leave_balance_ledger WHERE related_leave_request_id=$1::uuid AND user_id=$2::uuid
      AND affected_bucket='used' AND action IN ('leave_approved','leave_revoked')
    GROUP BY leave_type HAVING SUM(days_changed)>0 ORDER BY leave_type`,[requestId,employeeId]);
  let restoredDays=0;
  for(const charge of charges.rows) {
    const days=Number(charge.deducted_days);
    const balance=(await db.query(`SELECT used_days FROM leave_balances
      WHERE user_id=$1::uuid AND leave_type=$2::text FOR UPDATE`,[employeeId,charge.leave_type])).rows[0];
    const used=Number(balance?.used_days);
    if(!balance || !Number.isFinite(days) || days<=0 || !Number.isFinite(used) || used+0.000001<days)
      throw Object.assign(new Error('The recorded credit deduction does not match the balance. HR must reconcile it before revoking.'),{statusCode:409});
    await db.query(`UPDATE leave_balances SET used_days=used_days-$3::numeric,updated_at=now()
      WHERE user_id=$1::uuid AND leave_type=$2::text`,[employeeId,charge.leave_type,days]);
    await insertLeaveBalanceLedger(db,{userId:employeeId,leaveType:charge.leave_type,action:'leave_revoked',affectedBucket:'used',
      daysChanged:-days,oldValue:used,newValue:used-days,relatedLeaveRequestId:requestId,actorUserId:actorId,actorKind:'admin',remarks:reason,
      metadataJson:{approval_source:'approved_paper',restored_paid_days:days}});
    restoredDays+=days;
  }
  return {restoredDays};
}

module.exports={evaluatePaperRevocation,assertPaperRevocationActor,restorePaperLeaveCredits};
