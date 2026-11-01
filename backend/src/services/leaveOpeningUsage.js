'use strict';
const {dateOnly} = require('./holidayOverlay');
const dates = require('../modules/leave/policies/dates')({});
const workingDays = require('../modules/leave/services/workingDays')({...dates,...require('./holidayRangeUtils')});

function usageBaseline(opening, year) {
  const cutoff = dateOnly(opening?.cutoff_date);
  const applies = !!cutoff && Number(cutoff.slice(0,4)) === Number(year);
  return {cutoff: applies ? cutoff : null,
    used: applies && opening.qualifying_leave_days != null ? Number(opening.qualifying_leave_days) : 0,
    needsReview: applies && opening.qualifying_leave_days == null};
}
async function qualifyingUsage(db, userId, year, opening, requests, countDays=workingDays.workingDaysWithinYear) {
  const baseline = usageBaseline(opening,year);
  let used = baseline.used;
  for (const row of requests) {
    if (row.status !== 'approved') continue;
    let from = dateOnly(row.start_date), to = dateOnly(row.end_date);
    if (!from || !to) continue;
    from = from < `${year}-01-01` ? `${year}-01-01` : from;
    to = to > `${year}-12-31` ? `${year}-12-31` : to;
    if (baseline.cutoff && from <= baseline.cutoff) {
      const next = new Date(baseline.cutoff+'T00:00:00Z');next.setUTCDate(next.getUTCDate()+1);
      from = next.toISOString().slice(0,10);
    }
    if (from > to) continue;
    const days = await countDays(db,userId,from,to,Number(year));
    const stored = row.number_of_days ?? row.total_days;
    used += stored != null && Number.isFinite(Number(stored)) ? Math.min(days,Math.max(0,Number(stored))) : days;
  }
  return {...baseline,used:Math.round(used*1000)/1000};
}
async function loadOpeningUsage(db,userId) {
  return (await db.query(`SELECT cutoff_date,qualifying_leave_days FROM leave_opening_balance_setups WHERE user_id=$1::uuid`,[userId])).rows[0] || null;
}
async function assertOpeningUsageVerified(db,userId,year) {
  if (usageBaseline(await loadOpeningUsage(db,userId),year).needsReview) {
    throw Object.assign(new Error('Verify historical vacation/forced-leave usage in Opening balances before year-end deductions.'),{statusCode:409});
  }
}
module.exports={usageBaseline,qualifyingUsage,loadOpeningUsage,assertOpeningUsageVerified};
