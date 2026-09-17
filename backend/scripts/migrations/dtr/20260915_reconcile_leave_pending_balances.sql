-- Repair legacy pending leave-credit totals from the authoritative active
-- request reservations. Completed, returned, rejected, and cancelled requests
-- must not retain pending credits.

BEGIN;

WITH expected_pending AS (
  SELECT
    COALESCE(lr.user_id, lr.employee_id) AS user_id,
    CASE
      WHEN lt.balance_ledger_type = 'ownBalance' THEN lt.name
      ELSE lt.balance_ledger_type
    END AS leave_type,
    SUM(COALESCE(lr.reserved_credit_days, 0))::numeric AS pending_days
  FROM leave_requests lr
  JOIN leave_types lt ON lt.id = lr.leave_type_id
  WHERE lr.status IN ('pending', 'pending_department_head', 'pending_hr')
    AND COALESCE(lt.balance_ledger_type, 'none') <> 'none'
  GROUP BY
    COALESCE(lr.user_id, lr.employee_id),
    CASE
      WHEN lt.balance_ledger_type = 'ownBalance' THEN lt.name
      ELSE lt.balance_ledger_type
    END
), corrections AS (
  SELECT
    lb.user_id,
    lb.leave_type,
    COALESCE(lb.pending_days, 0)::numeric AS old_pending_days,
    COALESCE(ep.pending_days, 0)::numeric AS expected_pending_days
  FROM leave_balances lb
  LEFT JOIN expected_pending ep
    ON ep.user_id = lb.user_id
   AND ep.leave_type = lb.leave_type
  WHERE COALESCE(lb.pending_days, 0) IS DISTINCT FROM
        COALESCE(ep.pending_days, 0)
)
INSERT INTO leave_balance_ledger (
  user_id,
  leave_type,
  action,
  affected_bucket,
  days_changed,
  old_value,
  new_value,
  actor_kind,
  remarks,
  metadata_json
)
SELECT
  user_id,
  leave_type,
  'pending_balance_reconciled',
  'pending',
  expected_pending_days - old_pending_days,
  old_pending_days,
  expected_pending_days,
  'system',
  'Reconciled pending credits from active leave request reservations.',
  jsonb_build_object('reason', 'active_request_reservation_reconciliation')
FROM corrections;

WITH expected_pending AS (
  SELECT
    COALESCE(lr.user_id, lr.employee_id) AS user_id,
    CASE
      WHEN lt.balance_ledger_type = 'ownBalance' THEN lt.name
      ELSE lt.balance_ledger_type
    END AS leave_type,
    SUM(COALESCE(lr.reserved_credit_days, 0))::numeric AS pending_days
  FROM leave_requests lr
  JOIN leave_types lt ON lt.id = lr.leave_type_id
  WHERE lr.status IN ('pending', 'pending_department_head', 'pending_hr')
    AND COALESCE(lt.balance_ledger_type, 'none') <> 'none'
  GROUP BY
    COALESCE(lr.user_id, lr.employee_id),
    CASE
      WHEN lt.balance_ledger_type = 'ownBalance' THEN lt.name
      ELSE lt.balance_ledger_type
    END
)
UPDATE leave_balances lb
SET pending_days = COALESCE(ep.pending_days, 0),
    as_of_date = CURRENT_DATE,
    updated_at = now()
FROM (
  SELECT
    balances.user_id,
    balances.leave_type,
    expected_pending.pending_days
  FROM leave_balances balances
  LEFT JOIN expected_pending
    ON expected_pending.user_id = balances.user_id
   AND expected_pending.leave_type = balances.leave_type
) ep
WHERE lb.user_id = ep.user_id
  AND lb.leave_type = ep.leave_type
  AND COALESCE(lb.pending_days, 0) IS DISTINCT FROM
      COALESCE(ep.pending_days, 0);

COMMIT;
