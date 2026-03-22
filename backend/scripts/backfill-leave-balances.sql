-- Backfill leave_balances for existing users
-- Run: psql -d hrms_plaridel -f backend/scripts/backfill-leave-balances.sql
--
-- For every user: inserts Vacation Leave (15 days) and Sick Leave (15 days).
-- Skips users who already have a balance for that leave type (ON CONFLICT DO NOTHING).

INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days)
SELECT id, 'vacationLeave', 15, 0, 0, 0 FROM users
UNION ALL
SELECT id, 'sickLeave', 15, 0, 0, 0 FROM users
ON CONFLICT (user_id, leave_type) DO NOTHING;
