// Leave Card selection requires a current assignment and either credit
// eligibility or historical VL/SL movements.
const leaveCardEligibilitySql = `(EXISTS (
  SELECT 1 FROM assignments card_assignment
  WHERE card_assignment.employee_id = u.id
    AND COALESCE(card_assignment.is_active, true) = true
    AND card_assignment.effective_from <= (now() AT TIME ZONE 'Asia/Manila')::date
    AND (card_assignment.effective_to IS NULL
      OR card_assignment.effective_to >= (now() AT TIME ZONE 'Asia/Manila')::date)
) AND (
  COALESCE(u.leave_credit_eligible, true) = true
  OR EXISTS (
    SELECT 1 FROM leave_balances card_balance
    WHERE card_balance.user_id = u.id
      AND card_balance.leave_type IN ('vacationLeave', 'sickLeave')
      AND (COALESCE(card_balance.earned_days, 0) <> 0
        OR COALESCE(card_balance.used_days, 0) <> 0
        OR COALESCE(card_balance.pending_days, 0) <> 0
        OR COALESCE(card_balance.adjusted_days, 0) <> 0)
  )
  OR EXISTS (
    SELECT 1 FROM leave_balance_ledger card_ledger
    WHERE card_ledger.user_id = u.id
      AND card_ledger.leave_type IN ('vacationLeave', 'sickLeave')
  )
  OR EXISTS (
    SELECT 1 FROM leave_requests card_request
    JOIN leave_types card_type ON card_type.id = card_request.leave_type_id
    WHERE COALESCE(card_request.user_id, card_request.employee_id) = u.id
      AND card_request.status = 'approved'
      AND (card_type.name IN ('vacationLeave', 'sickLeave')
        OR card_type.balance_ledger_type IN ('vacationLeave', 'sickLeave'))
  )
))`;

module.exports = {leaveCardEligibilitySql};
