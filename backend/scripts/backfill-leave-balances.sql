-- Backfill leave_balances for existing users
-- Run: psql -d hrms_plaridel -f backend/scripts/backfill-leave-balances.sql
--
-- Inserts VL + SL rows with earned_days = 0 (credits accrue via monthly job only, 1.25/mo each).
-- Skips users who already have a balance for that leave type (ON CONFLICT DO NOTHING).

INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days)
SELECT id, 'vacationLeave', 0, 0, 0, 0 FROM users
UNION ALL
SELECT id, 'sickLeave', 0, 0, 0, 0 FROM users
ON CONFLICT (user_id, leave_type) DO NOTHING;
