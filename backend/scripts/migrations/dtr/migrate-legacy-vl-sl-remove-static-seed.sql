-- HRMS Plaridel — One-time transition: remove legacy static 15-day VL/SL seed
-- (Policy: earned VL/SL credits come only from monthly accrual at 1.25 days/month.)
--
-- Review with HR before running. Backup leave_balances first.
--
-- STRATEGY A (recommended first): rows that still look like untouched seed only
--    — earned_days = 15, no used/pending/adjusted activity
UPDATE leave_balances
SET
  earned_days = 0,
  last_accrual_date = NULL,
  as_of_date = CURRENT_DATE,
  updated_at = now()
WHERE leave_type IN ('vacationLeave', 'sickLeave')
  AND earned_days = 15
  AND COALESCE(used_days, 0) = 0
  AND COALESCE(pending_days, 0) = 0
  AND COALESCE(adjusted_days, 0) = 0;

-- STRATEGY B (optional): subtract exactly 15 from earned where it likely came from old seed
--    and employees already have accrual on top (e.g. earned = 16.25). Uncomment only if HR agrees.
-- UPDATE leave_balances
-- SET
--   earned_days = GREATEST(0, earned_days - 15),
--   as_of_date = CURRENT_DATE,
--   updated_at = now()
-- WHERE leave_type IN ('vacationLeave', 'sickLeave')
--   AND earned_days >= 15;

-- STRATEGY C (nuclear): reset ALL VL/SL earned to 0 — destroys any legitimate manual HR edits
--    on earned_days. Do not use unless approved.
-- UPDATE leave_balances
-- SET earned_days = 0, last_accrual_date = NULL, as_of_date = CURRENT_DATE, updated_at = now()
-- WHERE leave_type IN ('vacationLeave', 'sickLeave');

-- After migration: run monthly accrual (API or npm run leave:accrual) for the current month
-- so employees receive credit under the new policy.
