BEGIN;
SET LOCAL lock_timeout = '5s';

DO $migration$
DECLARE needs_baseline BOOLEAN := to_regclass('public.leave_month_end_notification_state') IS NULL;
BEGIN
CREATE TABLE IF NOT EXISTS leave_month_end_notification_state (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_month DATE NOT NULL CHECK (EXTRACT(DAY FROM service_month) = 1),
  totals JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, service_month)
);

-- Baseline only on first installation; reruns must not suppress pending alerts.
IF needs_baseline THEN
WITH movements AS (
  SELECT user_id, service_month, leave_type, credited_days AS earned, 0::numeric AS deducted
  FROM leave_monthly_accrual_postings
  UNION ALL
  SELECT user_id, service_month, leave_type, 0::numeric, deducted_days
  FROM leave_attendance_deductions
), grouped AS (
  SELECT user_id, service_month, leave_type, SUM(earned) AS earned, SUM(deducted) AS deducted
  FROM movements GROUP BY user_id, service_month, leave_type
)
INSERT INTO leave_month_end_notification_state(user_id, service_month, totals)
SELECT user_id, service_month, jsonb_object_agg(leave_type,
  jsonb_build_object('earned', earned, 'deducted', deducted))
FROM grouped GROUP BY user_id, service_month
ON CONFLICT (user_id, service_month) DO NOTHING;
END IF;
END;
$migration$;

CREATE UNIQUE INDEX IF NOT EXISTS user_notifications_month_end_failure_idx
  ON user_notifications(user_id, (metadata->>'service_month'))
  WHERE type = 'leave_month_end_failed';

COMMIT;
