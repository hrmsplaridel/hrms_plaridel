'use strict';
module.exports = function createLeaveControllers({
  ENTITLEMENT_BASES,
  annualAllowance,
  applyAdminLeaveBalanceAdjustment,
  broadcastLeaveUpdated,
  buildLeaveBalanceHistoryFilters,
  canAdjustLeaveCredits,
  creditBalanceLabel,
  normalizeEntitlementBasis,
  normalizeSexEligibility,
  pool,
  resolveBalanceLedgerLeaveType,
  serviceEligibility,
  systemLeaveTypeDisplayName,
  toIsoDateStr,
  todayInHrmsTimezone,
  workflowEngine,
  workingDaysWithinYear,
}) {
  return {
    getLedger: async (req, res) => {
      const requesterId = req.user?.id;
      const role = req.user?.role;
      if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
      const isPrivileged = role === 'admin' || role === 'hr';

      const limitRaw = req.query?.limit ? parseInt(String(req.query.limit), 10) : 50;
      const offsetRaw = req.query?.offset ? parseInt(String(req.query.offset), 10) : 0;
      const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 200) : 50;
      const offset = Number.isFinite(offsetRaw) && offsetRaw >= 0 ? offsetRaw : 0;

      const filterUserId = (req.query?.user_id || '').toString().trim() || null;
      const leaveType = (req.query?.leave_type || '').toString().trim() || null;
      const action = (req.query?.action || '').toString().trim() || null;
      const affectedBucket =
        (req.query?.affected_bucket || '').toString().trim().toLowerCase() || null;
      const hideZeroPending = ['1', 'true'].includes(
        String(req.query?.hide_zero_pending || '').toLowerCase(),
      );
      const from = (req.query?.from || req.query?.created_from || '').toString().trim() || null;
      const to = (req.query?.to || req.query?.created_to || '').toString().trim() || null;
      const includeAllUsers = ['1', 'true', 'yes'].includes(
        (req.query?.all_users || req.query?.include_all_users || '')
          .toString()
          .trim()
          .toLowerCase(),
      );

      if (!isPrivileged && filterUserId && filterUserId !== requesterId) {
        return res.status(403).json({ error: 'Not allowed to view ledger for other users' });
      }

      const scopeAllUsers = isPrivileged && includeAllUsers && !filterUserId;
      const scopedUserId = filterUserId || requesterId;

      if (affectedBucket) {
        if (!['earned', 'used', 'pending', 'adjusted'].includes(affectedBucket)) {
          return res.status(400).json({ error: 'Invalid affected_bucket filter' });
        }
      }

      // Summary includes the complete date range and remains stable while the
      // user switches activity buckets. The row list adds that bucket filter.
      const {
        summaryWhereSql,
        summaryParams,
        whereSql,
        params,
        nextParameter: p,
      } = buildLeaveBalanceHistoryFilters({
        scopeAllUsers,
        scopedUserId,
        leaveType,
        action,
        from,
        to,
        affectedBucket,
        hideZeroPending,
      });

      try {
        const [countQ, summaryQ] = await Promise.all([
          pool.query(
            `SELECT count(*)::int AS c FROM leave_balance_ledger l WHERE ${whereSql}`,
            params,
          ),
          pool.query(
            `SELECT
           COALESCE(SUM(CASE
             WHEN LOWER(l.affected_bucket) = 'earned'
                  OR LOWER(l.action) = 'monthly_accrual'
             THEN l.days_changed ELSE 0 END), 0)::float8 AS earned,
           GREATEST(COALESCE(SUM(CASE
             WHEN LOWER(l.affected_bucket) = 'used'
             THEN l.days_changed ELSE 0 END), 0), 0)::float8 AS used,
           GREATEST(COALESCE(SUM(CASE
             WHEN LOWER(l.affected_bucket) = 'pending'
             THEN l.days_changed ELSE 0 END), 0), 0)::float8 AS pending,
           COALESCE(SUM(CASE
             WHEN LOWER(l.affected_bucket) = 'adjusted'
             THEN l.days_changed ELSE 0 END), 0)::float8 AS adjusted
         FROM leave_balance_ledger l
         WHERE ${summaryWhereSql}`,
            summaryParams,
          ),
        ]);
        const total = countQ.rows[0]?.c ?? 0;
        const summary = summaryQ.rows[0] || {};

        const listParams = [...params, limit, offset];
        const limIdx = p;
        const offIdx = p + 1;
        const list = await pool.query(
          `SELECT l.*, u.full_name AS employee_name,
              actor.full_name AS actor_name
       FROM leave_balance_ledger l
       LEFT JOIN users u ON u.id = l.user_id
       LEFT JOIN users actor ON actor.id = l.actor_user_id
       WHERE ${whereSql}
       ORDER BY l.created_at DESC
       LIMIT $${limIdx} OFFSET $${offIdx}`,
          listParams,
        );

        res.json({
          total,
          limit,
          offset,
          summary: {
            earned: Number(summary.earned || 0),
            used: Number(summary.used || 0),
            pending: Number(summary.pending || 0),
            adjusted: Number(summary.adjusted || 0),
          },
          rows: list.rows.map((r) => ({
            id: r.id,
            user_id: r.user_id,
            employee_name: r.employee_name || null,
            leave_type: r.leave_type,
            action: r.action,
            affected_bucket: r.affected_bucket,
            days_changed: r.days_changed != null ? parseFloat(r.days_changed) : 0,
            old_value: r.old_value != null ? parseFloat(r.old_value) : null,
            new_value: r.new_value != null ? parseFloat(r.new_value) : null,
            related_leave_request_id: r.related_leave_request_id,
            actor_user_id: r.actor_user_id,
            actor_name: r.actor_name || null,
            actor_kind: r.actor_kind,
            remarks: r.remarks,
            metadata_json: r.metadata_json,
            created_at: r.created_at,
          })),
        });
      } catch (err) {
        console.error('[leave GET /ledger]', err);
        if (err.code === '42P01') {
          return res.status(503).json({ error: 'Leave ledger table not ready yet' });
        }
        res.status(500).json({ error: 'Failed to fetch leave ledger' });
      }
    },

    getFormCredits: async (req, res) => {
      const viewerId = req.user?.id;
      if (!viewerId) return res.status(401).json({ error: 'Not authenticated' });
      try {
        const privileged = req.user.role === 'admin' || req.user.role === 'hr';
        const access = await pool.query(
          `SELECT lr.id,lr.status,lr.workflow_snapshot,COALESCE(lr.user_id, lr.employee_id) AS employee_id,
              ($2::boolean = true
                OR lr.user_id = $3::uuid OR lr.employee_id = $3::uuid
                OR ($4::boolean AND lr.final_review_route IN ('mayor','mayor_direct'))
                OR (lr.status = 'pending_department_head'
                    AND lr.assigned_department_head_id = $3::uuid)
                OR EXISTS (
                  SELECT 1 FROM leave_request_history h
                  WHERE h.leave_request_id = lr.id AND h.acted_by = $3::uuid
                    AND h.action IN ('department_head_approved',
                      'department_head_rejected', 'department_head_returned')
                )) AS can_view
       FROM leave_requests lr WHERE lr.id = $1::uuid LIMIT 1`,
          [
            req.params.id,
            privileged,
            viewerId,
            await workflowEngine.isCurrentMayor(pool, req.user),
          ],
        );
        const request = access.rows[0];
        if (!request) return res.status(404).json({ error: 'Leave request not found' });
        if (
          (await require('../../../services/sharedWorkflowInbox').pendingReadAccess(
            pool,
            'leave',
            request,
            req.user,
          )) === false
        ) {
          return res.status(403).json({ error: 'Not allowed to view this leave form' });
        }
        if (
          !request.can_view &&
          !(await require('../../../services/leaveWorkflowReadAccess').canReadSharedLeaveRequest(
            pool,
            req.params.id,
            req.user,
          ))
        ) {
          return res.status(403).json({ error: 'Not allowed to view this leave form' });
        }

        const result = await pool.query(
          `SELECT lb.id, lb.user_id, lb.leave_type, lb.earned_days,
              lb.used_days, lb.pending_days, lb.adjusted_days,
              lb.as_of_date, lb.last_accrual_date, lb.created_at, lb.updated_at
       FROM leave_balances lb
       WHERE lb.user_id = $1::uuid
         AND lb.leave_type IN ('vacationLeave', 'sickLeave')
       ORDER BY CASE lb.leave_type WHEN 'vacationLeave' THEN 0 ELSE 1 END`,
          [request.employee_id],
        );
        res.json(
          result.rows.map((row) => ({
            ...row,
            record_kind: 'credit_balance',
            earned_days: Number(row.earned_days || 0),
            used_days: Number(row.used_days || 0),
            pending_days: Number(row.pending_days || 0),
            adjusted_days: Number(row.adjusted_days || 0),
          })),
        );
      } catch (err) {
        console.error('[leave GET /:id/form-credits]', err);
        res.status(500).json({ error: 'Failed to fetch leave form credits' });
      }
    },

    getBalances: async (req, res) => {
      const requesterId = req.user?.id;
      const role = req.user?.role;
      if (!requesterId) return res.status(401).json({ error: 'Not authenticated' });
      const targetId = req.params.userId;
      const isPrivileged = role === 'admin' || role === 'hr';
      if (!isPrivileged && requesterId !== targetId) {
        return res.status(403).json({ error: 'Not allowed to view balances for this user' });
      }
      try {
        const rows = await pool.query(
          `SELECT lb.*, u.full_name AS employee_name,
              COALESCE(lt.display_name, lt.description, lb.leave_type) AS leave_type_display_name,
              lt.entitlement_basis
       FROM leave_balances lb
       LEFT JOIN users u ON u.id = lb.user_id
       LEFT JOIN leave_types lt ON lt.name = lb.leave_type
       WHERE lb.user_id = $1::uuid
         AND (
           lb.leave_type IN ('vacationLeave', 'sickLeave')
           OR lt.balance_ledger_type = 'ownBalance'
         )
       ORDER BY lb.leave_type ASC`,
          [targetId],
        );
        const mappedBalances = rows.rows.map((r) => ({
          id: r.id,
          user_id: r.user_id,
          leave_type: r.leave_type,
          leave_type_display_name: r.leave_type_display_name || r.leave_type,
          record_kind: 'credit_balance',
          entitlement_basis: normalizeEntitlementBasis(r.entitlement_basis, r.leave_type),
          employee_name: r.employee_name || null,
          earned_days: r.earned_days != null ? parseFloat(r.earned_days) : 0,
          used_days: r.used_days != null ? parseFloat(r.used_days) : 0,
          pending_days: r.pending_days != null ? parseFloat(r.pending_days) : 0,
          adjusted_days: r.adjusted_days != null ? parseFloat(r.adjusted_days) : 0,
          as_of_date: r.as_of_date ? String(r.as_of_date).slice(0, 10) : null,
          last_accrual_date: r.last_accrual_date ? String(r.last_accrual_date).slice(0, 10) : null,
          created_at: r.created_at,
          updated_at: r.updated_at,
        }));

        // Annual entitlements are not credit wallets. They are returned as clearly
        // marked, read-only summary rows so the employee UI can show yearly usage
        // separately from VL/SL credits.
        const officialDate = todayInHrmsTimezone();
        const currentYear = Number(officialDate.slice(0, 4));
        const startOfYear = `${currentYear}-01-01`;
        const endOfYear = `${currentYear}-12-31`;

        const annualTypesQ = await pool.query(
          `SELECT name,
              COALESCE(display_name, description, name) AS display_name,
              max_days,
              minimum_service_months,
              first_year_allowance,
              sex_eligibility,
              eligible_employment_types
       FROM leave_types
       WHERE is_active = true
         AND entitlement_basis = $1
         AND COALESCE(balance_ledger_type, 'none') = 'none'
         AND max_days IS NOT NULL
         AND max_days > 0
       ORDER BY display_name, name`,
          [ENTITLEMENT_BASES.ANNUAL],
        );
        const annualQuotaTypes = annualTypesQ.rows.map((row) => ({
          name: row.name,
          display: row.display_name || systemLeaveTypeDisplayName(row.name),
          quota: parseFloat(row.max_days),
          minimum_service_months: row.minimum_service_months || 0,
          first_year_allowance: row.first_year_allowance || 'full',
          sex: normalizeSexEligibility(row.sex_eligibility, row.name),
          employmentTypes: row.eligible_employment_types,
        }));

        // Skip employment- and sex-restricted types the employee cannot use
        let employeeSex = null;
        let employeeEmploymentType = null;
        let employeeHireDate = null;
        try {
          const sexRow = await pool.query(
            'SELECT sex, employment_type, date_hired::text AS date_hired FROM users WHERE id = $1::uuid LIMIT 1',
            [targetId],
          );
          employeeSex = sexRow.rows[0]?.sex || null;
          employeeHireDate = sexRow.rows[0]?.date_hired || null;
          employeeEmploymentType = sexRow.rows[0]?.employment_type || null;
        } catch (_) {}

        const applicableTypes = annualQuotaTypes.filter((t) => {
          if (t.employmentTypes != null && !t.employmentTypes.includes(employeeEmploymentType))
            return false;
          if (!t.sex || t.sex === 'any') return true;
          if (!employeeSex) return true; // unknown sex: show anyway
          return t.sex.toLowerCase() === employeeSex.toLowerCase();
        });

        // Skip types already covered by a persistent balance row
        const alreadyPresent = new Set(mappedBalances.map((b) => b.leave_type));
        const synthTypes = applicableTypes.filter((t) => !alreadyPresent.has(t.name));

        if (synthTypes.length > 0) {
          const synthTypeNames = synthTypes.map((t) => t.name);
          const usageQuery = await pool.query(
            `SELECT lr.start_date, lr.end_date, lr.status, lt.name AS leave_type
         FROM leave_requests lr
         JOIN leave_types lt ON lt.id = lr.leave_type_id
         WHERE (lr.user_id = $1::uuid OR lr.employee_id = $1::uuid)
           AND lr.start_date <= $3::date
           AND lr.end_date   >= $2::date
           AND lt.name = ANY($4::text[])
           AND lr.status IN ('pending', 'pending_department_head', 'pending_hr', 'pending_mayor', 'approved')`,
            [targetId, startOfYear, endOfYear, synthTypeNames],
          );

          // Build usage map per type
          const usageMap = {};
          for (const t of synthTypes) {
            usageMap[t.name] = { used: 0, pending: 0 };
          }

          const client = await pool.connect();
          try {
            for (const row of usageQuery.rows) {
              const startStr = toIsoDateStr(row.start_date);
              const endStr = toIsoDateStr(row.end_date);
              const days = await workingDaysWithinYear(
                client,
                targetId,
                startStr,
                endStr,
                currentYear,
              );
              const usageKey = row.leave_type;
              if (days > 0 && usageMap[usageKey]) {
                if (row.status === 'approved') {
                  usageMap[usageKey].used += days;
                } else {
                  usageMap[usageKey].pending += days;
                }
              }
            }
          } finally {
            client.release();
          }

          const employeeName = mappedBalances.length > 0 ? mappedBalances[0].employee_name : null;
          const today = officialDate;
          for (const t of synthTypes) {
            const allowance = annualAllowance(
              { ...t, max_days: t.quota },
              employeeHireDate,
              currentYear,
            );
            const service = serviceEligibility(t, employeeHireDate, officialDate);
            mappedBalances.push({
              id: `synth-${t.name}-${currentYear}`,
              user_id: targetId,
              leave_type: t.name,
              leave_type_display_name: t.display,
              employee_name: employeeName,
              record_kind: 'annual_entitlement',
              entitlement_basis: ENTITLEMENT_BASES.ANNUAL,
              entitlement_year: currentYear,
              earned_days: allowance.limit_days,
              full_limit_days: allowance.full_limit_days,
              calculated_days: allowance.calculated_days,
              prorated: allowance.prorated,
              eligibility_message: allowance.error_message || service.message,
              eligible: !allowance.error_message && service.eligible,
              eligible_from: service.eligible_from,
              used_days: usageMap[t.name].used,
              pending_days: usageMap[t.name].pending,
              adjusted_days: 0,
              as_of_date: today,
              last_accrual_date: null,
              created_at: null,
              updated_at: null,
            });
          }
        }

        res.json(mappedBalances);
      } catch (err) {
        console.error('[leave GET /balances/:userId]', err);
        res.status(500).json({ error: 'Failed to fetch leave balances' });
      }
    },

    adjustBalance: async (req, res) => {
      const reviewerId = req.user?.id;
      const targetId = req.params.userId;
      const b = req.body || {};
      const leaveType = (b.leave_type ?? b.leaveType ?? '').toString().trim();
      if (!leaveType) {
        return res.status(400).json({ error: 'Invalid or missing leave_type' });
      }
      let asOf = b.as_of_date ?? b.asOfDate;
      if (asOf === '' || asOf === undefined) asOf = null;
      if (asOf != null && !/^\d{4}-\d{2}-\d{2}$/.test(String(asOf))) {
        return res.status(400).json({ error: 'as_of_date must use YYYY-MM-DD' });
      }
      const daysChanged = b.adjustment_days ?? b.adjustmentDays;
      const remarks = b.remarks ?? b.reason;

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const employee = await client.query(
          'SELECT employment_type, leave_credit_eligible FROM users WHERE id = $1::uuid FOR SHARE',
          [targetId],
        );
        if (!employee.rows[0]) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Employee not found' });
        }
        if (!canAdjustLeaveCredits(employee.rows[0])) {
          await client.query('ROLLBACK');
          return res
            .status(400)
            .json({
              error:
                'This employee is not eligible for manual leave credit adjustments. JO/COS and employees with credits disabled are excluded.',
            });
        }
        const balanceBucket = await resolveBalanceLedgerLeaveType(client, leaveType);
        if (!balanceBucket) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: 'This leave type does not use leave credits and cannot be adjusted.',
          });
        }
        if (balanceBucket !== leaveType) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error: `${systemLeaveTypeDisplayName(leaveType)} uses the ${creditBalanceLabel(balanceBucket, leaveType)} balance bucket. Adjust that bucket instead.`,
          });
        }

        const result = await applyAdminLeaveBalanceAdjustment(client, {
          userId: targetId,
          leaveType,
          daysChanged,
          actorUserId: reviewerId || null,
          actorKind: req.user?.role || 'admin',
          remarks,
          asOfDate: asOf,
        });
        const r = result.row;
        const nameRow = await client.query('SELECT full_name FROM users WHERE id = $1::uuid', [
          targetId,
        ]);
        const employeeName = nameRow.rows[0]?.full_name || null;
        await client.query('COMMIT');

        const response = {
          id: r.id,
          user_id: r.user_id,
          leave_type: r.leave_type,
          employee_name: employeeName,
          earned_days: r.earned_days != null ? parseFloat(r.earned_days) : 0,
          used_days: r.used_days != null ? parseFloat(r.used_days) : 0,
          pending_days: r.pending_days != null ? parseFloat(r.pending_days) : 0,
          adjusted_days: r.adjusted_days != null ? parseFloat(r.adjusted_days) : 0,
          as_of_date: r.as_of_date ? String(r.as_of_date).slice(0, 10) : null,
          last_accrual_date: r.last_accrual_date ? String(r.last_accrual_date).slice(0, 10) : null,
          created_at: r.created_at,
          updated_at: r.updated_at,
        };
        broadcastLeaveUpdated('balance_updated', { user_id: targetId }, response);
        res.status(201).json(response);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave POST /balances/:userId/adjustments]', err);
        if (err && err.statusCode) {
          return res.status(err.statusCode).json({ error: err.message });
        }
        if (err && err.code === '23503') {
          return res.status(400).json({ error: 'Invalid user or leave type reference' });
        }
        if (err && err.code === '22007') {
          return res.status(400).json({ error: 'Invalid adjustment date' });
        }
        res.status(500).json({ error: err.message || 'Failed to adjust leave balance' });
      } finally {
        client.release();
      }
    },

    rejectBalanceReplacement: (_req, res) => {
      res.set('Allow', 'GET, POST');
      return res.status(405).json({
        error:
          'Direct balance replacement is disabled. Submit an audited balance adjustment instead.',
      });
    },
  };
};
