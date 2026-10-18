'use strict';
module.exports = function createLeaveComponent({
  NO_CREDIT_LEDGER_TYPE,
  OWN_BALANCE_LEDGER_TYPE,
  calculateApprovalCreditHeadroom,
  calculateCreditReservation,
  creditBalanceLabel,
  defaultLedgerTypeForLeaveType,
  fetchBalanceSnapshot,
  insertLeaveBalanceLedger,
  normalizeLedgerType,
}) {
  /**
   * CSC practice: mandatory/forced leave is charged against vacation leave credits.
   * Maps a leave_requests.leave type name to a leave_balances row key, or null
   * when the type is configured as a no-credit entitlement/statutory leave.
   */
  function balanceLedgerLeaveType(leaveTypeName) {
    if (!leaveTypeName) return leaveTypeName;
    const configured = defaultLedgerTypeForLeaveType(leaveTypeName);
    if (configured === NO_CREDIT_LEDGER_TYPE) return null;
    if (configured === OWN_BALANCE_LEDGER_TYPE) return leaveTypeName;
    return configured;
  }

  async function resolveBalanceLedgerConfigType(client, leaveTypeName) {
    if (!leaveTypeName) return NO_CREDIT_LEDGER_TYPE;
    const fallback = defaultLedgerTypeForLeaveType(leaveTypeName);
    if (!client) return fallback;
    const q = await client.query(
      'SELECT balance_ledger_type FROM leave_types WHERE name = $1 LIMIT 1',
      [leaveTypeName],
    );
    return normalizeLedgerType(q.rows[0]?.balance_ledger_type, leaveTypeName);
  }

  async function resolveBalanceLedgerLeaveType(client, leaveTypeName) {
    const configured = await resolveBalanceLedgerConfigType(client, leaveTypeName);
    if (configured === NO_CREDIT_LEDGER_TYPE) return null;
    if (configured === OWN_BALANCE_LEDGER_TYPE) return leaveTypeName;
    return configured;
  }

  /** Matches Flutter LeaveBalance.remainingDays: earned - used + adjusted */
  function ledgerRemainingFromBalancesRow(row) {
    if (!row) return 0;
    const e = parseFloat(row.earned_days ?? 0);
    const u = parseFloat(row.used_days ?? 0);
    const a = parseFloat(row.adjusted_days ?? 0);
    return e - u + a;
  }

  /** Matches Flutter LeaveBalance.availableDays: remaining - pending */
  function ledgerAvailableFromBalancesRow(row) {
    const pending = row ? parseFloat(row.pending_days ?? 0) : 0;
    return ledgerRemainingFromBalancesRow(row) - pending;
  }

  function reservedCreditDaysFromRequest(row) {
    const days = row?.reserved_credit_days != null ? parseFloat(row.reserved_credit_days) : 0;
    return Number.isFinite(days) && days > 0 ? days : 0;
  }

  /** Normalized snapshot for leave_balance_ledger old/new values. */
  function balanceRowToSnapshot(row) {
    if (!row) {
      return { earned_days: 0, used_days: 0, pending_days: 0, adjusted_days: 0 };
    }
    return {
      earned_days: parseFloat(row.earned_days ?? 0),
      used_days: parseFloat(row.used_days ?? 0),
      pending_days: parseFloat(row.pending_days ?? 0),
      adjusted_days: parseFloat(row.adjusted_days ?? 0),
    };
  }

  async function upsertLeaveBalanceDeduction(
    client,
    userId,
    leaveTypeName,
    daysToDeduct,
    options = {},
  ) {
    if (!userId || !leaveTypeName) return;
    const days = daysToDeduct != null ? parseFloat(daysToDeduct) : 0;
    const allowNegative = options.allowNegative === true;
    /** When true (HR final approval only): clear the submit-time pending reservation before adding used_days. */
    const decrementPendingDays = options.decrementPendingDays === true;
    const pendingDaysToRelease = decrementPendingDays
      ? parseFloat(options.pendingDaysToRelease ?? days)
      : 0;
    if (!Number.isFinite(days) || days < 0) return;
    if (!Number.isFinite(pendingDaysToRelease) || pendingDaysToRelease < 0) return;
    if (days <= 0 && pendingDaysToRelease <= 0) return;

    const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
    if (!ledgerType) return null;

    const bal = await client.query(
      `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     LIMIT 1
     FOR UPDATE`,
      [userId, ledgerType],
    );
    const remaining = ledgerRemainingFromBalancesRow(bal.rows[0]);
    const pending = bal.rows.length > 0 ? parseFloat(bal.rows[0].pending_days ?? 0) : 0;
    const available = remaining - pending;

    if (decrementPendingDays) {
      // This request may reserve only part of its requested days. Its own hold is
      // available for approval; pending credits held by other requests are not.
      const approvalHeadroom = calculateApprovalCreditHeadroom({
        remainingDays: remaining,
        pendingDays: pending,
        reservedCreditDays: pendingDaysToRelease,
      });
      if (!allowNegative && days > approvalHeadroom) {
        const bucketLabel = creditBalanceLabel(ledgerType, leaveTypeName);
        const err = new Error(
          `Insufficient ${bucketLabel} balance for the paid allocation. Available ${approvalHeadroom.toFixed(2)}, requested with pay ${days.toFixed(2)}.`,
        );
        err.statusCode = 400;
        throw err;
      }
    } else {
      // Forced deduction (and any use not tied to a pending reservation): cannot take more than available.
      if (!allowNegative && days > available) {
        const bucketLabel = creditBalanceLabel(ledgerType, leaveTypeName);
        const prefix = `Insufficient ${bucketLabel} balance`;
        const msg = `${prefix}. Available ${available.toFixed(2)} (remaining ${remaining.toFixed(2)}, pending ${pending.toFixed(2)}), requested ${days.toFixed(2)}.`;
        const err = new Error(msg);
        err.statusCode = 400;
        throw err;
      }
    }

    if (days > 0) {
      await client.query(
        `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days, as_of_date, last_accrual_date, created_at, updated_at)
       VALUES ($1::uuid, $2::text, 0, $3::numeric, 0, 0, now()::date, now()::date, now(), now())
       ON CONFLICT (user_id, leave_type)
       DO UPDATE SET used_days = COALESCE(leave_balances.used_days, 0) + EXCLUDED.used_days,
                     updated_at = now()`,
        [userId, ledgerType, days],
      );
    }

    // Final approval: move days out of pending (submit-time reservation) into used — same ledger row as submit/PUT.
    if (decrementPendingDays && pendingDaysToRelease > 0) {
      await client.query(
        `UPDATE leave_balances
       SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
           updated_at = now()
       WHERE user_id = $1::uuid AND leave_type = $2::text`,
        [userId, ledgerType, pendingDaysToRelease],
      );
    }

    const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
    const remainingOut = afterSnap.earned_days - afterSnap.used_days + afterSnap.adjusted_days;

    const lc = options.ledgerContext;
    if (lc) {
      const beforeSnap = balanceRowToSnapshot(bal.rows[0]);
      if (decrementPendingDays) {
        if (afterSnap.used_days !== beforeSnap.used_days) {
          await insertLeaveBalanceLedger(client, {
            userId,
            leaveType: ledgerType,
            action: lc.action || 'leave_approved',
            affectedBucket: 'used',
            daysChanged: afterSnap.used_days - beforeSnap.used_days,
            oldValue: beforeSnap.used_days,
            newValue: afterSnap.used_days,
            relatedLeaveRequestId: lc.leaveRequestId || null,
            actorUserId: lc.actorUserId || null,
            actorKind: lc.actorKind || 'admin',
            remarks: lc.remarks || null,
            metadataJson: lc.metadataJson || null,
          });
        }
        await insertLeaveBalanceLedger(client, {
          userId,
          leaveType: ledgerType,
          action: lc.action || 'leave_approved',
          affectedBucket: 'pending',
          daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
          oldValue: beforeSnap.pending_days,
          newValue: afterSnap.pending_days,
          relatedLeaveRequestId: lc.leaveRequestId || null,
          actorUserId: lc.actorUserId || null,
          actorKind: lc.actorKind || 'admin',
          remarks: lc.remarks || null,
          metadataJson: lc.metadataJson || null,
        });
      } else {
        await insertLeaveBalanceLedger(client, {
          userId,
          leaveType: ledgerType,
          action: lc.action || 'forced_leave_deduction',
          affectedBucket: 'used',
          daysChanged: afterSnap.used_days - beforeSnap.used_days,
          oldValue: beforeSnap.used_days,
          newValue: afterSnap.used_days,
          relatedLeaveRequestId: lc.leaveRequestId || null,
          actorUserId: lc.actorUserId || null,
          actorKind: lc.actorKind || 'admin',
          remarks: lc.remarks || null,
          metadataJson: lc.metadataJson || null,
        });
      }
    }

    return remainingOut;
  }

  async function reservePendingLeaveBalance(
    client,
    {
      userId,
      leaveTypeName,
      days,
      leaveRequestId,
      actorUserId,
      actorKind = 'user',
      action = 'leave_submitted',
      remarks = null,
      metadataJson = null,
    },
  ) {
    const d = days != null ? parseFloat(days) : 0;
    if (!userId || !leaveTypeName || !Number.isFinite(d) || d <= 0) return null;
    const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
    if (!ledgerType) return null;

    await client.query(
      `INSERT INTO leave_balances (
       user_id, leave_type, earned_days, used_days, pending_days,
       adjusted_days, as_of_date, last_accrual_date, created_at, updated_at
     )
     VALUES ($1::uuid, $2::text, 0, 0, 0, 0, now()::date, now()::date, now(), now())
     ON CONFLICT (user_id, leave_type) DO NOTHING`,
      [userId, ledgerType],
    );
    const lockedBalance = await client.query(
      `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     FOR UPDATE`,
      [userId, ledgerType],
    );
    const beforeSnap = balanceRowToSnapshot(lockedBalance.rows[0]);
    const reservation = calculateCreditReservation({
      requestedDays: d,
      availableDays: ledgerAvailableFromBalancesRow(lockedBalance.rows[0]),
    });

    if (leaveRequestId) {
      await client.query(
        `UPDATE leave_requests
       SET reserved_credit_days = $2::numeric,
           updated_at = now()
       WHERE id = $1`,
        [leaveRequestId, reservation.reservedDays],
      );
    }

    if (reservation.reservedDays <= 0) {
      return { ledgerType, ...reservation };
    }

    await client.query(
      `UPDATE leave_balances
     SET pending_days = COALESCE(pending_days, 0) + $3::numeric,
         updated_at = now()
     WHERE user_id = $1::uuid AND leave_type = $2::text`,
      [userId, ledgerType, reservation.reservedDays],
    );
    const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
    await insertLeaveBalanceLedger(client, {
      userId,
      leaveType: ledgerType,
      action,
      affectedBucket: 'pending',
      daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
      oldValue: beforeSnap.pending_days,
      newValue: afterSnap.pending_days,
      relatedLeaveRequestId: leaveRequestId || null,
      actorUserId: actorUserId || null,
      actorKind,
      remarks,
      metadataJson: {
        ...(metadataJson || {}),
        requested_days: reservation.requestedDays,
        reserved_credit_days: reservation.reservedDays,
        potential_without_pay_days: reservation.potentialWithoutPayDays,
      },
    });
    return { ledgerType, ...reservation };
  }

  async function releasePendingLeaveBalance(
    client,
    {
      userId,
      leaveTypeName,
      days,
      leaveRequestId,
      actorUserId,
      actorKind = 'admin',
      action,
      remarks = null,
      metadataJson = null,
    },
  ) {
    const d = days != null ? parseFloat(days) : 0;
    if (!userId || !leaveTypeName || !Number.isFinite(d) || d <= 0) return null;
    const ledgerType = await resolveBalanceLedgerLeaveType(client, leaveTypeName);
    if (!ledgerType) return null;

    const beforeSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
    await client.query(
      `UPDATE leave_balances
     SET pending_days = GREATEST(0, COALESCE(pending_days, 0) - $3::numeric),
         updated_at = now()
     WHERE user_id = $1::uuid AND leave_type = $2::text`,
      [userId, ledgerType, d],
    );
    const afterSnap = await fetchBalanceSnapshot(client, userId, ledgerType);
    await insertLeaveBalanceLedger(client, {
      userId,
      leaveType: ledgerType,
      action,
      affectedBucket: 'pending',
      daysChanged: afterSnap.pending_days - beforeSnap.pending_days,
      oldValue: beforeSnap.pending_days,
      newValue: afterSnap.pending_days,
      relatedLeaveRequestId: leaveRequestId || null,
      actorUserId: actorUserId || null,
      actorKind,
      remarks,
      metadataJson,
    });
    return ledgerType;
  }
  return {
    balanceLedgerLeaveType,
    resolveBalanceLedgerConfigType,
    resolveBalanceLedgerLeaveType,
    ledgerRemainingFromBalancesRow,
    ledgerAvailableFromBalancesRow,
    reservedCreditDaysFromRequest,
    balanceRowToSnapshot,
    upsertLeaveBalanceDeduction,
    reservePendingLeaveBalance,
    releasePendingLeaveBalance,
  };
};
