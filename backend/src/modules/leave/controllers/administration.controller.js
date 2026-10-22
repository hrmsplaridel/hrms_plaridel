'use strict';
module.exports = function createLeaveControllers({
  applyYearEndForcedLeaveDeductions,
  broadcastAppEvent,
  broadcastLeaveUpdated,
  getYearEndForcedLeaveCompliance,
  leaveNotifications,
  notificationMonthForTarget,
  notifyLeaveMonthEnd,
  notifyLeaveMonthEndFailure,
  notifySafe,
  pool,
  runLeaveMonthlyAccrual,
  runMonthlyAttendanceDeductions,
  upsertLeaveBalanceDeduction,
  yearEndManilaYearNow,
}) {
  return {
    deductForcedLeave: async (req, res) => {
      const reviewerId = req.user?.id;
      if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
      const userId = (req.body?.user_id || '').toString().trim();
      const daysRaw = req.body?.days_to_deduct ?? req.body?.daysToDeduct;
      const days = daysRaw != null && daysRaw !== '' ? parseFloat(daysRaw) : NaN;
      const yearRaw = req.body?.year ?? req.body?.deduction_year ?? req.body?.deductionYear;
      const yearText = yearRaw != null ? String(yearRaw).trim() : '';
      const year = /^\d{4}$/.test(yearText) ? parseInt(yearText, 10) : NaN;
      const remarks = (req.body?.remarks || '').toString().trim() || null;
      const allowNegative = req.body?.allow_negative_balance === true;
      if (!userId) return res.status(400).json({ error: 'user_id is required' });
      if (!Number.isFinite(days) || days <= 0) {
        return res.status(400).json({ error: 'days_to_deduct must be greater than 0' });
      }
      const maxAllowedYear = new Date().getFullYear() + 1;
      if (!Number.isInteger(year) || year < 1900 || year > maxAllowedYear) {
        return res.status(400).json({ error: `year must be between 1900 and ${maxAllowedYear}` });
      }
      if (year >= yearEndManilaYearNow()) {
        return res.status(409).json({
          error: `Year-end deductions for ${year} cannot be applied until that calendar year has closed.`,
        });
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const userQ = await client.query(
          'SELECT id FROM users WHERE id = $1::uuid AND (is_active IS NULL OR is_active = true) LIMIT 1',
          [userId],
        );
        if (userQ.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Target employee not found or inactive' });
        }
        const duplicateQ = await client.query(
          `SELECT id, created_at
       FROM leave_balance_ledger
       WHERE user_id = $1::uuid
         AND leave_type = 'vacationLeave'
         AND action = 'forced_leave_deduction'
         AND (
           metadata_json->>'year' = $2::text
           OR metadata_json->>'deduction_year' = $2::text
         )
       LIMIT 1`,
          [userId, String(year)],
        );
        if (duplicateQ.rows.length > 0) {
          await client.query('ROLLBACK');
          return res.status(409).json({
            error: `Year-end forced leave deduction for ${year} has already been applied for this employee.`,
            year,
            existing_ledger_id: duplicateQ.rows[0].id,
            applied_at: duplicateQ.rows[0].created_at,
          });
        }
        const remaining = await upsertLeaveBalanceDeduction(
          client,
          userId,
          'mandatoryForcedLeave',
          days,
          {
            allowNegative,
            ledgerContext: {
              action: 'forced_leave_deduction',
              actorUserId: reviewerId,
              actorKind: 'admin',
              remarks,
              metadataJson: {
                source: 'forced_leave_deduction',
                year,
                deduction_year: year,
                requested_leave_type: 'mandatoryForcedLeave',
                deducted_days: days,
                allow_negative_balance: allowNegative,
              },
            },
          },
        );
        const balSnap = await client.query(
          `SELECT
         COALESCE(earned_days, 0) - COALESCE(used_days, 0) + COALESCE(adjusted_days, 0) AS rem,
         COALESCE(earned_days, 0) - COALESCE(used_days, 0) + COALESCE(adjusted_days, 0) - COALESCE(pending_days, 0) AS avail
       FROM leave_balances
       WHERE user_id = $1::uuid AND leave_type = 'vacationLeave'
       LIMIT 1`,
          [userId],
        );
        const remainingAfter =
          balSnap.rows.length > 0 ? parseFloat(balSnap.rows[0].rem ?? 0) : remaining;
        const availableAfter =
          balSnap.rows.length > 0 ? parseFloat(balSnap.rows[0].avail ?? 0) : remainingAfter;

        await client.query('COMMIT');
        notifySafe(() =>
          leaveNotifications.notifyForcedLeaveDeductionApplied(pool, {
            employeeUserId: userId,
            deductedDays: days,
            remainingDays: availableAfter,
            year,
            remarks,
          }),
        );
        const response = {
          user_id: userId,
          leave_type: 'vacationLeave',
          deducted_days: days,
          year,
          remaining_days: remainingAfter,
          available_days: availableAfter,
          remarks,
          applied_at: new Date().toISOString(),
        };
        broadcastLeaveUpdated('forced_leave_deduction', { user_id: userId }, response);
        res.status(201).json(response);
      } catch (err) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
        console.error('[leave POST /admin/forced-leave-deduction]', err);
        if (err && err.statusCode) return res.status(err.statusCode).json({ error: err.message });
        res.status(500).json({ error: 'Failed to apply forced leave deduction' });
      } finally {
        client.release();
      }
    },

    runMonthlyAccrual: async (req, res) => {
      let notificationMonth = null;
      let notificationDryRun = true;
      try {
        const dryRun =
          req.body?.dry_run === true || req.query?.dry_run === '1' || req.query?.dry_run === 'true';

        const rawMax = req.body?.max_catch_up_months ?? req.query?.max_catch_up_months;
        const maxCatchUpMonths =
          rawMax != null && rawMax !== '' ? parseInt(String(rawMax), 10) : undefined;
        const targetMonth =
          req.body?.target_month ??
          req.body?.year_month ??
          req.query?.target_month ??
          req.query?.year_month;

        notificationDryRun = dryRun;
        notificationMonth = notificationMonthForTarget(targetMonth);
        const accrualResult = await runLeaveMonthlyAccrual(pool, {
          dryRun,
          maxCatchUpMonths: Number.isFinite(maxCatchUpMonths) ? maxCatchUpMonths : undefined,
          targetMonth: targetMonth ? String(targetMonth).trim() : undefined,
        });

        const previewEarnedByUser = new Map();
        if (dryRun) {
          for (const detail of accrualResult.details || []) {
            if (
              detail.leave_type === 'vacationLeave' &&
              (detail.action === 'would_apply' || detail.action === 'would_adjust')
            ) {
              const key = String(detail.user_id);
              const earnedMovement = Number(detail.balance_delta ?? detail.days_added ?? 0);
              previewEarnedByUser.set(key, (previewEarnedByUser.get(key) || 0) + earnedMovement);
            }
          }
        }

        const attendanceDeductions = await runMonthlyAttendanceDeductions(pool, {
          dryRun,
          targetMonth: accrualResult.targetYearMonth,
          balanceEarnedAdjustmentsByUser: previewEarnedByUser,
        });
        const result = { ...accrualResult, attendanceDeductions };
        await notifyLeaveMonthEnd(pool, { targetYearMonth: result.targetYearMonth, dryRun });

        const attendanceBalanceDetails = (attendanceDeductions.details || []).filter(
          (item) => Number(item.balance_delta || 0) !== 0,
        );
        if (
          !result.dryRun &&
          (result.rowsUpdated > 0 ||
            result.missingBalanceRowsCreated > 0 ||
            attendanceBalanceDetails.length > 0)
        ) {
          const affectedUserIds = [
            ...new Set(
              [
                ...(Array.isArray(result.details) ? result.details : []),
                ...attendanceBalanceDetails,
              ]
                .filter(
                  (item) =>
                    item.action === 'applied' ||
                    item.action === 'adjusted' ||
                    item.created_balance_row === true ||
                    Number(item.balance_delta || 0) !== 0,
                )
                .map((item) => item.user_id)
                .filter(Boolean)
                .map((id) => String(id)),
            ),
          ];
          if (affectedUserIds.length > 0) {
            broadcastLeaveUpdated(
              'monthly_accrual',
              { user_id: affectedUserIds[0] },
              {
                userIds: affectedUserIds,
                user_ids: affectedUserIds,
                targetYearMonth: result.targetYearMonth,
                rowsUpdated: result.rowsUpdated,
                rowsSkipped: result.rowsSkipped,
                missingBalanceRowsCreated: result.missingBalanceRowsCreated || 0,
                attendanceRowsUpdated: attendanceDeductions.rowsUpdated,
                attendanceDeductedDays: attendanceDeductions.totalDeductedDays,
                attendanceWithoutPayDays: attendanceDeductions.totalWithoutPayDays,
                leaveTypes: result.leaveTypes,
                balanceChanged: true,
              },
            );
          }
        }
        res.status(200).json(result);
      } catch (err) {
        if (!notificationDryRun && notificationMonth) {
          await notifyLeaveMonthEndFailure(pool, {
            targetYearMonth: notificationMonth,
            actorId: req.user.id,
          });
        }
        console.error('[leave POST /admin/monthly-accrual]', err);
        res.status(400).json({ error: err.message || 'Monthly accrual failed' });
      }
    },

    previewYearEndForcedLeave: async (req, res) => {
      try {
        const yearRaw = req.query.year;
        const year = yearRaw ? parseInt(String(yearRaw).trim(), 10) : yearEndManilaYearNow();
        const maxYear = new Date().getFullYear() + 1;
        if (!Number.isInteger(year) || year < 1900 || year > maxYear) {
          return res.status(400).json({ error: `year must be between 1900 and ${maxYear}` });
        }
        const result = await getYearEndForcedLeaveCompliance(pool, { year });
        res.json(result);
      } catch (err) {
        console.error('[leave GET /admin/year-end-forced-leave]', err);
        res.status(500).json({ error: 'Failed to fetch year-end forced leave compliance' });
      }
    },

    applyYearEndForcedLeave: async (req, res) => {
      try {
        const actorUserId = req.user?.id;
        const yearRaw = req.body?.year ?? req.query?.year;
        const year = yearRaw ? parseInt(String(yearRaw).trim(), 10) : yearEndManilaYearNow();
        const maxYear = new Date().getFullYear() + 1;
        if (!Number.isInteger(year) || year < 1900 || year > maxYear) {
          return res.status(400).json({ error: `year must be between 1900 and ${maxYear}` });
        }

        const dryRun =
          req.body?.dry_run === true ||
          req.body?.dryRun === true ||
          req.query?.dry_run === '1' ||
          req.query?.dry_run === 'true';

        if (!dryRun && year >= yearEndManilaYearNow()) {
          return res.status(409).json({
            error: `Year-end deductions for ${year} cannot be applied until that calendar year has closed. Preview remains available.`,
          });
        }

        const rawIds = req.body?.employee_ids ?? req.body?.employeeIds;
        const employeeIds =
          Array.isArray(rawIds) && rawIds.length > 0
            ? rawIds.map((id) => String(id).trim()).filter(Boolean)
            : null;

        const remarks = (req.body?.remarks || '').toString().trim() || null;

        const result = await applyYearEndForcedLeaveDeductions(pool, {
          year,
          actorUserId,
          dryRun,
          employeeIds,
          remarks,
        });

        const appliedCount =
          (result.summary?.applied || 0) + (result.summary?.partially_applied || 0);
        if (!dryRun && appliedCount > 0) {
          broadcastAppEvent('leave_updated', {
            action: 'forced_leave_deduction',
            source: 'year_end_bulk',
            year,
            applied: appliedCount,
          });
        }

        res.status(dryRun ? 200 : 201).json(result);
      } catch (err) {
        console.error('[leave POST /admin/year-end-forced-leave/apply]', err);
        res.status(500).json({ error: 'Failed to apply year-end forced leave deductions' });
      }
    },
  };
};
