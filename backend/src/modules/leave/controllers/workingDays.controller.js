'use strict';
module.exports = function createLeaveControllers({
  computeAnnualQuotaLeavePreview,
  computeEmployeeLeaveWorkingDays,
  getLeaveTypeDefinition,
  pool,
  requiredLeaveDateRangeError,
  serviceEligibility,
  toIsoDateStr,
}) {
  return {
    previewWorkingDays: async (req, res, staffEmployeeId) => {
      const userId = typeof staffEmployeeId === 'string' ? staffEmployeeId : req.user?.id;
      if (!userId) return res.status(401).json({ error: 'Not authenticated' });
      if (typeof staffEmployeeId === 'string' && !/^[0-9a-f-]{36}$/i.test(userId)) return res.status(400).json({error:'Select a valid employee.'});
      const dateError = requiredLeaveDateRangeError(
        req.query.start_date || req.query.startDate,
        req.query.end_date || req.query.endDate,
      );
      if (dateError) return res.status(400).json({ error: dateError });
      const startStr = toIsoDateStr(req.query.start_date || req.query.startDate);
      const endStr = toIsoDateStr(req.query.end_date || req.query.endDate);
      const leaveTypeName = String(req.query.leave_type || req.query.leaveType || '').trim();
      try {
        const result = await computeEmployeeLeaveWorkingDays(pool, userId, startStr, endStr);
        if (result.days == null) {
          return res.status(400).json({ error: 'Invalid date range' });
        }
        const annualEntitlement = leaveTypeName
          ? await computeAnnualQuotaLeavePreview(pool, {
              userId,
              leaveTypeName,
              startStr,
              endStr,
              requestedCountedDates: result.countedDates,
            })
          : null;
        const leaveRule = leaveTypeName ? await getLeaveTypeDefinition(pool, leaveTypeName) : null;
        let service = null;
        if (Number(leaveRule?.minimum_service_months || 0) > 0) {
          const employee = await pool.query(
            'SELECT date_hired::text AS date_hired FROM users WHERE id = $1::uuid LIMIT 1',
            [userId],
          );
          service = serviceEligibility(leaveRule, employee.rows[0]?.date_hired, startStr);
        }
        res.json({
          service_eligibility: service,
          start_date: startStr,
          end_date: endStr,
          working_days_applied: result.days,
          counted_dates: result.countedDates,
          holiday_dates: result.holidayDates || [],
          schedule_source: result.scheduleSource,
          annual_entitlement: annualEntitlement,
        });
      } catch (err) {
        console.error('[leave GET /working-days]', err);
        res.status(500).json({ error: 'Failed to compute working days' });
      }
    },
  };
};
