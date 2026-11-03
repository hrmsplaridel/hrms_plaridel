'use strict';
const {applyOpeningBalances,verifyOpeningUsage} = require('../../../services/leaveOpeningBalances');
const {dateOnly} = require('../../../services/holidayOverlay');
module.exports = ({pool,broadcastLeaveUpdated,todayInHrmsTimezone}) => ({
  listOpeningBalances: async(req,res) => {
    try {
      const setups = (await pool.query(`SELECT user_id, to_char(cutoff_date,'YYYY-MM-DD') AS cutoff_date
        FROM leave_opening_balance_setups ORDER BY user_id`)).rows;
      res.json({setups});
    } catch(error) {
      res.status(500).json({error:'Unable to load opening balance recording status.'});
    }
  },
  getOpeningBalances: async(req,res) => {
    try {
      const userId=req.params.userId;
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId))return res.status(400).json({error:'Select a valid employee.'});
      const employee=(await pool.query('SELECT date_hired::text AS date_hired FROM users WHERE id=$1::uuid',[userId])).rows[0];
      if(!employee)return res.status(404).json({error:'Employee not found.'});
      const setup=(await pool.query(`SELECT user_id,to_char(cutoff_date,'YYYY-MM-DD') AS cutoff_date,
        sick_leave_days,vacation_leave_days,reason,created_by,created_at,
        qualifying_leave_days,usage_reference,usage_verified_by,usage_verified_at
        FROM leave_opening_balance_setups WHERE user_id=$1::uuid`,[userId])).rows[0] || null;
      const balances=(await pool.query(`SELECT leave_type,earned_days,used_days,pending_days,adjusted_days,last_accrual_date
        FROM leave_balances WHERE user_id=$1::uuid AND leave_type IN ('sickLeave','vacationLeave')`,[userId])).rows;
      res.json({setup,balances,date_hired:dateOnly(employee.date_hired),official_date:todayInHrmsTimezone()});
    } catch(error) {res.status(500).json({error:'Unable to load opening balance setup.'});}
  },
  saveOpeningBalances: async(req,res) => {
    let client;
    try {
      client=await pool.connect();
      await client.query('BEGIN');
      const result=await applyOpeningBalances(client,{...req.body,userId:req.params.userId,actor:req.user});
      await client.query('COMMIT');
      try { broadcastLeaveUpdated('opening_balance_recorded',{user_id:req.params.userId}); }
      catch(error) { console.error('[leave opening balance broadcast]',error.message); }
      res.status(201).json(result);
    } catch(error) {
      if(client) await client.query('ROLLBACK');
      res.status(error.statusCode || 500).json({error:error.statusCode ? error.message : 'Unable to record opening balances.'});
    } finally {client?.release();}
  },
  verifyOpeningUsage: async(req,res) => {
    let client;
    try {
      client=await pool.connect();await client.query('BEGIN');
      const result=await verifyOpeningUsage(client,{...req.body,userId:req.params.userId,actor:req.user});
      await client.query('COMMIT');
      try {broadcastLeaveUpdated('opening_usage_verified',{user_id:req.params.userId});} catch (_) {}
      res.json(result);
    } catch(error) {
      if(client) await client.query('ROLLBACK');
      res.status(error.statusCode || 500).json({error:error.statusCode ? error.message : 'Unable to verify historical leave usage.'});
    } finally {client?.release();}
  },
});
